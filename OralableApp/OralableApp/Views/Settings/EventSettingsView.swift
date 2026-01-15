//
//  EventSettingsView.swift
//  OralableApp
//
//  Created: January 8, 2026
//  Updated: January 13, 2026 - Updated for detection mode (absolute/normalized)
//
//  Settings for event detection threshold and detection mode
//

import SwiftUI
import OralableCore

struct EventSettingsView: View {

    @ObservedObject var settings = EventSettings.shared

    var body: some View {
        Form {
            // Detection Mode Section
            Section {
                Picker("Detection Mode", selection: $settings.detectionMode) {
                    Text("Normalized (Recommended)").tag(DetectionMode.normalized)
                    Text("Absolute (Fixed)").tag(DetectionMode.absolute)
                }
            } header: {
                Text("Detection Mode")
            } footer: {
                Text(detectionModeFooter)
            }

            // Threshold Section - varies by mode
            if settings.detectionMode == .normalized {
                // Normalized mode - percentage threshold
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Threshold Percentage")
                            .font(.headline)

                        Text("Events are detected when PPG IR exceeds this percentage above your calibrated baseline. Lower values detect more events.")
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
                    Text("Normalized Threshold")
                }

                Section {
                    NormalizedPresetButton(
                        title: "Sensitive",
                        description: "Detects light muscle activity",
                        value: 25.0,
                        currentValue: settings.normalizedThresholdPercent
                    ) {
                        settings.normalizedThresholdPercent = 25.0
                    }

                    NormalizedPresetButton(
                        title: "Normal",
                        description: "Balanced detection",
                        value: 40.0,
                        currentValue: settings.normalizedThresholdPercent
                    ) {
                        settings.normalizedThresholdPercent = 40.0
                    }

                    NormalizedPresetButton(
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

            } else {
                // Absolute mode - fixed threshold
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("IR Threshold")
                            .font(.headline)

                        Text("Events are detected when PPG IR exceeds this fixed value. May need adjustment for different users.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text(EventSettings.formattedMinAbsoluteThreshold)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .leading)

                            Slider(
                                value: Binding(
                                    get: { Double(settings.absoluteThreshold) },
                                    set: { settings.absoluteThreshold = Int($0) }
                                ),
                                in: Double(EventSettings.minAbsoluteThreshold)...Double(EventSettings.maxAbsoluteThreshold),
                                step: Double(EventSettings.thresholdStep)
                            )
                            .tint(.orange)

                            Text(EventSettings.formattedMaxAbsoluteThreshold)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }

                        HStack {
                            Spacer()
                            Text("Current: \(settings.formattedAbsoluteThreshold)")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Absolute Threshold")
                }

                Section {
                    AbsolutePresetButton(
                        title: "Sensitive",
                        description: "Detects light muscle activity",
                        value: 75000,
                        currentValue: settings.absoluteThreshold
                    ) {
                        settings.absoluteThreshold = 75000
                    }

                    AbsolutePresetButton(
                        title: "Normal",
                        description: "Balanced detection",
                        value: 150000,
                        currentValue: settings.absoluteThreshold
                    ) {
                        settings.absoluteThreshold = 150000
                    }

                    AbsolutePresetButton(
                        title: "Strong Only",
                        description: "Detects only strong activity",
                        value: 250000,
                        currentValue: settings.absoluteThreshold
                    ) {
                        settings.absoluteThreshold = 250000
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

    private var detectionModeFooter: String {
        switch settings.detectionMode {
        case .normalized:
            return "Normalized mode uses a percentage above your calibrated baseline. Works consistently across different users and sensor placements. Requires 15-second calibration before recording."
        case .absolute:
            return "Absolute mode uses a fixed threshold value. May need adjustment for different users or sensor placements. No calibration required."
        }
    }
}

// MARK: - Normalized Preset Button

private struct NormalizedPresetButton: View {
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

// MARK: - Absolute Preset Button

private struct AbsolutePresetButton: View {
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
