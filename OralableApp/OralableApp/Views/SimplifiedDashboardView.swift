//
//  SimplifiedDashboardView.swift
//  OralableApp
//
//  Minimal dashboard showing:
//  - Battery status (top right)
//  - Single PPG card with color-coded status
//  - Event count
//  - Recording button
//
//  Design: Apple-inspired black/white, light mode default
//

import SwiftUI

struct SimplifiedDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    // Computed positioning state
    private var positioningState: PositioningState {
        PositioningState.from(
            temperature: viewModel.temperature,
            irValue: Int(viewModel.ppgIRValue),
            threshold: Int(EventSettings.shared.normalizedThresholdPercent),
            isCalibrated: viewModel.eventSession?.isCalibrated ?? false,
            normalizedPercent: nil
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
                            isCalibrating: viewModel.eventSession?.isCalibrating ?? false,
                            calibrationProgress: viewModel.eventSession?.calibrationProgress ?? 0
                        )

                        // Event summary
                        eventSummary

                        // Recording button
                        recordingButton
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
                Text("Events")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(viewModel.eventCount)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    if viewModel.discardedEventCount > 0 {
                        Text("(\(viewModel.discardedEventCount) unvalidated)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Recording indicator
            if viewModel.isRecording {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Recording")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                    }

                    Text(viewModel.formattedDuration)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Recording Button

    private var recordingButton: some View {
        Button(action: { viewModel.toggleRecording() }) {
            HStack {
                Image(systemName: viewModel.isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 18))

                Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(viewModel.isRecording ? Color.red : Color.black)
            .cornerRadius(12)
        }
        .disabled(!viewModel.isConnected)
        .opacity(viewModel.isConnected ? 1.0 : 0.5)
    }
}

// MARK: - Preview

struct SimplifiedDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        // Note: Preview requires mock view model
        Text("SimplifiedDashboardView Preview")
    }
}
