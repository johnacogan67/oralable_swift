//
//  EventSettings.swift
//  OralableApp
//
//  Created: January 8, 2026
//  Updated: January 13, 2026 - Added detection mode and normalized threshold
//
//  Settings for event detection and recording.
//

import Foundation
import OralableCore

/// User settings for event detection
class EventSettings: ObservableObject {

    static let shared = EventSettings()

    // MARK: - Keys

    private enum Keys {
        static let detectionMode = "eventDetectionMode"
        static let absoluteThreshold = "eventAbsoluteThreshold"
        static let normalizedThreshold = "eventNormalizedThreshold"
        static let calibrationDuration = "eventCalibrationDuration"
        static let recordingMode = "recordingMode"
    }

    // MARK: - Defaults

    public static let defaultAbsoluteThreshold: Int = 150000
    public static let defaultNormalizedThreshold: Double = 40.0
    public static let defaultCalibrationDuration: TimeInterval = 15.0

    /// Minimum allowed absolute threshold value
    public static let minAbsoluteThreshold: Int = 50000

    /// Maximum allowed absolute threshold value
    public static let maxAbsoluteThreshold: Int = 500000

    /// Step size for threshold slider
    public static let thresholdStep: Int = 10000

    /// Minimum normalized threshold percentage
    public static let minNormalizedThreshold: Double = 10.0

    /// Maximum normalized threshold percentage
    public static let maxNormalizedThreshold: Double = 100.0

    // MARK: - Published Properties

    /// Detection mode: absolute (fixed threshold) or normalized (percentage above baseline)
    @Published var detectionMode: DetectionMode {
        didSet {
            UserDefaults.standard.set(detectionMode.rawValue, forKey: Keys.detectionMode)
        }
    }

    /// Absolute threshold value (for absolute mode)
    @Published var absoluteThreshold: Int {
        didSet {
            let clamped = min(max(absoluteThreshold, Self.minAbsoluteThreshold), Self.maxAbsoluteThreshold)
            if clamped != absoluteThreshold {
                absoluteThreshold = clamped
            }
            UserDefaults.standard.set(absoluteThreshold, forKey: Keys.absoluteThreshold)
        }
    }

    /// Normalized threshold as percentage above baseline (for normalized mode)
    @Published var normalizedThresholdPercent: Double {
        didSet {
            let clamped = min(max(normalizedThresholdPercent, Self.minNormalizedThreshold), Self.maxNormalizedThreshold)
            if clamped != normalizedThresholdPercent {
                normalizedThresholdPercent = clamped
            }
            UserDefaults.standard.set(normalizedThresholdPercent, forKey: Keys.normalizedThreshold)
        }
    }

    /// Calibration duration in seconds
    @Published var calibrationDuration: TimeInterval {
        didSet {
            UserDefaults.standard.set(calibrationDuration, forKey: Keys.calibrationDuration)
        }
    }

    // MARK: - Init

    private init() {
        // Load detection mode
        if let modeString = UserDefaults.standard.string(forKey: Keys.detectionMode),
           let mode = DetectionMode(rawValue: modeString) {
            self.detectionMode = mode
        } else {
            self.detectionMode = .normalized  // Default to normalized (recommended)
        }

        // Load absolute threshold
        let savedAbsoluteThreshold = UserDefaults.standard.integer(forKey: Keys.absoluteThreshold)
        self.absoluteThreshold = savedAbsoluteThreshold > 0 ? savedAbsoluteThreshold : Self.defaultAbsoluteThreshold

        // Load normalized threshold
        let savedNormalizedThreshold = UserDefaults.standard.double(forKey: Keys.normalizedThreshold)
        self.normalizedThresholdPercent = savedNormalizedThreshold > 0 ? savedNormalizedThreshold : Self.defaultNormalizedThreshold

        // Load calibration duration
        let savedCalibrationDuration = UserDefaults.standard.double(forKey: Keys.calibrationDuration)
        self.calibrationDuration = savedCalibrationDuration > 0 ? savedCalibrationDuration : Self.defaultCalibrationDuration
    }

    // MARK: - Reset

    /// Reset all settings to defaults
    func resetToDefaults() {
        detectionMode = .normalized
        absoluteThreshold = Self.defaultAbsoluteThreshold
        normalizedThresholdPercent = Self.defaultNormalizedThreshold
        calibrationDuration = Self.defaultCalibrationDuration
    }

    // MARK: - Display Helpers

    /// Absolute threshold formatted for display (e.g., "150k")
    var formattedAbsoluteThreshold: String {
        if absoluteThreshold >= 1000 {
            return "\(absoluteThreshold / 1000)k"
        }
        return "\(absoluteThreshold)"
    }

    /// Normalized threshold formatted for display (e.g., "40%")
    var formattedNormalizedThreshold: String {
        return "\(Int(normalizedThresholdPercent))%"
    }

    /// Current threshold description based on mode
    var currentThresholdDescription: String {
        switch detectionMode {
        case .absolute:
            return "Fixed: \(formattedAbsoluteThreshold)"
        case .normalized:
            return "Normalized: \(formattedNormalizedThreshold) above baseline"
        }
    }

    /// Minimum absolute threshold formatted for display
    static var formattedMinAbsoluteThreshold: String {
        "\(minAbsoluteThreshold / 1000)k"
    }

    /// Maximum absolute threshold formatted for display
    static var formattedMaxAbsoluteThreshold: String {
        "\(maxAbsoluteThreshold / 1000)k"
    }
}
