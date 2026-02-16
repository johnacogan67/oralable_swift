//
//  PulseMorphologyAnalyzer.swift
//  OralableApp
//
//  Created: January 29, 2026
//  Purpose: Extract pulse morphology features from PPG signal
//  Reference: cursor_oralable/src/analysis/features.py detect_beats_from_green_bp()
//

import Foundation
import Accelerate

/// Analyzes pulse morphology from PPG signal
public class PulseMorphologyAnalyzer {

    // MARK: - Configuration

    /// Sample rate in Hz
    public let sampleRate: Double

    /// Minimum peak distance in seconds (max heart rate limit)
    /// 0.4s = 150 BPM max
    public var minPeakDistanceSeconds: Double = 0.4

    /// Prominence threshold multiplier (relative to signal std dev)
    public var prominenceMultiplier: Double = 0.5

    /// Bandpass filter low cutoff (Hz)
    public var bandpassLowHz: Double = 0.5

    /// Bandpass filter high cutoff (Hz)
    public var bandpassHighHz: Double = 8.0

    // MARK: - Filter State

    private var bandpassFilter: ButterworthFilter?

    // MARK: - Initialization

    public init(sampleRate: Double = 50.0) {
        self.sampleRate = sampleRate
        self.bandpassFilter = ButterworthFilter(
            type: .bandpass,
            cutoffLow: bandpassLowHz,
            cutoffHigh: bandpassHighHz,
            sampleRate: sampleRate,
            order: 4
        )
    }

    // MARK: - Beat Detection

    /// Detect beats and extract morphology features from PPG signal
    /// - Parameters:
    ///   - signal: Raw PPG signal (Green channel recommended)
    ///   - timestamps: Optional timestamps for each sample
    ///   - irDCValues: Optional IR DC baseline values for each sample
    /// - Returns: Array of detected beats with morphology features
    public func detectBeats(
        signal: [Double],
        timestamps: [Date]? = nil,
        irDCValues: [Double]? = nil
    ) -> [BeatFeature] {

        guard signal.count >= 3 else { return [] }

        // Apply bandpass filter
        let filtered = applyBandpassFilter(signal)

        // Find peaks with minimum distance and prominence
        let minDistanceSamples = Int(minPeakDistanceSeconds * sampleRate)
        let stdDev = standardDeviation(filtered)
        let prominence = stdDev * prominenceMultiplier

        let peakIndices = findPeaks(
            signal: filtered,
            minDistance: minDistanceSamples,
            minProminence: prominence > 0 ? prominence : nil
        )

        guard peakIndices.count >= 2 else { return [] }

        // Extract beats with onset/offset
        var beats: [BeatFeature] = []

        for i in 0..<peakIndices.count {
            let peakIdx = peakIndices[i]

            // Search window for onset: previous peak to current peak
            let searchStart: Int
            if i == 0 {
                searchStart = max(0, peakIdx - Int(0.8 * sampleRate))
            } else {
                searchStart = peakIndices[i - 1]
            }

            guard searchStart < peakIdx else { continue }

            // Find onset (minimum before peak)
            let onsetSegment = Array(filtered[searchStart..<peakIdx])
            guard !onsetSegment.isEmpty else { continue }
            let onsetRelative = onsetSegment.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let onsetIdx = searchStart + onsetRelative

            // Search window for offset: current peak to next peak
            let searchEnd: Int
            if i == peakIndices.count - 1 {
                searchEnd = min(signal.count - 1, peakIdx + Int(0.8 * sampleRate))
            } else {
                searchEnd = peakIndices[i + 1]
            }

            guard peakIdx < searchEnd else { continue }

            // Find offset (minimum after peak)
            let offsetSegment = Array(filtered[peakIdx...searchEnd])
            guard !offsetSegment.isEmpty else { continue }
            let offsetRelative = offsetSegment.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let offsetIdx = peakIdx + offsetRelative

            // Validate indices
            guard onsetIdx < peakIdx && peakIdx < offsetIdx else { continue }
            guard offsetIdx < signal.count else { continue }

            // Calculate timing
            let riseTimeSeconds = Double(peakIdx - onsetIdx) / sampleRate
            let fallTimeSeconds = Double(offsetIdx - peakIdx) / sampleRate

            // Get timestamps
            let onsetTime: Date
            let peakTime: Date
            let offsetTime: Date

            if let ts = timestamps, ts.count > offsetIdx {
                onsetTime = ts[onsetIdx]
                peakTime = ts[peakIdx]
                offsetTime = ts[offsetIdx]
            } else {
                let now = Date()
                let totalSamples = signal.count
                let sampleDuration = 1.0 / sampleRate
                onsetTime = now.addingTimeInterval(-Double(totalSamples - onsetIdx) * sampleDuration)
                peakTime = now.addingTimeInterval(-Double(totalSamples - peakIdx) * sampleDuration)
                offsetTime = now.addingTimeInterval(-Double(totalSamples - offsetIdx) * sampleDuration)
            }

            // Get amplitudes from original signal
            let peakAmplitude = signal[peakIdx]
            let onsetAmplitude = signal[onsetIdx]

            // Get IR DC if available
            let irDC: Double? = irDCValues?[peakIdx]

            let beat = BeatFeature(
                onsetIndex: onsetIdx,
                peakIndex: peakIdx,
                offsetIndex: offsetIdx,
                onsetTime: onsetTime,
                peakTime: peakTime,
                offsetTime: offsetTime,
                riseTimeSeconds: riseTimeSeconds,
                fallTimeSeconds: fallTimeSeconds,
                peakAmplitude: peakAmplitude,
                onsetAmplitude: onsetAmplitude,
                irDCMean5s: irDC
            )

            beats.append(beat)
        }

        return beats
    }

    // MARK: - Private Methods

    private func applyBandpassFilter(_ signal: [Double]) -> [Double] {
        guard let filter = bandpassFilter else {
            return signal
        }

        // Detrend (remove mean)
        let mean = signal.reduce(0, +) / Double(signal.count)
        let detrended = signal.map { $0 - mean }

        // Apply forward-backward filtering (like scipy filtfilt)
        return filter.filtfilt(detrended)
    }

    private func findPeaks(
        signal: [Double],
        minDistance: Int,
        minProminence: Double?
    ) -> [Int] {

        var peaks: [Int] = []

        for i in 2..<(signal.count - 2) {
            let current = signal[i]

            // Local maximum check
            guard current > signal[i - 1] && current > signal[i + 1] else { continue }
            guard current > signal[i - 2] && current > signal[i + 2] else { continue }

            // Prominence check
            if let prom = minProminence {
                let leftMin = signal[max(0, i - minDistance)..<i].min() ?? current
                let rightMin = signal[(i + 1)..<min(signal.count, i + minDistance + 1)].min() ?? current
                let prominence = current - max(leftMin, rightMin)
                guard prominence >= prom else { continue }
            }

            // Distance check
            if let lastPeak = peaks.last {
                guard i - lastPeak >= minDistance else { continue }
            }

            peaks.append(i)
        }

        return peaks
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sumSquaredDiff = values.map { pow($0 - mean, 2) }.reduce(0, +)
        return sqrt(sumSquaredDiff / Double(values.count - 1))
    }
}
