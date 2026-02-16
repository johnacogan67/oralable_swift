//
//  BeatFeature.swift
//  OralableApp
//
//  Created: January 29, 2026
//  Purpose: Pulse beat morphology features
//  Reference: cursor_oralable/src/analysis/features.py
//

import Foundation

/// Features extracted from a single pulse beat
public struct BeatFeature: Codable, Sendable, Identifiable {

    public let id: UUID

    // MARK: - Sample Indices

    /// Index of pulse onset (foot of upstroke)
    public let onsetIndex: Int

    /// Index of systolic peak
    public let peakIndex: Int

    /// Index of pulse offset (foot after peak)
    public let offsetIndex: Int

    // MARK: - Timestamps

    /// Timestamp of onset
    public let onsetTime: Date

    /// Timestamp of peak
    public let peakTime: Date

    /// Timestamp of offset
    public let offsetTime: Date

    // MARK: - Morphology Metrics

    /// Rise time: onset → peak (seconds)
    /// In pulse physiology: time for blood to rush in
    public let riseTimeSeconds: Double

    /// Fall time: peak → offset (seconds)
    /// In pulse physiology: time for blood to drain
    public let fallTimeSeconds: Double

    /// Rise time in milliseconds
    public var riseTimeMs: Double {
        riseTimeSeconds * 1000.0
    }

    /// Fall time in milliseconds
    public var fallTimeMs: Double {
        fallTimeSeconds * 1000.0
    }

    /// Pulse symmetry ratio: rise time / fall time
    /// Healthy resting pulse: typically 0.3 - 0.5
    /// Ratio > 1.0: abnormal (rise slower than fall)
    public var symmetryRatio: Double {
        guard fallTimeSeconds > 0 else { return 0 }
        return riseTimeSeconds / fallTimeSeconds
    }

    /// Total pulse duration in seconds
    public var durationSeconds: Double {
        riseTimeSeconds + fallTimeSeconds
    }

    /// Instantaneous heart rate from this beat (BPM)
    public var instantaneousBPM: Double {
        guard durationSeconds > 0 else { return 0 }
        return 60.0 / durationSeconds
    }

    // MARK: - Amplitude Metrics

    /// Peak amplitude (raw IR value at peak)
    public let peakAmplitude: Double

    /// Onset amplitude (raw IR value at onset)
    public let onsetAmplitude: Double

    /// Pulse amplitude (peak - onset)
    public var pulseAmplitude: Double {
        peakAmplitude - onsetAmplitude
    }

    // MARK: - Context

    /// IR DC baseline at this beat (from rolling 5s mean)
    public let irDCMean5s: Double?

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        onsetIndex: Int,
        peakIndex: Int,
        offsetIndex: Int,
        onsetTime: Date,
        peakTime: Date,
        offsetTime: Date,
        riseTimeSeconds: Double,
        fallTimeSeconds: Double,
        peakAmplitude: Double,
        onsetAmplitude: Double,
        irDCMean5s: Double? = nil
    ) {
        self.id = id
        self.onsetIndex = onsetIndex
        self.peakIndex = peakIndex
        self.offsetIndex = offsetIndex
        self.onsetTime = onsetTime
        self.peakTime = peakTime
        self.offsetTime = offsetTime
        self.riseTimeSeconds = riseTimeSeconds
        self.fallTimeSeconds = fallTimeSeconds
        self.peakAmplitude = peakAmplitude
        self.onsetAmplitude = onsetAmplitude
        self.irDCMean5s = irDCMean5s
    }
}

// MARK: - Validation

extension BeatFeature {

    /// Whether this beat has physiologically valid timing
    /// Normal resting: rise 80-150ms, fall 200-400ms
    public var hasValidTiming: Bool {
        let riseMs = riseTimeMs
        let fallMs = fallTimeMs

        // Rise time: 50-200ms (allowing some margin)
        guard riseMs >= 50 && riseMs <= 200 else { return false }

        // Fall time: 150-500ms (allowing some margin)
        guard fallMs >= 150 && fallMs <= 500 else { return false }

        // Symmetry ratio: 0.1 - 1.0 (rise should be faster than fall)
        guard symmetryRatio >= 0.1 && symmetryRatio <= 1.0 else { return false }

        return true
    }

    /// Quality score based on morphology (0.0 - 1.0)
    public var morphologyQuality: Double {
        var score = 0.0

        // Rise time quality (optimal: 100-120ms)
        let riseMs = riseTimeMs
        if riseMs >= 80 && riseMs <= 150 {
            score += 0.3
        } else if riseMs >= 50 && riseMs <= 200 {
            score += 0.15
        }

        // Fall time quality (optimal: 250-350ms)
        let fallMs = fallTimeMs
        if fallMs >= 200 && fallMs <= 400 {
            score += 0.3
        } else if fallMs >= 150 && fallMs <= 500 {
            score += 0.15
        }

        // Symmetry quality (optimal: 0.3-0.5)
        let sym = symmetryRatio
        if sym >= 0.3 && sym <= 0.5 {
            score += 0.4
        } else if sym >= 0.2 && sym <= 0.7 {
            score += 0.2
        }

        return min(1.0, score)
    }
}
