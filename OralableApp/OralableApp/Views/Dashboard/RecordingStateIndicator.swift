//
//  RecordingStateIndicator.swift
//  OralableApp
//
//  Visual indicator for automatic recording state showing:
//  - DataStreaming (Black), Positioned (Green), Activity (Red)
//  - Calibration progress when applicable
//  - Duration and event count badges
//
//  Extracted from DashboardView.swift
//

import SwiftUI

// MARK: - Recording State Indicator (Automatic Recording)
struct RecordingStateIndicator: View {
    let state: DeviceRecordingState
    let isCalibrated: Bool
    let calibrationProgress: Double
    let eventCount: Int
    let duration: String

    private var stateColor: Color {
        switch state {
        case .dataStreaming:
            return .black
        case .positioned:
            return .green
        case .activity:
            return .red
        }
    }

    private var stateIcon: String {
        switch state {
        case .dataStreaming:
            return "waveform"
        case .positioned:
            return "checkmark.circle.fill"
        case .activity:
            return "bolt.fill"
        }
    }

    private var statusText: String {
        if !isCalibrated && state == .positioned {
            return "Calibrating..."
        }
        return state.displayName
    }

    var body: some View {
        VStack(spacing: 8) {
            // State indicator circle
            ZStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 50, height: 50)
                    .shadow(color: stateColor.opacity(0.3), radius: 6, x: 0, y: 3)

                Image(systemName: stateIcon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }

            // Status text
            Text(statusText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(stateColor)

            // Calibration progress (if calibrating)
            if !isCalibrated && state == .positioned && calibrationProgress > 0 {
                ProgressView(value: calibrationProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .frame(width: 100)
                Text("\(Int(calibrationProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Duration and events
            HStack(spacing: 16) {
                StatBadge(label: "Time", value: duration)
                StatBadge(label: "Events", value: "\(eventCount)")
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Stat Badge
struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}
