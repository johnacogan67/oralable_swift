//
//  PPGProcessor.swift
//  OralableApp
//
//  Created: January 29, 2026
//  Purpose: PPG signal processing for heart rate extraction
//  Reference: cursor_oralable/src/analysis/features.py
//

import Foundation

/// Processes PPG signals to extract heart rate and pulse features
public class PPGProcessor {

    // MARK: - Configuration

    /// Sample rate in Hz
    public let sampleRate: Double

    /// Bandpass filter for heart rate extraction
    private let bandpassFilter: ButterworthFilter

    // MARK: - Buffers

    /// Signal buffer for processing
    private var signalBuffer: [Double] = []

    /// Maximum buffer size (samples)
    private let maxBufferSize: Int

    /// Detected peak times
    private var peakTimes: [Date] = []

    // MARK: - Initialization

    public init(sampleRate: Double = AlgorithmSpec.ppgSampleRate) {
        self.sampleRate = sampleRate
        self.maxBufferSize = Int(sampleRate * 10)  // 10 seconds

        // Bandpass 0.5-8 Hz for heart rate
        self.bandpassFilter = ButterworthFilter(
            type: .bandpass,
            cutoffLow: AlgorithmSpec.hrBandpassLow,
            cutoffHigh: AlgorithmSpec.hrBandpassHigh,
            sampleRate: sampleRate,
            order: AlgorithmSpec.filterOrder
        )
    }

    // MARK: - Processing

    /// Process a single PPG sample
    /// - Parameter sample: PPGData sample
    /// - Returns: Current heart rate estimate, or nil if insufficient data
    public func process(_ sample: PPGData) -> Int? {
        // Use Green channel for beat detection (per Python reference)
        let value = Double(sample.green)
        return processSample(value, timestamp: sample.timestamp)
    }

    /// Process a raw sample value
    /// - Parameters:
    ///   - value: Raw signal value (typically Green channel)
    ///   - timestamp: Sample timestamp
    /// - Returns: Current heart rate estimate, or nil if insufficient data
    public func processSample(_ value: Double, timestamp: Date) -> Int? {
        // Add to buffer
        signalBuffer.append(value)

        // Trim buffer
        if signalBuffer.count > maxBufferSize {
            signalBuffer.removeFirst(signalBuffer.count - maxBufferSize)
        }

        // Need at least 3 seconds of data
        let minSamples = Int(sampleRate * 3)
        guard signalBuffer.count >= minSamples else { return nil }

        // Calculate heart rate from buffer
        return calculateHeartRate()
    }

    /// Process batch of PPG samples
    /// - Parameter samples: Array of PPGData
    /// - Returns: Heart rate estimate, or nil if insufficient data
    public func processBatch(_ samples: [PPGData]) -> Int? {
        for sample in samples {
            signalBuffer.append(Double(sample.green))
        }

        // Trim buffer
        if signalBuffer.count > maxBufferSize {
            signalBuffer.removeFirst(signalBuffer.count - maxBufferSize)
        }

        return calculateHeartRate()
    }

    // MARK: - Heart Rate Calculation

    private func calculateHeartRate() -> Int? {
        guard signalBuffer.count >= Int(sampleRate * 3) else { return nil }

        // Apply bandpass filter
        let filtered = bandpassFilter.filtfilt(signalBuffer)

        // Calculate statistics
        let mean = filtered.reduce(0, +) / Double(filtered.count)
        let sumSquaredDiff = filtered.map { pow($0 - mean, 2) }.reduce(0, +)
        let stdDev = sqrt(sumSquaredDiff / Double(filtered.count))

        // Signal too flat
        guard stdDev > 1.0 else { return nil }

        // Find peaks with minimum distance
        let minDistanceSamples = Int(AlgorithmSpec.minPeakDistanceSeconds * sampleRate)
        let prominence = stdDev * AlgorithmSpec.peakProminenceMultiplier

        let peaks = findPeaks(
            signal: filtered,
            minDistance: minDistanceSamples,
            minProminence: prominence
        )

        guard peaks.count >= 2 else { return nil }

        // Calculate inter-beat intervals
        var intervals: [Double] = []
        for i in 1..<peaks.count {
            let intervalSamples = Double(peaks[i] - peaks[i - 1])
            let intervalSeconds = intervalSamples / sampleRate

            // Filter by physiological bounds
            let minInterval = 60.0 / AlgorithmSpec.maxHeartRate
            let maxInterval = 60.0 / AlgorithmSpec.minHeartRate

            if intervalSeconds >= minInterval && intervalSeconds <= maxInterval {
                intervals.append(intervalSeconds)
            }
        }

        guard !intervals.isEmpty else { return nil }

        // Use median interval (robust to outliers)
        let sortedIntervals = intervals.sorted()
        let medianInterval = sortedIntervals[sortedIntervals.count / 2]

        let bpm = Int(60.0 / medianInterval)

        // Validate
        guard bpm >= Int(AlgorithmSpec.minHeartRate) && bpm <= Int(AlgorithmSpec.maxHeartRate) else {
            return nil
        }

        return bpm
    }

    // MARK: - Peak Detection

    private func findPeaks(signal: [Double], minDistance: Int, minProminence: Double) -> [Int] {
        var peaks: [Int] = []

        for i in 2..<(signal.count - 2) {
            let current = signal[i]

            // Local maximum check
            guard current > signal[i - 1] && current > signal[i + 1] else { continue }
            guard current > signal[i - 2] && current > signal[i + 2] else { continue }

            // Prominence check
            let leftMin = signal[max(0, i - minDistance)..<i].min() ?? current
            let rightMin = signal[(i + 1)..<min(signal.count, i + minDistance + 1)].min() ?? current
            let prominence = current - max(leftMin, rightMin)
            guard prominence >= minProminence else { continue }

            // Distance check
            if let lastPeak = peaks.last {
                guard i - lastPeak >= minDistance else { continue }
            }

            peaks.append(i)
        }

        return peaks
    }

    // MARK: - Reset

    /// Reset processor state
    public func reset() {
        signalBuffer.removeAll()
        peakTimes.removeAll()
        bandpassFilter.reset()
    }
}
