import Foundation

/// A dedicated service to extract Heart Rate from cleaned PPG signals (Green Channel).
/// This service expects signal data that has already been processed by the MotionCompensator.
class HeartRateService {
    
    // Constants
    private let minBPM = 40.0
    private let maxBPM = 180.0
    private let sampleRate = 200.0
    private let windowSize = 1000   // 5 seconds buffer size
    
    // Internal Buffer
    private var buffer: [Double] = []
    
    struct HRResult {
        let bpm: Int
        let confidence: Double // 0.0 to 1.0
        let isWorn: Bool
    }
    
    /// Processes a batch of cleaned samples (typically Green channel)
    func process(samples: [Double]) -> HRResult {
        buffer.append(contentsOf: samples)
        
        // Maintain fixed window size
        if buffer.count > windowSize {
            buffer.removeFirst(buffer.count - windowSize)
        }
        
        // Wait for buffer to fill before processing
        guard buffer.count >= windowSize else {
            return HRResult(bpm: 0, confidence: 0, isWorn: false)
        }
        
        // 1. Bandpass Filter (0.5Hz - 4Hz)
        // Focuses on the frequency band where human heart rates exist.
        let filtered = applyBandpassFilter(buffer)
        
        // 2. Peak Detection
        // Identifies the systolic peaks in the pulse wave.
        let peaks = findPeaks(in: filtered)
        
        // 3. Calculate BPM & Confidence
        let (bpm, confidence) = calculateBPM(from: peaks)
        
        // 4. Perfusion Check (Worn Status)
        // Checks the AC/DC ratio to ensure the sensor is actually on skin.
        let dc = buffer.reduce(0, +) / Double(buffer.count)
        let ac = filtered.map { abs($0) }.reduce(0, +) / Double(filtered.count)
        
        // AC/DC ratio > 0.001 usually indicates pulsatile blood flow
        let isWorn = bpm > 0 && confidence > 0.5 && (ac/dc > 0.001)
        
        return HRResult(bpm: bpm, confidence: confidence, isWorn: isWorn)
    }
    
    private func applyBandpassFilter(_ data: [Double]) -> [Double] {
        let mean = data.reduce(0, +) / Double(data.count)
        let centered = data.map { $0 - mean }
        // Simple 5-point Moving Average for smoothing
        var smoothed = centered
        for i in 2..<centered.count-2 {
            smoothed[i] = (centered[i-2] + centered[i-1] + centered[i] + centered[i+1] + centered[i+2]) / 5.0
        }
        return smoothed
    }
    
    private func findPeaks(in data: [Double]) -> [Int] {
        var peaks: [Int] = []
        let threshold = (data.max() ?? 0) * 0.4
        
        for i in 1..<data.count-1 {
            if data[i] > data[i-1] && data[i] > data[i+1] && data[i] > threshold {
                 // Ensure peaks are at least 300ms apart (max 200 BPM)
                 if let last = peaks.last, (i - last) < Int(sampleRate * 0.3) { continue }
                 peaks.append(i)
            }
        }
        return peaks
    }
    
    private func calculateBPM(from peaks: [Int]) -> (Int, Double) {
        guard peaks.count >= 4 else { return (0, 0.0) }
        
        var intervals: [Double] = []
        for i in 1..<peaks.count {
            intervals.append(Double(peaks[i] - peaks[i-1]))
        }
        
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        let bpm = 60.0 / (avgInterval / sampleRate)
        
        // Calculate regularity (confidence)
        let variance = intervals.map { pow($0 - avgInterval, 2) }.reduce(0, +) / Double(intervals.count)
        let stdDev = sqrt(variance)
        let confidence = max(0, 1.0 - (stdDev / avgInterval))
        
        return (Int(bpm), confidence)
    }
}
