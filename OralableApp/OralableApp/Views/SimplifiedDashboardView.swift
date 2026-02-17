//
//  SimplifiedDashboardView.swift
//  OralableApp
//
//  Minimal dashboard showing:
//  - Battery status (top right)
//  - Single PPG card with color-coded status
//  - Event count
//  - Automatic recording state indicator
//
//  Design: Apple-inspired black/white, light mode default
//
//  Updated: January 29, 2026 - Automatic recording (no manual button)
//

import SwiftUI
import OralableCore

struct SimplifiedDashboardView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @ObservedObject var viewModel: DashboardViewModel

    // Computed positioning state
    private var positioningState: PositioningState {
        PositioningState.from(
            temperature: viewModel.temperature,
            irValue: Int(viewModel.ppgIRValue),
            thresholdPercent: EventSettings.shared.normalizedThresholdPercent,
            isCalibrated: viewModel.isCalibrated,
            calibrationProgress: viewModel.calibrationProgress,
            baseline: viewModel.automaticRecordingSession?.stateDetector.baseline ?? 0
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top bar
                topBar

                // Main content
                ScrollView {
                    VStack(spacing: designSystem.spacing.lg) {
                        // Connection prompt (if not connected)
                        if !viewModel.isConnected {
                            connectionPrompt
                        }

                        // PPG Status Card
                        PPGStatusCard(
                            state: positioningState,
                            temperature: viewModel.temperature,
                            isConnected: viewModel.isConnected,
                            isCalibrating: viewModel.isCalibrating,
                            calibrationProgress: viewModel.calibrationProgress
                        )

                        // Event summary
                        eventSummary

                        // Recording state indicator (automatic recording)
                        recordingStateIndicator
                    }
                    .padding(designSystem.spacing.screenPadding)
                }
                .background(designSystem.colors.backgroundPrimary)
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Device name or connection status
            if viewModel.isConnected {
                Text(viewModel.deviceName)
                    .font(designSystem.typography.labelMedium)
                    .foregroundColor(designSystem.colors.textPrimary)
            } else {
                Text("Not Connected")
                    .font(designSystem.typography.labelMedium)
                    .foregroundColor(designSystem.colors.textSecondary)
            }

            Spacer()

            // Battery (if connected)
            if viewModel.isConnected {
                BatteryIndicator(
                    level: Int(viewModel.batteryLevel),
                    isCharging: viewModel.isCharging
                )
            }
        }
        .padding(.horizontal, designSystem.spacing.screenPadding)
        .padding(.vertical, designSystem.spacing.buttonPadding)
        .background(designSystem.colors.backgroundPrimary)
    }

    // MARK: - Connection Prompt

    private var connectionPrompt: some View {
        VStack(spacing: designSystem.spacing.buttonPadding) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundColor(designSystem.colors.textSecondary)

            Text("Connect to start monitoring")
                .font(designSystem.typography.labelMedium)
                .foregroundColor(designSystem.colors.textSecondary)

            Button(action: { viewModel.startScanning() }) {
                Text("Scan for Devices")
                    .font(designSystem.typography.captionBold)
                    .foregroundColor(designSystem.colors.primaryWhite)
                    .padding(.horizontal, designSystem.spacing.lg)
                    .padding(.vertical, designSystem.spacing.sm + 2)
                    .background(designSystem.colors.primaryBlack)
                    .cornerRadius(designSystem.cornerRadius.xl)
            }
        }
        .padding(.vertical, designSystem.spacing.lg)
    }

    // MARK: - Event Summary

    private var eventSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
                Text("State Transitions")
                    .font(designSystem.typography.labelSmall)
                    .foregroundColor(designSystem.colors.textSecondary)

                Text("\(viewModel.eventCount)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(designSystem.colors.textPrimary)
            }

            Spacer()

            // Duration
            if viewModel.isRecording {
                VStack(alignment: .trailing, spacing: designSystem.spacing.xs) {
                    Text("Duration")
                        .font(designSystem.typography.labelSmall)
                        .foregroundColor(designSystem.colors.textSecondary)

                    Text(viewModel.formattedDuration)
                        .font(designSystem.typography.labelMedium)
                        .foregroundColor(designSystem.colors.textPrimary)
                }
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundTertiary)
        .cornerRadius(designSystem.cornerRadius.large)
    }

    // MARK: - Recording State Indicator (Automatic Recording)

    private var recordingStateIndicator: some View {
        Group {
            if viewModel.isConnected {
                HStack(spacing: designSystem.spacing.buttonPadding) {
                    // State color indicator
                    Circle()
                        .fill(stateColor)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: designSystem.spacing.xxs) {
                        Text("Recording: \(stateDisplayName)")
                            .font(designSystem.typography.labelMedium)
                            .foregroundColor(designSystem.colors.textPrimary)

                        Text("Automatic • \(viewModel.eventCount) events")
                            .font(designSystem.typography.captionSmall)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }

                    Spacer()

                    if viewModel.isRecording {
                        Text(viewModel.formattedDuration)
                            .font(designSystem.typography.labelMedium)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                }
                .padding(designSystem.spacing.md)
                .background(designSystem.colors.backgroundTertiary)
                .cornerRadius(designSystem.cornerRadius.large)
            }
        }
    }

    private var stateColor: Color {
        switch viewModel.currentRecordingState {
        case .dataStreaming:
            return designSystem.colors.primaryBlack
        case .positioned:
            return designSystem.colors.success
        case .activity:
            return designSystem.colors.error
        }
    }

    private var stateDisplayName: String {
        viewModel.currentRecordingState.displayName
    }
}

// MARK: - Preview

struct SimplifiedDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        // Note: Preview requires mock view model
        Text("SimplifiedDashboardView Preview")
    }
}
