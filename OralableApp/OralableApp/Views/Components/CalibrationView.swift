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
    @ObservedObject var session: EventRecordingSession

    var body: some View {
        VStack(spacing: 16) {
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
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - State Views

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text("Calibration Required")
                .font(.headline)

            Text("Keep your jaw relaxed and remain still for 15 seconds to establish your baseline.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { session.startCalibration() }) {
                Label("Start Calibration", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
    }

    private func calibratingView(progress: Double) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: progress)

                Text("\(Int(progress * 100))%")
                    .font(.title2.bold())
            }

            Text("Calibrating...")
                .font(.headline)

            Text("Please remain still with jaw relaxed")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: {
                session.eventDetector.cancelCalibration()
                session.reset()
            }) {
                Text("Cancel")
                    .foregroundColor(.red)
            }
        }
    }

    private var calibratedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)

            Text("Calibration Complete")
                .font(.headline)

            HStack {
                Text("Baseline:")
                    .foregroundColor(.secondary)
                Text("\(Int(session.eventDetector.baseline))")
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Text("Threshold:")
                    .foregroundColor(.secondary)
                Text(session.eventDetector.effectiveThreshold)
                    .font(.system(.body, design: .monospaced))
            }

            Button(action: { session.startRecording() }) {
                Label("Start Recording", systemImage: "record.circle")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(10)
            }

            Button(action: { session.startCalibration() }) {
                Text("Recalibrate")
                    .foregroundColor(.blue)
            }
        }
    }

    private var recordingView: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)

                Text("Recording")
                    .font(.headline)

                Spacer()

                Text(session.summary.formattedDuration)
                    .font(.system(.title2, design: .monospaced))
            }

            HStack(spacing: 20) {
                StatView(label: "Events", value: "\(session.eventCount)")
                StatView(label: "Memory", value: session.summary.formattedMemory)
            }

            Button(action: { session.stopRecording() }) {
                Label("Stop Recording", systemImage: "stop.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(10)
            }
        }
    }

    private var stoppedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)

            Text("Recording Complete")
                .font(.headline)

            HStack(spacing: 20) {
                StatView(label: "Duration", value: session.summary.formattedDuration)
                StatView(label: "Events", value: "\(session.eventCount)")
            }

            HStack(spacing: 20) {
                StatView(label: "Samples", value: "\(session.samplesProcessed)")
                StatView(label: "Memory", value: session.summary.formattedMemory)
            }

            HStack(spacing: 12) {
                Button(action: { session.startCalibration() }) {
                    Label("New Recording", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
    }
}

// MARK: - Stat View

private struct StatView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .monospaced).bold())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    CalibrationView(session: EventRecordingSession())
        .padding()
}
