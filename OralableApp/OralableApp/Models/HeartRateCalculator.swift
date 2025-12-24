import Foundation

/// Result of heart rate calculation
struct HeartRateResult {
    let bpm: Double
    let quality: Double
    /// Human-readable quality level
    var qualityLevel: String {
        switch quality {
        case 0.9...1.0: return "Excellent"
        case 0.8..<0.9: return "Good"
        case 0.7..<0.8: return "Fair"
        case 0.6..<0.7: return "Acceptable"
        default: return "Poor"
        }
    }
}

/// A robust heart rate calculator designed for reflective PPG on muscle sites.
/// Uses a combination of bandpass filtering, derivative analysis, and adaptive thresholding.
class HeartRateCalculator {
    private var irValues: [Double] = []
    private let windowSize: Int
    private let sampleRate: Double

    // Filter State
    private var lowPassValue: Double = 0
    private var highPassValue: Double = 0
    private let alphaLP: Double = 0.15 // Smoothing
    private let alphaHP: Double = 0.05 // Baseline tracking

    // Peak Detection State
    private var lastPeakTime = Date()
    private var minPeakInterval: TimeInterval = 0.4 // Max HR ~150bpm

    // MARK: - Initialization

    /// Initialize with configurable sample rate
    /// - Parameter sampleRate: PPG sample rate in Hz. Default 50.0 for Oralable device.
    init(sampleRate: Double = 50.0) {
        self.sampleRate = sampleRate
        self.windowSize = Int(sampleRate * 3.0)  // ~3 seconds of data
    }

    func process(irValue: Double) -> Int? {
        // 1. DC Offset Removal & Bandpass Filter
        // We use a simple Recursive High-Pass to remove baseline and Low-Pass to remove noise
        highPassValue = alphaHP * (highPassValue + irValue - (irValues.last ?? irValue))
        lowPassValue = lowPassValue + alphaLP * (highPassValue - lowPassValue)
        
        irValues.append(lowPassValue)
        if irValues.count > windowSize {
            irValues.removeFirst()
        }
        
        guard irValues.count >= windowSize else { return nil }
        
        return calculateHeartRate()
    }
    
    /// Batch API: feed a set of raw IR samples and compute BPM and a basic quality score
    /// - Parameter irSamples: Raw IR samples (UInt32) from the sensor
    /// - Returns: HeartRateResult with bpm (Double) and quality (0...1), or nil if not enough/poor signal
    func calculateHeartRate(irSamples: [UInt32]) -> HeartRateResult? {
        guard !irSamples.isEmpty else { return nil }
        
        // Reset state for batch processing
        irValues.removeAll(keepingCapacity: true)
        lowPassValue = 0
        highPassValue = 0
        
        // Feed samples through the same filter path as real-time processing
        for s in irSamples {
            let v = Double(s)
            highPassValue = alphaHP * (highPassValue + v - (irValues.last ?? v))
            lowPassValue = lowPassValue + alphaLP * (highPassValue - lowPassValue)
            irValues.append(lowPassValue)
        }
        
        // Require minimum window
        guard irValues.count >= windowSize else { return nil }
        
        // Compute BPM using existing peak logic (adapted)
        let signal = irValues
        let mean = signal.reduce(0, +) / Double(signal.count)
        let sumSquaredDiff = signal.map { pow($0 - mean, 2) }.reduce(0, +)
        let stdDev = sqrt(sumSquaredDiff / Double(signal.count))
        
        // If the signal is too flat, quality is poor
        if stdDev < 1.0 { return nil }
        
        let threshold = mean + (stdDev * 0.6)
        var peaks: [Int] = []
        for i in 2..<(signal.count - 2) {
            let current = signal[i]
            if current > signal[i-1] && current > signal[i+1] && current > threshold {
                peaks.append(i)
            }
        }
        guard peaks.count >= 2 else { return nil }
        
        var intervals: [Double] = []
        for j in 1..<peaks.count {
            let intervalSamples = Double(peaks[j] - peaks[j-1])
            let intervalSeconds = intervalSamples / sampleRate
            if intervalSeconds > 0.33 && intervalSeconds < 1.5 {
                intervals.append(intervalSeconds)
            }
        }
        guard !intervals.isEmpty else { return nil }
        
        let sortedIntervals = intervals.sorted()
        let medianInterval = sortedIntervals[sortedIntervals.count / 2]
        let bpmInt = Int(60.0 / medianInterval)
        guard (40...180).contains(bpmInt) else { return nil }
        
        // Derive a simple quality metric from stdDev and peak consistency
        // Normalize stdDev by mean (AC/DC ratio proxy), clamp to 0...1, and blend with peak count factor
        let acdc = max(0.0, min(1.0, stdDev / max(1.0, abs(mean))))
        let peakFactor = max(0.0, min(1.0, Double(intervals.count) / 10.0)) // more intervals → higher confidence
        let quality = max(0.0, min(1.0, 0.6 * acdc + 0.4 * peakFactor))
        
        return HeartRateResult(bpm: Double(bpmInt), quality: quality)
    }
    
    private func calculateHeartRate() -> Int? {
        // 2. Identify Local Maxima in the filtered signal
        // We look for the "Systolic Peak"
        var peaks: [Int] = []
        let signal = irValues
        
        // Adaptive threshold based on the signal's standard deviation (AC amplitude)
        let mean = signal.reduce(0, +) / Double(signal.count)
        let sumSquaredDiff = signal.map { pow($0 - mean, 2) }.reduce(0, +)
        let stdDev = sqrt(sumSquaredDiff / Double(signal.count))
        
        // If the signal is too "flat" or too "chaotic", signal quality is likely poor
        if stdDev < 1.0 { return nil }
        
        let threshold = mean + (stdDev * 0.6)
        
        for i in 2..<(signal.count - 2) {
            let current = signal[i]
            // Peak condition: Greater than neighbors and above adaptive threshold
            if current > signal[i-1] && current > signal[i+1] && current > threshold {
                peaks.append(i)
            }
        }
        
        // 3. Convert Peak Intervals to BPM
        guard peaks.count >= 2 else { return nil }
        
        var intervals: [Double] = []
        for j in 1..<peaks.count {
            let intervalSamples = Double(peaks[j] - peaks[j-1])
            let intervalSeconds = intervalSamples / sampleRate
            
            // Physiological Filter: 40bpm to 180bpm
            if intervalSeconds > 0.33 && intervalSeconds < 1.5 {
                intervals.append(intervalSeconds)
            }
        }
        
        guard !intervals.isEmpty else { return nil }
        
        // Use Median to filter out outliers from movement
        let sortedIntervals = intervals.sorted()
        let medianInterval = sortedIntervals[sortedIntervals.count / 2]
        
        let bpm = Int(60.0 / medianInterval)
        return (40...180).contains(bpm) ? bpm : nil
    }
    
    func reset() {
        irValues.removeAll()
        lowPassValue = 0
        highPassValue = 0
    }
}
