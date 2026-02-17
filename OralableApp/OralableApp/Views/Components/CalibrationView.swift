//
//  CalibrationView.swift
//  OralableApp
//
//  Created: January 13, 2026
//
//  UI for PPG calibration before recording.
//

import SwiftUI
import OralableCore

struct CalibrationView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @ObservedObject var session: EventRecordingSession

    var body: some View {
        VStack(spacing: designSystem.spacing.md) {
            switch session.sessionState {
            case .idle:
                idleView

            case .calibrating(let progress):
                calibratingView(progress: progress)

            case .calibrated:
                calibratedView

            case .recording:
                recordingView

            case .stopped:
                stoppedView
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundTertiary)
        .cornerRadius(designSystem.cornerRadius.large)
    }

    // MARK: - State Views

    private var idleView: some View {
        VStack(spacing: designSystem.spacing.buttonPadding) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 40))
                .foregroundColor(designSystem.colors.info)

            Text("Calibration Required")
                .font(designSystem.typography.headline)

            Text("Keep your jaw relaxed and remain still for 15 seconds to establish your baseline.")
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: { session.startCalibration() }) {
                Label("Start Calibration", systemImage: "play.fill")
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.primaryWhite)
                    .frame(maxWidth: .infinity)
                    .padding(designSystem.spacing.md)
                    .background(designSystem.colors.info)
                    .cornerRadius(designSystem.cornerRadius.medium)
            }
        }
    }

    private func calibratingView(progress: Double) -> some View {
        VStack(spacing: designSystem.spacing.md) {
            ZStack {
                Circle()
                    .stroke(designSystem.colors.gray300.opacity(0.3), lineWidth: 8)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(designSystem.colors.info, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: progress)

                Text("\(Int(progress * 100))%")
                    .font(designSystem.typography.h3)
            }

            Text("Calibrating...")
                .font(designSystem.typography.headline)

            Text("Please remain still with jaw relaxed")
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)

            Button(action: {
                session.eventDetector.cancelCalibration()
                session.reset()
            }) {
                Text("Cancel")
                    .foregroundColor(designSystem.colors.error)
            }
        }
    }

    private var calibratedView: some View {
        VStack(spacing: designSystem.spacing.buttonPadding) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(designSystem.colors.success)

            Text("Calibration Complete")
                .font(designSystem.typography.headline)

            HStack {
                Text("Baseline:")
                    .foregroundColor(designSystem.colors.textSecondary)
                Text("\(Int(session.eventDetector.baseline))")
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Text("Threshold:")
                    .foregroundColor(designSystem.colors.textSecondary)
                Text(session.eventDetector.effectiveThreshold)
                    .font(.system(.body, design: .monospaced))
            }

            Button(action: { session.startRecording() }) {
                Label("Start Recording", systemImage: "record.circle")
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.primaryWhite)
                    .frame(maxWidth: .infinity)
                    .padding(designSystem.spacing.md)
                    .background(designSystem.colors.error)
                    .cornerRadius(designSystem.cornerRadius.medium)
            }

            Button(action: { session.startCalibration() }) {
                Text("Recalibrate")
                    .foregroundColor(designSystem.colors.info)
            }
        }
    }

    private var recordingView: some View {
        VStack(spacing: designSystem.spacing.buttonPadding) {
            HStack {
                Circle()
                    .fill(designSystem.colors.error)
                    .frame(width: 12, height: 12)

                Text("Recording")
                    .font(designSystem.typography.headline)

                Spacer()

                Text(session.summary.formattedDuration)
                    .font(.system(.title2, design: .monospaced))
            }

            HStack(spacing: designSystem.spacing.screenPadding) {
                StatView(label: "Events", value: "\(session.eventCount)")
                StatView(label: "Memory", value: session.summary.formattedMemory)
            }

            Button(action: { session.stopRecording() }) {
                Label("Stop Recording", systemImage: "stop.fill")
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.primaryWhite)
                    .frame(maxWidth: .infinity)
                    .padding(designSystem.spacing.md)
                    .background(designSystem.colors.error)
                    .cornerRadius(designSystem.cornerRadius.medium)
            }
        }
    }

    private var stoppedView: some View {
        VStack(spacing: designSystem.spacing.buttonPadding) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(designSystem.colors.success)

            Text("Recording Complete")
                .font(designSystem.typography.headline)

            HStack(spacing: designSystem.spacing.screenPadding) {
                StatView(label: "Duration", value: session.summary.formattedDuration)
                StatView(label: "Events", value: "\(session.eventCount)")
            }

            HStack(spacing: designSystem.spacing.screenPadding) {
                StatView(label: "Samples", value: "\(session.samplesProcessed)")
                StatView(label: "Memory", value: session.summary.formattedMemory)
            }

            HStack(spacing: designSystem.spacing.buttonPadding) {
                Button(action: { session.startCalibration() }) {
                    Label("New Recording", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                        .padding(designSystem.spacing.md)
                        .background(designSystem.colors.info)
                        .foregroundColor(designSystem.colors.primaryWhite)
                        .cornerRadius(designSystem.cornerRadius.medium)
                }
            }
        }
    }
}

// MARK: - Stat View

private struct StatView: View {
    @EnvironmentObject var designSystem: DesignSystem
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: designSystem.spacing.xs) {
            Text(value)
                .font(.system(.title3, design: .monospaced).bold())
            Text(label)
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, designSystem.spacing.sm)
        .background(designSystem.colors.backgroundTertiary)
        .cornerRadius(designSystem.cornerRadius.medium)
    }
}

// MARK: - Preview

#Preview {
    CalibrationView(session: EventRecordingSession())
        .padding()
}
