//
//  EventSettings.swift
//  OralableApp
//
//  Created: January 8, 2026
//  User settings for event detection threshold
//

import Foundation

/// User settings for event detection
class EventSettings: ObservableObject {

    static let shared = EventSettings()

    // MARK: - Keys

    private enum Keys {
        static let threshold = "eventThreshold"
    }

    // MARK: - Threshold Configuration

    /// Default threshold value for PPG IR event detection
    public static let defaultThreshold: Int = 150000

    /// Minimum allowed threshold value
    public static let minThreshold: Int = 50000

    /// Maximum allowed threshold value
    public static let maxThreshold: Int = 500000

    /// Step size for threshold slider
    public static let thresholdStep: Int = 10000

    // MARK: - Published Properties

    /// Current threshold value for event detection
    /// Events are detected when PPG IR exceeds this value
    @Published var threshold: Int {
        didSet {
            // Clamp to valid range
            let clamped = min(max(threshold, EventSettings.minThreshold), EventSettings.maxThreshold)
            if clamped != threshold {
                threshold = clamped
            }
            UserDefaults.standard.set(threshold, forKey: Keys.threshold)
        }
    }

    // MARK: - Init

    private init() {
        let saved = UserDefaults.standard.integer(forKey: Keys.threshold)
        self.threshold = saved > 0 ? saved : EventSettings.defaultThreshold
    }

    // MARK: - Reset

    /// Reset threshold to default value
    func resetToDefault() {
        threshold = EventSettings.defaultThreshold
    }

    // MARK: - Display Helpers

    /// Threshold formatted for display (e.g., "150k")
    var formattedThreshold: String {
        if threshold >= 1000 {
            return "\(threshold / 1000)k"
        }
        return "\(threshold)"
    }

    /// Minimum threshold formatted for display
    static var formattedMinThreshold: String {
        "\(minThreshold / 1000)k"
    }

    /// Maximum threshold formatted for display
    static var formattedMaxThreshold: String {
        "\(maxThreshold / 1000)k"
    }
}
