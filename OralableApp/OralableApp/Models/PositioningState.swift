//
//  PositioningState.swift
//  OralableApp
//
//  Device positioning and activity state for simplified dashboard.
//  Color-coded: Black (not positioned), Green (rest), Red (activity)
//

import SwiftUI

/// Device positioning and muscle activity state
public enum PositioningState: Equatable {
    /// Device not correctly positioned (temp < 32°C)
    case notPositioned

    /// Correctly positioned, muscle at rest
    case rest

    /// Correctly positioned, muscle active (above threshold)
    case activity

    // MARK: - Colors (Apple-inspired)

    /// Background color for the PPG card
    public var backgroundColor: Color {
        switch self {
        case .notPositioned:
            return .black
        case .rest:
            return Color(red: 0.2, green: 0.78, blue: 0.35)  // Apple green
        case .activity:
            return Color(red: 1.0, green: 0.23, blue: 0.19)  // Apple red
        }
    }

    /// Text color (always white for contrast)
    public var textColor: Color {
        .white
    }

    /// SF Symbol icon name
    public var iconName: String {
        switch self {
        case .notPositioned:
            return "exclamationmark.triangle"
        case .rest:
            return "checkmark.circle"
        case .activity:
            return "waveform.path.ecg"
        }
    }

    /// Primary status text
    public var statusText: String {
        switch self {
        case .notPositioned:
            return "Position Device"
        case .rest:
            return "Monitoring"
        case .activity:
            return "Activity Detected"
        }
    }

    /// Secondary description
    public var description: String {
        switch self {
        case .notPositioned:
            return "Place device on skin"
        case .rest:
            return "Muscle at rest"
        case .activity:
            return "Muscle contraction"
        }
    }

    // MARK: - Factory

    /// Create state from sensor data
    /// - Parameters:
    ///   - temperature: Current temperature in °C
    ///   - irValue: Current PPG IR value
    ///   - threshold: Activity threshold
    ///   - isCalibrated: Whether calibration is complete
    ///   - normalizedPercent: Normalized IR as percentage (if calibrated)
    /// - Returns: Current positioning state
    public static func from(
        temperature: Double,
        irValue: Int,
        threshold: Int,
        isCalibrated: Bool = false,
        normalizedPercent: Double? = nil
    ) -> PositioningState {
        // Check if device is positioned (temp >= 32°C)
        guard temperature >= 32.0 else {
            return .notPositioned
        }

        // If calibrated, use normalized percentage
        if isCalibrated, let normalized = normalizedPercent {
            // Assuming threshold is stored as percentage (e.g., 40 = 40%)
            return normalized > Double(threshold) ? .activity : .rest
        }

        // Fallback to absolute threshold
        return irValue > threshold ? .activity : .rest
    }
}
