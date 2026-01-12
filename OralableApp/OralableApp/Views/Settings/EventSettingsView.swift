//
//  EventSettingsView.swift
//  OralableApp
//
//  Created: January 8, 2026
//  Updated: January 12, 2026 - Added recording mode setting and memory estimates
//  Settings for event detection threshold and recording mode
//

import SwiftUI

struct EventSettingsView: View {

    @ObservedObject var settings = EventSettings.shared

    var body: some View {
        Form {
            // Recording Mode Section
            Section {
                Picker("Recording Mode", selection: $settings.recordingMode) {
                    Text("Event-Based (Recommended)").tag(RecordingMode.eventBased)
                    Text("Continuous (Legacy)").tag(RecordingMode.continuous)
                }
            } header: {
                Text("Recording Mode")
            } footer: {
                Text(recordingModeFooter)
            }

            // Threshold Section (for event-based mode)
            if settings.recordingMode == .eventBased {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("IR Threshold")
                            .font(.headline)

                        Text("Events are detected when PPG IR exceeds this value. Lower values detect more events, higher values detect only stronger muscle activity.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text(EventSettings.formattedMinThreshold)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .leading)

                            Slider(
                                value: Binding(
                                    get: { Double(settings.threshold) },
                                    set: { settings.threshold = Int($0) }
                                ),
                                in: Double(EventSettings.minThreshold)...Double(EventSettings.maxThreshold),
                                step: Double(EventSettings.thresholdStep)
                            )
                            .tint(.orange)

                            Text(EventSettings.formattedMaxThreshold)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }

                        HStack {
                            Spacer()
                            Text("Current: \(settings.formattedThreshold)")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Event Detection")
                }

                Section {
                    ThresholdPresetButton(
                        title: "Sensitive",
                        description: "Detects light muscle activity",
                        value: 75000,
                        currentValue: settings.threshold
                    ) {
                        settings.threshold = 75000
                    }

                    ThresholdPresetButton(
                        title: "Normal",
                        description: "Balanced detection",
                        value: 150000,
                        currentValue: settings.threshold
                    ) {
                        settings.threshold = 150000
                    }

                    ThresholdPresetButton(
                        title: "Strong Only",
                        description: "Detects only strong activity",
                        value: 250000,
                        currentValue: settings.threshold
                    ) {
                        settings.threshold = 250000
                    }
                } header: {
                    Text("Presets")
                }
            }

            // Memory Comparison Section
            Section {
                HStack {
                    Text("1 Hour Recording")
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(settings.recordingMode == .eventBased ? "~20 KB" : "~18 MB")
                            .font(.system(.body, design: .monospaced))
                        Text(settings.recordingMode == .eventBased ? "Events only" : "All samples")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("8 Hour Recording")
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(settings.recordingMode == .eventBased ? "~160 KB" : "~144 MB")
                            .font(.system(.body, design: .monospaced))
                        Text(settings.recordingMode == .eventBased ? "Events only" : "All samples")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Estimated Memory Usage")
            }

            Section {
                Button("Reset to Default") {
                    settings.resetToDefault()
                }
                .foregroundColor(.blue)
            }
        }
        .navigationTitle("Event Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var recordingModeFooter: String {
        switch settings.recordingMode {
        case .eventBased:
            return "Event-based mode detects muscle activity in real-time and only stores events. Uses 99.9% less memory."
        case .continuous:
            return "Continuous mode stores all sensor samples. Uses significantly more memory but preserves raw data."
        }
    }
}

// MARK: - Preset Button

private struct ThresholdPresetButton: View {
    let title: String
    let description: String
    let value: Int
    let currentValue: Int
    let action: () -> Void

    private var isSelected: Bool {
        currentValue == value
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Text("\(value / 1000)k")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        EventSettingsView()
    }
}
