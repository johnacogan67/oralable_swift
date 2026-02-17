//
//  HealthMetricCard.swift
//  OralableApp
//
//  Apple Health-style metric card for displaying sensor values
//  with icon, title, value, unit, and optional sparkline.
//
//  Extracted from DashboardView.swift
//

import SwiftUI
import Charts

// MARK: - Health Metric Card (Apple Health Style)
struct HealthMetricCard: View {
    @EnvironmentObject var designSystem: DesignSystem
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color
    let sparklineData: [Double]
    let showChevron: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: icon, title, chevron
            HStack {
                Image(systemName: icon)
                    .font(designSystem.typography.headline)
                    .foregroundColor(color)

                Text(title)
                    .font(designSystem.typography.captionBold)
                    .foregroundColor(designSystem.colors.textPrimary)

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(designSystem.typography.buttonSmall)
                        .foregroundColor(designSystem.colors.textTertiary)
                }
            }

            // Value row with optional sparkline
            HStack(alignment: .bottom) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(designSystem.typography.displaySmall)
                        .foregroundColor(designSystem.colors.textPrimary)

                    if !unit.isEmpty {
                        Text(unit)
                            .font(designSystem.typography.body)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                }

                Spacer()

                // Mini sparkline
                if !sparklineData.isEmpty {
                    MiniSparkline(data: sparklineData, color: color)
                        .frame(width: 50, height: 30)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(designSystem.spacing.cardPadding)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.xl)
        .designShadow(.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value) \(unit)")
        .accessibilityHint(showChevron ? "Double tap to view details" : "")
    }
}
