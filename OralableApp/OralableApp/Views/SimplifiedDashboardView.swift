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
        NavigationView {
            VStack(spacing: 0) {
                // Top bar
                topBar

                // Main content
                ScrollView {
                    VStack(spacing: 24) {
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
                    .padding(20)
                }
                .background(Color(.systemBackground))
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            } else {
                Text("Not Connected")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    // MARK: - Connection Prompt

    private var connectionPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("Connect to start monitoring")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            Button(action: { viewModel.startScanning() }) {
                Text("Scan for Devices")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.black)
                    .cornerRadius(20)
            }
        }
        .padding(.vertical, 24)
    }

    // MARK: - Event Summary

    private var eventSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("State Transitions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Text("\(viewModel.eventCount)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            Spacer()

            // Duration
            if viewModel.isRecording {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Duration")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(viewModel.formattedDuration)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Recording State Indicator (Automatic Recording)

    private var recordingStateIndicator: some View {
        Group {
            if viewModel.isConnected {
                HStack(spacing: 12) {
                    // State color indicator
                    Circle()
                        .fill(stateColor)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recording: \(stateDisplayName)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)

                        Text("Automatic • \(viewModel.eventCount) events")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if viewModel.isRecording {
                        Text(viewModel.formattedDuration)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    private var stateColor: Color {
        switch viewModel.currentRecordingState {
        case .dataStreaming:
            return .black
        case .positioned:
            return .green
        case .activity:
            return .red
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
