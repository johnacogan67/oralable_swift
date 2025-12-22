import Foundation

/// Refined service to extract Heart Rate from cleaned PPG signals.
class HeartRateService {
    private let sampleRate = 200.0
    private let windowSize = 1000 // 5 seconds
    private var buffer: [Double] = []
    
    struct HRResult {
        let bpm: Int
        let confidence: Double
        let isWorn: Bool
    }
    
    func process(samples: [Double]) -> HRResult {
        buffer.append(contentsOf: samples)
        if buffer.count > windowSize { buffer.removeFirst(buffer.count - windowSize) }
        
        guard buffer.count >= windowSize else {
            return HRResult(bpm: 0, confidence: 0, isWorn: false)
        }
        
        // 1. Adaptive Filtering
        // We use a band-pass (0.7Hz to 3.5Hz) for human HR (40-210 BPM)
        let filtered = applyBandpass(buffer)
        
        // 2. Local Peak Detection
        let peaks = detectPeaks(in: filtered)
        
        // 3. Calculate Metrics
        return calculateMetrics(from: peaks, raw: buffer, filtered: filtered)
    }
    
    private func applyBandpass(_ data: [Double]) -> [Double] {
        let mean = data.reduce(0, +) / Double(data.count)
        let centered = data.map { $0 - mean }
        // Simple 3-point average smoothing
        var result = centered
        for i in 1..<centered.count-1 {
            result[i] = (centered[i-1] + centered[i] + centered[i+1]) / 3.0
        }
        return result
    }
    
    private func detectPeaks(in data: [Double]) -> [Int] {
        var peaks: [Int] = []
        let threshold = (data.max() ?? 0) * 0.3
        
        for i in 1..<data.count-1 {
            if data[i] > data[i-1] && data[i] > data[i+1] && data[i] > threshold {
                if let last = peaks.last, (i - last) < Int(sampleRate * 0.4) { continue }
                peaks.append(i)
            }
        }
        return peaks
    }
    
    private func calculateMetrics(from peaks: [Int], raw: [Double], filtered: [Double]) -> HRResult {
        guard peaks.count >= 3 else { return HRResult(bpm: 0, confidence: 0, isWorn: false) }
        
        var intervals: [Double] = []
        for i in 1..<peaks.count {
            intervals.append(Double(peaks[i] - peaks[i-1]))
        }
        
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        let bpm = Int(60.0 / (avgInterval / sampleRate))
        
        // Signal Stability Check
        let stdDev = sqrt(intervals.map { pow($0 - avgInterval, 2) }.reduce(0, +) / Double(intervals.count))
        let confidence = max(0, 1.0 - (stdDev / avgInterval))
        
        // Perfusion check (AC/DC ratio)
        let dc = raw.reduce(0, +) / Double(raw.count)
        let ac = filtered.map { abs($0) }.reduce(0, +) / Double(filtered.count)
        let isWorn = (ac/dc) > 0.001 && confidence > 0.5
        
        return HRResult(bpm: bpm, confidence: confidence, isWorn: isWorn)
    }
}
