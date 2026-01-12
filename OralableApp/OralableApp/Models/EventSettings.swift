//
//  EventSettings.swift
//  OralableApp
//
//  Created: January 8, 2026
//  Updated: January 12, 2026 - Added recording mode setting
//  User settings for event detection threshold and recording mode
//

import Foundation

/// Recording mode determines how data is stored during recording
public enum RecordingMode: String, CaseIterable {
    case continuous = "Continuous"  // Store all samples (legacy, high memory)
    case eventBased = "Event-Based" // Store only events (new, low memory)

    public var description: String {
        switch self {
        case .continuous:
            return "Store all sensor samples (high memory)"
        case .eventBased:
            return "Store only events (low memory, recommended)"
        }
    }
}

/// User settings for event detection
class EventSettings: ObservableObject {

    static let shared = EventSettings()

    // MARK: - Keys

    private enum Keys {
        static let threshold = "eventThreshold"
        static let recordingMode = "recordingMode"
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

    /// Recording mode: event-based (default, low memory) or continuous (legacy, high memory)
    @Published var recordingMode: RecordingMode {
        didSet {
            UserDefaults.standard.set(recordingMode.rawValue, forKey: Keys.recordingMode)
        }
    }

    // MARK: - Init

    private init() {
        let savedThreshold = UserDefaults.standard.integer(forKey: Keys.threshold)
        self.threshold = savedThreshold > 0 ? savedThreshold : EventSettings.defaultThreshold

        if let modeString = UserDefaults.standard.string(forKey: Keys.recordingMode),
           let mode = RecordingMode(rawValue: modeString) {
            self.recordingMode = mode
        } else {
            self.recordingMode = .eventBased // Default to event-based for memory efficiency
        }
    }

    // MARK: - Reset

    /// Reset threshold to default value
    func resetToDefault() {
        threshold = EventSettings.defaultThreshold
        recordingMode = .eventBased
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
