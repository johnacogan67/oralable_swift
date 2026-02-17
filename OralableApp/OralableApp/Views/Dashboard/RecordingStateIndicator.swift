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
    @EnvironmentObject var designSystem: DesignSystem
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
        VStack(spacing: designSystem.spacing.sm) {
            // State indicator circle
            ZStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 50, height: 50)
                    .shadow(color: stateColor.opacity(0.3), radius: 6, x: 0, y: 3)

                Image(systemName: stateIcon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(designSystem.colors.primaryWhite)
            }

            // Status text
            Text(statusText)
                .font(designSystem.typography.captionBold)
                .foregroundColor(stateColor)

            // Calibration progress (if calibrating)
            if !isCalibrated && state == .positioned && calibrationProgress > 0 {
                ProgressView(value: calibrationProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: designSystem.colors.success))
                    .frame(width: 100)
                Text("\(Int(calibrationProgress * 100))%")
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.textSecondary)
            }

            // Duration and events
            HStack(spacing: designSystem.spacing.md) {
                StatBadge(label: "Time", value: duration)
                StatBadge(label: "Events", value: "\(eventCount)")
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.large)
        .designShadow(.small)
    }
}

// MARK: - Stat Badge
struct StatBadge: View {
    @EnvironmentObject var designSystem: DesignSystem
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: designSystem.spacing.xs) {
            Text(label)
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.textSecondary)
            Text(value)
                .font(designSystem.typography.captionBold)
                .foregroundColor(designSystem.colors.textPrimary)
        }
        .padding(.horizontal, designSystem.spacing.sm)
        .padding(.vertical, designSystem.spacing.xs)
        .background(designSystem.colors.textSecondary.opacity(0.1))
        .cornerRadius(designSystem.cornerRadius.medium)
    }
}
