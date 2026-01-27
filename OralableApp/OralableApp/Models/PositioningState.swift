//
//  PositioningState.swift
//  OralableApp
//
//  Device positioning and activity state for simplified dashboard.
//  Color-coded: Black (not positioned/calibrating), Green (rest), Red (activity)
//

import SwiftUI

/// Device positioning and muscle activity state
public enum PositioningState: Equatable {
    /// Device not correctly positioned (temp < 32°C)
    case notPositioned

    /// Calibrating (temp ≥ 32°C but baseline not yet established)
    case calibrating(progress: Double)

    /// Correctly positioned, muscle at rest
    case rest

    /// Correctly positioned, muscle active (above threshold)
    case activity

    // MARK: - Colors (Apple-inspired)

    /// Background color for the PPG card
    public var backgroundColor: Color {
        switch self {
        case .notPositioned, .calibrating:
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
        case .calibrating:
            return "circle.dotted"
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
        case .calibrating(let progress):
            return "Calibrating \(Int(progress * 100))%"
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
        case .calibrating:
            return "Keep jaw relaxed"
        case .rest:
            return "Muscle at rest"
        case .activity:
            return "Muscle contraction"
        }
    }

    /// Whether state should show as black
    public var isBlack: Bool {
        switch self {
        case .notPositioned, .calibrating:
            return true
        case .rest, .activity:
            return false
        }
    }

    // MARK: - Factory

    /// Create state from sensor data
    /// - Parameters:
    ///   - temperature: Current temperature in °C
    ///   - irValue: Current PPG IR value
    ///   - thresholdPercent: Normalized threshold percentage (e.g., 40.0)
    ///   - isCalibrated: Whether calibration is complete
    ///   - calibrationProgress: Progress 0.0 to 1.0
    ///   - baseline: Calibrated baseline IR value
    /// - Returns: Current positioning state
    public static func from(
        temperature: Double,
        irValue: Int,
        thresholdPercent: Double,
        isCalibrated: Bool,
        calibrationProgress: Double,
        baseline: Double
    ) -> PositioningState {
        // Temperature parameter kept for API compatibility but no longer used for positioning
        // Optical metrics (HR, SpO2, PI) now determine positioning status

        // Check if calibrated
        guard isCalibrated else {
            return .calibrating(progress: calibrationProgress)
        }

        // Calculate absolute threshold from baseline
        let absoluteThreshold = baseline * (1.0 + thresholdPercent / 100.0)
        return Double(irValue) >= absoluteThreshold ? .activity : .rest
    }
}
