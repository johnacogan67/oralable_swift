//
//  ThresholdsSettingsView.swift
//  OralableApp
//
//  Created: December 2025
//  Purpose: Settings screen for adjusting detection thresholds
//

import SwiftUI

struct ThresholdsSettingsView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @ObservedObject private var settings = ThresholdSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Movement Threshold Section
            Section {
                VStack(alignment: .leading, spacing: designSystem.spacing.md) {
                    // Header with current value
                    HStack {
                        Text("Movement Threshold")
                            .font(designSystem.typography.headline)
                        Spacer()
                        Text(formatThreshold(settings.movementThreshold))
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(thresholdColor)
                    }

                    // Slider
                    Slider(
                        value: $settings.movementThreshold,
                        in: ThresholdSettings.movementThresholdRange,
                        step: ThresholdSettings.movementThresholdStep
                    )
                    .tint(designSystem.colors.info)

                    // Labels
                    HStack {
                        VStack(alignment: .leading) {
                            Text("More Sensitive")
                                .font(designSystem.typography.caption)
                                .foregroundColor(designSystem.colors.success)
                            Text("500")
                                .font(designSystem.typography.caption2)
                                .foregroundColor(designSystem.colors.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Less Sensitive")
                                .font(designSystem.typography.caption)
                                .foregroundColor(designSystem.colors.info)
                            Text("5K")
                                .font(designSystem.typography.caption2)
                                .foregroundColor(designSystem.colors.textSecondary)
                        }
                    }

                    // Visual indicator
                    HStack(spacing: designSystem.spacing.xs) {
                        Image(systemName: "figure.walk")
                            .foregroundColor(isCurrentlyActive ? designSystem.colors.success : designSystem.colors.info)
                        Text(isCurrentlyActive ? "More likely to show Active" : "More likely to show Still")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                    .padding(.top, designSystem.spacing.xs)
                }
                .padding(.vertical, designSystem.spacing.sm)
            } header: {
                Text("Movement Detection")
            } footer: {
                Text("Adjusts how much movement is required to change from 'Still' (blue) to 'Active' (green) on the dashboard. Default is 1.5K.")
            }

            // Info Section
            Section {
                VStack(alignment: .leading, spacing: designSystem.spacing.buttonPadding) {
                    infoRow(
                        icon: "arrow.down.circle.fill",
                        color: designSystem.colors.success,
                        title: "Lower values (500-1000)",
                        description: "Detect small movements. Good for sensitive monitoring."
                    )

                    Divider()

                    infoRow(
                        icon: "minus.circle.fill",
                        color: designSystem.colors.info,
                        title: "Default value (1500)",
                        description: "Balanced sensitivity for typical use."
                    )

                    Divider()

                    infoRow(
                        icon: "arrow.up.circle.fill",
                        color: designSystem.colors.warning,
                        title: "Higher values (2000-5000)",
                        description: "Only detect significant movement. Reduces false positives."
                    )
                }
                .padding(.vertical, designSystem.spacing.xs)
            } header: {
                Text("Guide")
            }

            // Reset Section
            Section {
                Button(action: {
                    withAnimation {
                        settings.resetToDefaults()
                    }
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Defaults")
                        Spacer()
                    }
                    .foregroundColor(designSystem.colors.info)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Thresholds")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helper Views

    private func infoRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: designSystem.spacing.buttonPadding) {
            Image(systemName: icon)
                .font(.system(size: designSystem.spacing.screenPadding))
                .foregroundColor(color)
                .frame(width: designSystem.spacing.lg)

            VStack(alignment: .leading, spacing: designSystem.spacing.xxs) {
                Text(title)
                    .font(designSystem.typography.bodySmall)
                    .fontWeight(.medium)
                Text(description)
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            }
        }
    }

    // MARK: - Computed Properties

    private var thresholdColor: Color {
        if settings.movementThreshold < 1000 {
            return designSystem.colors.success
        } else if settings.movementThreshold > 2500 {
            return designSystem.colors.warning
        } else {
            return designSystem.colors.info
        }
    }

    private var isCurrentlyActive: Bool {
        settings.movementThreshold < ThresholdSettings.defaultMovementThreshold
    }

    // MARK: - Helper Functions

    private func formatThreshold(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fK", value / 1000)
        } else {
            return String(format: "%.0f", value)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ThresholdsSettingsView()
    }
}
