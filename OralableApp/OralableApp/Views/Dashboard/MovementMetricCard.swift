//
//  MovementMetricCard.swift
//  OralableApp
//
//  Movement-specific metric card with threshold-colored sparkline
//  showing active/still state and accelerometer data.
//
//  Extracted from DashboardView.swift
//

import SwiftUI
import Charts

// MARK: - Movement Metric Card (with threshold-colored sparkline)
struct MovementMetricCard: View {
    @EnvironmentObject var designSystem: DesignSystem
    let value: String
    let unit: String
    let statusText: String  // "Active", "Still", or "Not Connected"
    let isActive: Bool
    let isConnected: Bool
    let sparklineData: [Double]
    let threshold: Double
    let showChevron: Bool

    private var color: Color {
        guard isConnected else { return .gray }
        return isActive ? .green : .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: icon, title, chevron
            HStack {
                Image(systemName: "gyroscope")
                    .font(designSystem.typography.headline)
                    .foregroundColor(color)

                Text("Movement")
                    .font(designSystem.typography.captionBold)
                    .foregroundColor(designSystem.colors.textPrimary)

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(designSystem.typography.buttonSmall)
                        .foregroundColor(designSystem.colors.textTertiary)
                }
            }

            // Value row with movement sparkline
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

                    // Status indicator (Active/Still/Not Connected)
                    Text(statusText)
                        .font(designSystem.typography.labelMedium)
                        .foregroundColor(isConnected ? (isActive ? .green : .blue) : .secondary)
                        .padding(.leading, 8)
                }

                Spacer()

                // Movement sparkline with per-point coloring
                if !sparklineData.isEmpty && isConnected {
                    MovementSparkline(
                        data: sparklineData,
                        threshold: threshold,
                        isOverallActive: isActive,
                        activeColor: .green,
                        stillColor: .blue
                    )
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
        .accessibilityLabel("Movement, \(value) \(unit), \(statusText)")
        .accessibilityHint(showChevron ? "Double tap to view details" : "")
    }
}
