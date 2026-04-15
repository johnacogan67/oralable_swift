//
//  FirstLaunchOnboardingView.swift
//  OralableApp
//
//  Post-sign-in setup: pair REV10 first, then Temporalis fit + calibration.
//

import SwiftUI

struct FirstLaunchOnboardingView: View {
    @ObservedObject var firstLaunchManager: FirstLaunchManager
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var deviceManagerAdapter: DeviceManagerAdapter
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var sessionHistoryStore: SessionHistoryStore
    @EnvironmentObject var sensorDataProcessor: SensorDataProcessor

    @State private var showDeviceDiscoverySheet = false
    @State private var showFitGuide = false
    /// 0 = pairing, 1 = fitting (mirror guide), 2 = calibrating
    @State private var setupProgressIndex = 0
    @State private var pairingJustCompletedSession = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: designSystem.spacing.lg) {
                    Text("Before your first night")
                        .font(designSystem.typography.h2)
                        .foregroundColor(designSystem.colors.textPrimary)

                    Text("Connect your Oralable REV10, then complete the Temporalis fit and calibration once. This aligns every trial night with the same placement standard.")
                        .font(designSystem.typography.body)
                        .foregroundColor(designSystem.colors.textSecondary)

                    setupProgressIndicator

                    Button {
                        showDeviceDiscoverySheet = true
                    } label: {
                        Label("Connect Oralable Node", systemImage: "link.circle.fill")
                            .font(designSystem.typography.labelMedium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(designSystem.colors.primaryBlack)
                            .foregroundColor(designSystem.colors.primaryWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if firstLaunchManager.hasPairedOralablePrimary, !showFitGuide {
                        Button {
                            showFitGuide = true
                            setupProgressIndex1IfNeeded()
                        } label: {
                            Label("Continue to Temporalis fit guide", systemImage: "camera.viewfinder")
                                .font(designSystem.typography.labelMedium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(designSystem.colors.backgroundPrimary)
                                .foregroundColor(designSystem.colors.primaryBlack)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(designSystem.colors.border.opacity(0.5), lineWidth: 1)
                                )
                        }
                    }

                    videoPlaceholderCard
                    researcherOneSheetCard
                }
                .padding(designSystem.spacing.lg)
            }
            .background(designSystem.colors.backgroundSecondary)
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                syncProgressIndexFromState()
                applyExistingCalibrationGateIfNeeded()
            }
            .onChange(of: firstLaunchManager.hasPairedOralablePrimary) { _, paired in
                syncProgressIndexFromState()
            }
            .onChange(of: sessionHistoryStore.temporalisSleepCalibration?.calibrationId) { _, _ in
                applyExistingCalibrationGateIfNeeded()
            }
            .onChange(of: deviceManager.deviceReadiness) { _, _ in
                guard firstLaunchManager.hasPairedOralablePrimary else { return }
                guard !firstLaunchManager.hasCompletedFirstFit else { return }
                guard !showFitGuide else { return }
                guard !showDeviceDiscoverySheet else { return }
                guard case .ready = deviceManager.primaryDeviceReadiness else { return }

                setupProgressIndex1IfNeeded()
                showFitGuide = true
            }
        }
        .sheet(isPresented: $showDeviceDiscoverySheet, onDismiss: {
            if !pairingJustCompletedSession,
               !firstLaunchManager.hasPairedOralablePrimary {
                firstLaunchManager.enterTrialSetupMode()
            }
            pairingJustCompletedSession = false

            // Check if we should advance to the fit guide now that the sheet is safely dismissed
            if firstLaunchManager.hasPairedOralablePrimary,
               !firstLaunchManager.hasCompletedFirstFit,
               !showFitGuide,
               case .ready = deviceManager.primaryDeviceReadiness {

                setupProgressIndex1IfNeeded()
                showFitGuide = true
            }
        }) {
            DeviceDiscoveryView(
                onOralablePrimaryReady: {
                    pairingJustCompletedSession = true
                    firstLaunchManager.markOralablePaired()
                    showDeviceDiscoverySheet = false
                }
            )
            .environmentObject(deviceManager)
            .environmentObject(designSystem)
        }
        .fullScreenCover(isPresented: $showFitGuide) {
            TemporalisFitGuideView(
                onExit: {
                    showFitGuide = false
                    syncProgressIndexFromState()
                },
                onCalibrationSucceeded: {
                    firstLaunchManager.markFirstFitCompleted()
                },
                onBeginCalibration: {
                    setupProgressIndex = 2
                }
            )
            .environmentObject(designSystem)
            .environmentObject(deviceManagerAdapter)
            .environmentObject(deviceManager)
            .environmentObject(sessionHistoryStore)
            .environmentObject(sensorDataProcessor)
            .environmentObject(firstLaunchManager)
        }
    }

    private var setupProgressIndicator: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            Text("Setup progress")
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.textTertiary)
            HStack(alignment: .top, spacing: 0) {
                progressSegment(title: "Pairing", step: 0)
                progressChevron
                progressSegment(title: "Fitting", step: 1)
                progressChevron
                progressSegment(title: "Calibrating", step: 2)
            }
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(designSystem.colors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: designSystem.spacing.sm, style: .continuous))
    }

    private var progressChevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundColor(designSystem.colors.textTertiary)
            .padding(.top, 4)
    }

    private func progressSegment(title: String, step: Int) -> some View {
        let active = setupProgressIndex == step
        let done = setupProgressIndex > step
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? designSystem.colors.primaryBlack : designSystem.colors.gray200)
                    .frame(width: 26, height: 26)
                if done {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(designSystem.colors.primaryWhite)
                } else if active {
                    Circle()
                        .strokeBorder(designSystem.colors.primaryBlack, lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            Text(title)
                .font(designSystem.typography.captionSmall)
                .foregroundColor(active || done ? designSystem.colors.textPrimary : designSystem.colors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func setupProgressIndex1IfNeeded() {
        if setupProgressIndex < 1 {
            setupProgressIndex = 1
        }
    }

    private func syncProgressIndexFromState() {
        if firstLaunchManager.hasCompletedFirstFit {
            setupProgressIndex = 2
            return
        }
        if setupProgressIndex >= 2, !firstLaunchManager.hasCompletedFirstFit {
            return
        }
        if firstLaunchManager.hasPairedOralablePrimary {
            if setupProgressIndex == 0 {
                setupProgressIndex = 1
            }
        } else {
            setupProgressIndex = 0
        }
    }

    private func applyExistingCalibrationGateIfNeeded() {
        guard !firstLaunchManager.hasCompletedFirstFit else { return }
        guard let _ = sessionHistoryStore.temporalisSleepCalibration else { return }
        firstLaunchManager.markOralablePaired()
        firstLaunchManager.markFirstFitCompleted()
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
                bullet("Temporalis fit + quick IR-DC calibration (about 90 seconds) is required once per REV10 headset before overnight capture.")
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
