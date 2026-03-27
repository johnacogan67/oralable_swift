//
//  FirstLaunchOnboardingView.swift
//  OralableApp
//
//  Post-sign-in wizard: video placeholder, researcher one-sheet, then Temporalis fit gate.
//

import SwiftUI

struct FirstLaunchOnboardingView: View {
    @ObservedObject var firstLaunchManager: FirstLaunchManager
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var deviceManagerAdapter: DeviceManagerAdapter
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var sessionHistoryStore: SessionHistoryStore
    @EnvironmentObject var sensorDataProcessor: SensorDataProcessor

    @State private var showFitGuide = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: designSystem.spacing.lg) {
                    Text("Before your first night")
                        .font(designSystem.typography.h2)
                        .foregroundColor(designSystem.colors.textPrimary)

                    Text("Complete this short setup once. It aligns every trial night with the same Temporalis placement standard.")
                        .font(designSystem.typography.body)
                        .foregroundColor(designSystem.colors.textSecondary)

                    videoPlaceholderCard

                    researcherOneSheetCard

                    Button {
                        showFitGuide = true
                    } label: {
                        Label("Open Temporalis fit guide", systemImage: "camera.viewfinder")
                            .font(designSystem.typography.labelMedium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(designSystem.colors.primaryBlack)
                            .foregroundColor(designSystem.colors.primaryWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Text("Connect your Oralable REV10 as primary on the Devices tab if you have not already.")
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textTertiary)
                }
                .padding(designSystem.spacing.lg)
            }
            .background(designSystem.colors.backgroundSecondary)
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(isPresented: $showFitGuide) {
            TemporalisFitGuideView(
                onExit: { showFitGuide = false },
                onCalibrationSucceeded: {
                    firstLaunchManager.markFirstFitCompleted()
                }
            )
            .environmentObject(designSystem)
            .environmentObject(deviceManagerAdapter)
            .environmentObject(deviceManager)
            .environmentObject(sessionHistoryStore)
            .environmentObject(sensorDataProcessor)
        }
    }

    private var videoPlaceholderCard: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            HStack(spacing: designSystem.spacing.sm) {
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundColor(designSystem.colors.gray500)
                Text("Temporalis positioning video")
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.textPrimary)
            }
            Text("A narrated clip for mirror placement and temple reticle alignment will appear here for the trial.")
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)
            RoundedRectangle(cornerRadius: designSystem.cornerRadius.card)
                .fill(designSystem.colors.gray200.opacity(0.6))
                .frame(height: 160)
                .overlay {
                    VStack(spacing: designSystem.spacing.xs) {
                        Image(systemName: "film")
                            .font(.system(size: 36))
                            .foregroundColor(designSystem.colors.gray400)
                        Text("Video coming soon")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.textTertiary)
                    }
                }
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(designSystem.colors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: designSystem.spacing.sm, style: .continuous))
    }

    private var researcherOneSheetCard: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            Text("Researcher one-sheet")
                .font(designSystem.typography.headline)
                .foregroundColor(designSystem.colors.textPrimary)

            VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
                bullet("Temporalis fit + 10-minute IR-DC calibration is mandatory per REV10 headset before overnight capture.")
                bullet("Automatic recording runs while connected; hourly memory flush writes CSV to Application Support for data safety.")
                bullet("TFI (Temporalis Fatigue Index) and SASHB (hypoxic burden) roll into the clinical PDF and professional handshake export.")
                bullet("Trial coordination uses the 6-character clinician sync code on the PDF header with Share → Professional.")
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
                .font(designSystem.typography.bodySmall)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
