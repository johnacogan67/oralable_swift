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
            Text(displayTitle)
                .font(designSystem.typography.headline)
                .foregroundColor(designSystem.colors.textPrimary)

            if let result, result.analysis != nil {
                Text(wearCaption(for: result))
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)

                if result.isEvaluable {
                    bandChips(OvernightBandCalculator.chips(from: result))
                }

                StateHypnogramView(analysis: result.analysis)

                Text(result.isSimulated
                    ? "Simulated night. Device-inferred wellness states — not a recorded night. Not AHI."
                    : "Device-inferred wellness states — not a medical diagnosis. Not AHI.")
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.textTertiary)
            } else {
                Text("Wear overnight with pad or tape on the temple. Bands from ≥1 h. Beacon night ≥4 h (6 h better).")
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

    private var displayTitle: String {
        if result?.isSimulated == true {
            return "Simulated night"
        }
        return title
    }

    private func wearCaption(for result: OvernightNightReportBuilder.Result) -> String {
        let hours = result.wearHoursText
        let base: String
        if result.isFigureQuality {
            base = "\(hours) · figure-quality night (≥6 h)"
        } else if result.isBeaconFeasible {
            base = "\(hours) · Beacon evaluable (≥4 h). 6 h better for the hypnogram figure."
        } else if result.isEvaluable {
            base = "\(hours) · bands shown. Beacon target is ≥4 h (6 h better)."
        } else {
            base = "\(hours) · bands from ≥1 h worn."
        }
        if result.isSimulated {
            return "Simulated. \(base)"
        }
        return base
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
