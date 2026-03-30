//
//  TrialSetupDashboardView.swift
//  OralableApp
//
//  Shown when the user exits device pairing during first-launch setup without connecting.
//

import SwiftUI

struct TrialSetupDashboardView: View {
    @ObservedObject var firstLaunchManager: FirstLaunchManager
    @EnvironmentObject var designSystem: DesignSystem

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: designSystem.spacing.lg) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 44))
                        .foregroundColor(designSystem.colors.gray500)
                        .frame(maxWidth: .infinity)

                    Text("Trial setup")
                        .font(designSystem.typography.h2)
                        .foregroundColor(designSystem.colors.textPrimary)

                    Text(
                        "You’re in a limited trial view. Connect your Oralable REV10 headset to unlock live PPG, Temporalis fit, calibration, overnight capture, and exports. Tap below when you’re ready to pair."
                    )
                    .font(designSystem.typography.body)
                    .foregroundColor(designSystem.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    trialLimitationsCard

                    Button {
                        firstLaunchManager.exitTrialSetupMode()
                    } label: {
                        Label("Connect Oralable Node", systemImage: "link.circle.fill")
                            .font(designSystem.typography.labelMedium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(designSystem.colors.primaryBlack)
                            .foregroundColor(designSystem.colors.primaryWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(designSystem.spacing.lg)
            }
            .background(designSystem.colors.backgroundSecondary)
            .navigationTitle("Oralable")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var trialLimitationsCard: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            Text("What stays locked until you connect")
                .font(designSystem.typography.headline)
                .foregroundColor(designSystem.colors.textPrimary)
            VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
                bullet("Live dashboard vitals and recording from your headset")
                bullet("Temporalis mirror fit and IR-DC calibration")
                bullet("Share, clinical PDF, and professional handshake export")
            }
            .font(designSystem.typography.bodySmall)
            .foregroundColor(designSystem.colors.textSecondary)
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(designSystem.colors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: designSystem.spacing.sm, style: .continuous))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: designSystem.spacing.sm) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
