//
//  OvernightMorningCardView.swift
//  OralableApp
//
//  Dashboard / Share card: band chips + state hypnogram (FIG-CO-025 adaptation).
//  Wellness wording only — not a medical diagnosis.
//

import SwiftUI

struct OvernightMorningCardView: View {
    @EnvironmentObject var designSystem: DesignSystem

    let result: OvernightNightReportBuilder.Result?
    var title: String = "Last night"
    var showEmptyWhenInsufficient: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            Text(title)
                .font(designSystem.typography.headline)
                .foregroundColor(designSystem.colors.textPrimary)

            if let result, result.analysis != nil {
                if result.isEvaluable {
                    bandChips(OvernightBandCalculator.chips(from: result))
                } else if showEmptyWhenInsufficient {
                    Text("Need ≥6 hours worn for overnight bands.")
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                }

                StateHypnogramView(analysis: result.analysis)

                Text("Device-inferred wellness states — not a medical diagnosis.")
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.textTertiary)
            } else {
                Text("Need ≥6 hours worn for overnight bands.")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
                StateHypnogramView(analysis: nil)
            }
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.card)
    }

    private func bandChips(_ chips: [OvernightBandChip]) -> some View {
        HStack(spacing: designSystem.spacing.sm) {
            ForEach(chips) { chip in
                VStack(alignment: .leading, spacing: 2) {
                    Text(chip.label)
                        .font(designSystem.typography.captionSmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                    Text(chip.level.rawValue)
                        .font(designSystem.typography.labelMedium)
                        .foregroundColor(color(for: chip.level))
                    Text(chip.valueText)
                        .font(designSystem.typography.caption2)
                        .foregroundColor(designSystem.colors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(designSystem.spacing.sm)
                .background(designSystem.colors.backgroundPrimary)
                .cornerRadius(designSystem.cornerRadius.button)
            }
        }
    }

    private func color(for level: OvernightBandLevel) -> Color {
        switch level {
        case .low: return designSystem.colors.success
        case .moderate: return designSystem.colors.warning
        case .high: return designSystem.colors.error
        case .insufficient: return designSystem.colors.textSecondary
        }
    }
}
