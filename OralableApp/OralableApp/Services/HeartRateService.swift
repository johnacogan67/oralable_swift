import Foundation
import Accelerate

/// A service to extract Heart Rate from raw PPG IR data and determine worn status.
class HeartRateService {
    
    // Constants for physiological bounds
    private let minBPM = 40.0
    private let maxBPM = 180.0
    private let sampleRate = 100.0 // Hz
    private let windowSize = 500   // 5 seconds of data for stability
    
    // State
    private var irBuffer: [Double] = []
    
    /// Result structure for the UI
    struct HRResult {
        let bpm: Int
        let confidence: Double // 0.0 to 1.0
        let isWorn: Bool
    }
    
    /// Processes a new batch of IR samples
    func process(samples: [Double]) -> HRResult {
        irBuffer.append(contentsOf: samples)
        
        // Maintain window size
        if irBuffer.count > windowSize {
            irBuffer.removeFirst(irBuffer.count - windowSize)
        }
        
        guard irBuffer.count >= windowSize else {
            return HRResult(bpm: 0, confidence: 0, isWorn: false)
        }
        
        // 1. DC Removal & Bandpass (Simplified for CPU efficiency)
        let filtered = applyBandpassFilter(irBuffer)
        
        // 2. Peak Detection
        let peaks = findPeaks(in: filtered)
        
        // 3. Calculate BPM
        let result = calculateBPM(from: peaks)
        
        // 4. Perfusion Index (AC/DC Ratio check)
        let dcComponent = irBuffer.reduce(0, +) / Double(irBuffer.count)
        let acComponent = filtered.map { abs($0) }.reduce(0, +) / Double(filtered.count)
        let perfusionIndex = (acComponent / dcComponent) * 100
        
        // Device is worn if we have a stable BPM and a minimum perfusion index (usually > 0.1%)
        let isWorn = result.bpm > 0 && result.confidence > 0.6 && perfusionIndex > 0.05
        
        return HRResult(bpm: result.bpm, confidence: result.confidence, isWorn: isWorn)
    }
    
    private func applyBandpassFilter(_ data: [Double]) -> [Double] {
        // Simple Mean Subtraction to center the signal (High Pass)
        let mean = data.reduce(0, +) / Double(data.count)
        let centered = data.map { $0 - mean }
        
        // Basic 5-point Moving Average to smooth high freq noise (Low Pass)
        var smoothed = centered
        for i in 2..<centered.count-2 {
            smoothed[i] = (centered[i-2] + centered[i-1] + centered[i] + centered[i+1] + centered[i+2]) / 5.0
        }
        return smoothed
    }
    
    private func findPeaks(in data: [Double]) -> [Int] {
        var peaks: [Int] = []
        let threshold = (data.max() ?? 0) * 0.5 // Adaptive threshold
        
        for i in 1..<data.count-1 {
            if data[i] > data[i-1] && data[i] > data[i+1] && data[i] > threshold {
                // Ensure peaks aren't too close (minimum 300ms between beats)
                if let lastPeak = peaks.last {
                    if (i - lastPeak) > Int(sampleRate * 0.3) {
                        peaks.append(i)
                    }
                } else {
                    peaks.append(i)
                }
            }
        }
        return peaks
    }
    
    private func calculateBPM(from peaks: [Int]) -> (bpm: Int, confidence: Double) {
        guard peaks.count > 3 else { return (0, 0.0) }
        
        var intervals: [Double] = []
        for i in 1..<peaks.count {
            intervals.append(Double(peaks[i] - peaks[i-1]))
        }
        
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        let bpm = 60.0 / (avgInterval / sampleRate)
        
        // Confidence based on interval regularity (Standard Deviation)
        let variance = intervals.map { pow($0 - avgInterval, 2) }.reduce(0, +) / Double(intervals.count)
        let stdDev = sqrt(variance)
        let confidence = max(0, 1.0 - (stdDev / avgInterval))
        
        if bpm >= minBPM && bpm <= maxBPM {
            return (Int(bpm), confidence)
        } else {
            return (0, 0.0)
        }
    }
}