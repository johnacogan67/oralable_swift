//
//  EventSettingsView.swift
//  OralableApp
//
//  Created: January 8, 2026
//  Updated: January 15, 2026 - Simplified to normalized-only detection
//
//  Settings for event detection threshold (normalized mode only).
//

import SwiftUI
import OralableCore

struct EventSettingsView: View {

    @ObservedObject var settings = EventSettings.shared

    var body: some View {
        Form {
            // Detection Mode Info Section
            Section {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(.orange)
                    Text("Normalized Detection")
                        .font(.headline)
                }

                Text("Events are detected when PPG IR exceeds a percentage above your calibrated baseline. This works consistently across different users and sensor placements.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Detection Mode")
            } footer: {
                Text("Calibration is required before each recording session (15 seconds).")
            }

            // Normalized Threshold Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Threshold Percentage")
                        .font(.headline)

                    Text("Lower values detect more events, higher values detect only stronger activity.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("\(Int(EventSettings.minNormalizedThreshold))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .leading)

                        Slider(
                            value: $settings.normalizedThresholdPercent,
                            in: EventSettings.minNormalizedThreshold...EventSettings.maxNormalizedThreshold,
                            step: 5.0
                        )
                        .tint(.orange)

                        Text("\(Int(EventSettings.maxNormalizedThreshold))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }

                    HStack {
                        Spacer()
                        Text("Current: \(settings.formattedNormalizedThreshold)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 8)
            } header: {
                Text("Threshold")
            }

            // Presets Section
            Section {
                PresetButton(
                    title: "Sensitive",
                    description: "Detects light muscle activity",
                    value: 25.0,
                    currentValue: settings.normalizedThresholdPercent
                ) {
                    settings.normalizedThresholdPercent = 25.0
                }

                PresetButton(
                    title: "Normal",
                    description: "Balanced detection",
                    value: 40.0,
                    currentValue: settings.normalizedThresholdPercent
                ) {
                    settings.normalizedThresholdPercent = 40.0
                }

                PresetButton(
                    title: "Strong Only",
                    description: "Detects only strong activity",
                    value: 60.0,
                    currentValue: settings.normalizedThresholdPercent
                ) {
                    settings.normalizedThresholdPercent = 60.0
                }
            } header: {
                Text("Presets")
            }

            // Memory Comparison Section
            Section {
                HStack {
                    Text("1 Hour Recording")
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("~20 KB")
                            .font(.system(.body, design: .monospaced))
                        Text("Events only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("8 Hour Recording")
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("~160 KB")
                            .font(.system(.body, design: .monospaced))
                        Text("Events only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Estimated Memory Usage")
            } footer: {
                Text("Event-based detection uses 99.9% less memory than storing raw samples.")
            }

            Section {
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .foregroundColor(.blue)
            }
        }
        .navigationTitle("Event Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preset Button

private struct PresetButton: View {
    let title: String
    let description: String
    let value: Double
    let currentValue: Double
    let action: () -> Void

    private var isSelected: Bool {
        abs(currentValue - value) < 0.1
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
                    Text("\(Int(value))%")
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
