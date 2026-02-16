//
//  PulseAnalysisResult.swift
//  OralableApp
//
//  Created: January 29, 2026
//  Purpose: Combined pulse analysis result
//

import Foundation

/// Comprehensive pulse analysis result combining all metrics
public struct PulseAnalysisResult: Sendable {

    // MARK: - Timing

    public let timestamp: Date
    public let windowSeconds: Double

    // MARK: - Pulse Morphology

    /// Number of beats detected
    public let beatCount: Int

    /// Average rise time in ms
    public let avgRiseTimeMs: Double?

    /// Average fall time in ms
    public let avgFallTimeMs: Double?

    /// Average symmetry ratio
    public let avgSymmetryRatio: Double?

    /// Morphology quality score (0-1)
    public let morphologyQuality: Double

    // MARK: - Heart Rate

    /// Heart rate in BPM
    public let heartRateBPM: Int?

    /// HR confidence score (0-1)
    public let hrConfidence: Double

    // MARK: - IR DC Baseline

    /// Current IR DC value
    public let irDC: Double?

    /// 5-second rolling mean
    public let irDCMean5s: Double?

    /// IR DC shift (positive = occlusion)
    public let irDCShift5s: Double?

    // MARK: - HRV Metrics

    /// SDNN in ms
    public let sdnnMs: Double?

    /// RMSSD in ms
    public let rmssdMs: Double?

    /// SVD s1 (leading singular value)
    public let svdS1: Double?

    /// SVD s1/s2 ratio (bruxism biomarker)
    public let svdS1S2Ratio: Double?

    // MARK: - Quality Assessment

    /// Overall signal quality (0-1)
    public var overallQuality: Double {
        var score = 0.0
        var factors = 0

        if morphologyQuality > 0 {
            score += morphologyQuality
            factors += 1
        }

        if hrConfidence > 0 {
            score += hrConfidence
            factors += 1
        }

        return factors > 0 ? score / Double(factors) : 0
    }

    /// Whether pulse data is valid for positioning
    public var isValidForPositioning: Bool {
        // Require either valid HR or valid morphology
        (heartRateBPM ?? 0) > 0 || morphologyQuality > 0.5
    }

    // MARK: - Bruxism Indicators

    /// Whether metrics suggest potential bruxism (vs simple arousal)
    /// Based on SVD ratio - higher values suggest bruxism
    public var suggestsBruxism: Bool? {
        guard let ratio = svdS1S2Ratio else { return nil }
        // Threshold TBD from clinical validation
        return ratio > 5.0
    }

    /// IR DC shift indicates muscle activity
    public var hasSignificantIRShift: Bool {
        guard let shift = irDCShift5s else { return false }
        return shift > 1000  // ADC units threshold
    }

    // MARK: - Initialization

    public init(
        timestamp: Date = Date(),
        windowSeconds: Double,
        beatCount: Int,
        avgRiseTimeMs: Double? = nil,
        avgFallTimeMs: Double? = nil,
        avgSymmetryRatio: Double? = nil,
        morphologyQuality: Double = 0,
        heartRateBPM: Int? = nil,
        hrConfidence: Double = 0,
        irDC: Double? = nil,
        irDCMean5s: Double? = nil,
        irDCShift5s: Double? = nil,
        sdnnMs: Double? = nil,
        rmssdMs: Double? = nil,
        svdS1: Double? = nil,
        svdS1S2Ratio: Double? = nil
    ) {
        self.timestamp = timestamp
        self.windowSeconds = windowSeconds
        self.beatCount = beatCount
        self.avgRiseTimeMs = avgRiseTimeMs
        self.avgFallTimeMs = avgFallTimeMs
        self.avgSymmetryRatio = avgSymmetryRatio
        self.morphologyQuality = morphologyQuality
        self.heartRateBPM = heartRateBPM
        self.hrConfidence = hrConfidence
        self.irDC = irDC
        self.irDCMean5s = irDCMean5s
        self.irDCShift5s = irDCShift5s
        self.sdnnMs = sdnnMs
        self.rmssdMs = rmssdMs
        self.svdS1 = svdS1
        self.svdS1S2Ratio = svdS1S2Ratio
    }
}
