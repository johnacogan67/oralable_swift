//
//  EventSettings.swift
//  OralableApp
//
//  Created: January 8, 2026
//  Updated: January 15, 2026 - Simplified to normalized-only detection
//
//  Settings for event detection (normalized mode only).
//

import Foundation
import OralableCore

/// User settings for event detection
class EventSettings: ObservableObject {

    static let shared = EventSettings()

    // MARK: - Keys

    private enum Keys {
        static let normalizedThreshold = "eventNormalizedThreshold"
        static let calibrationDuration = "eventCalibrationDuration"
    }

    // MARK: - Defaults

    public static let defaultNormalizedThreshold: Double = 40.0
    public static let defaultCalibrationDuration: TimeInterval = 15.0

    /// Minimum normalized threshold percentage
    public static let minNormalizedThreshold: Double = 10.0

    /// Maximum normalized threshold percentage
    public static let maxNormalizedThreshold: Double = 100.0

    // MARK: - Published Properties

    /// Normalized threshold as percentage above baseline
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
        normalizedThresholdPercent = Self.defaultNormalizedThreshold
        calibrationDuration = Self.defaultCalibrationDuration
    }

    // MARK: - Display Helpers

    /// Normalized threshold formatted for display (e.g., "40%")
    var formattedNormalizedThreshold: String {
        return "\(Int(normalizedThresholdPercent))%"
    }

    /// Current threshold description
    var currentThresholdDescription: String {
        return "Normalized: \(formattedNormalizedThreshold) above baseline"
    }
}
