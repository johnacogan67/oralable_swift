//
//  LaunchCoordinator.swift
//  OralableApp
//
//  Coordinates app launch flow based on authentication state.
//
//  Flow Logic:
//  1. If authenticated and paired (Beacon default) → MainTabView
//  2. If authenticated, Protocol A Setup required + complete → MainTabView
//  3. If authenticated, paired, Protocol A required but incomplete → SingleProtocolASetupView
//  4. If authenticated and trial mode (pairing skipped) → TrialSetupDashboardView
//  5. If authenticated otherwise → FirstLaunchOnboardingView
//  6. If first launch (unauthenticated) → OnboardingView
//  7. Otherwise → LoginView
//

import SwiftUI

struct LaunchCoordinator: View {
    @EnvironmentObject var authenticationManager: AuthenticationManager
    @EnvironmentObject var historicalDataManager: HistoricalDataManager
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var sessionHistoryStore: SessionHistoryStore
    @EnvironmentObject var firstLaunchManager: FirstLaunchManager
    @ObservedObject private var featureFlags = FeatureFlags.shared

    var body: some View {
        Group {
            if authenticationManager.isAuthenticated {
                authenticatedRoot
            } else if authenticationManager.isFirstLaunch {
                OnboardingView()
                    .onAppear {
                        Logger.shared.info("🟡 LaunchCoordinator: Showing OnboardingView (first launch)")
                    }
            } else {
                LoginView()
                    .onAppear {
                        Logger.shared.info("🔴 LaunchCoordinator: Showing LoginView (not authenticated)")
                    }
            }
        }
        .onAppear {
            Logger.shared.info("🔵 LaunchCoordinator appeared - isAuthenticated: \(authenticationManager.isAuthenticated), isFirstLaunch: \(authenticationManager.isFirstLaunch)")
            reconcileLegacyGatesOnAppear()
            deviceManager.attemptAutoReconnect()
        }
    }

    @ViewBuilder
    private var authenticatedRoot: some View {
        let paired = firstLaunchManager.hasPairedOralablePrimary
        let requireA = featureFlags.requireProtocolASetup
        let protocolADone = firstLaunchManager.hasCompletedProtocolASetup
        let fitDone = firstLaunchManager.hasCompletedFirstFit

        if requireA {
            if paired, protocolADone {
                MainTabView()
                    .onAppear {
                        Logger.shared.info("🟢 LaunchCoordinator: MainTabView (Protocol A Setup complete)")
                    }
            } else if firstLaunchManager.isTrialSetupMode {
                TrialSetupDashboardView(firstLaunchManager: firstLaunchManager)
                    .onAppear {
                        Logger.shared.info("🟠 LaunchCoordinator: Trial setup dashboard (pairing skipped)")
                    }
            } else if paired, !protocolADone {
                SingleProtocolASetupView(firstLaunchManager: firstLaunchManager)
                    .onAppear {
                        Logger.shared.info("🟡 LaunchCoordinator: SingleProtocolASetupView (Setup Mode)")
                    }
            } else {
                FirstLaunchOnboardingView(firstLaunchManager: firstLaunchManager)
                    .onAppear {
                        Logger.shared.info("🟡 LaunchCoordinator: FirstLaunchOnboardingView (pair)")
                    }
            }
        } else if fitDone, paired {
            MainTabView()
                .onAppear {
                    Logger.shared.info("🟢 LaunchCoordinator: Showing MainTabView (authenticated, setup complete)")
                }
        } else if featureFlags.vitalsPhaseEnabled, paired {
            MainTabView()
                .onAppear {
                    Logger.shared.info("🟢 LaunchCoordinator: MainTabView (vitals phase, paired)")
                }
        } else if firstLaunchManager.isTrialSetupMode {
            TrialSetupDashboardView(firstLaunchManager: firstLaunchManager)
                .onAppear {
                    Logger.shared.info("🟠 LaunchCoordinator: Trial setup dashboard (pairing skipped)")
                }
        } else {
            FirstLaunchOnboardingView(firstLaunchManager: firstLaunchManager)
                .onAppear {
                    Logger.shared.info("🟡 LaunchCoordinator: Showing FirstLaunchOnboardingView (setup)")
                }
        }
    }

    private func reconcileLegacyGatesOnAppear() {
        guard authenticationManager.isAuthenticated else { return }

        // Auto-complete Temporalis fit only when Protocol A Setup gate is off.
        if !featureFlags.requireProtocolASetup,
           featureFlags.vitalsPhaseEnabled,
           firstLaunchManager.hasPairedOralablePrimary,
           !firstLaunchManager.hasCompletedFirstFit {
            firstLaunchManager.markFirstFitCompleted()
        }

        if firstLaunchManager.hasCompletedFirstFit,
           !firstLaunchManager.hasPairedOralablePrimary {
            firstLaunchManager.markOralablePaired()
        }

        // Legacy calibration restore — do not skip Protocol A when that gate is on.
        if !featureFlags.requireProtocolASetup,
           !firstLaunchManager.hasCompletedFirstFit,
           sessionHistoryStore.temporalisSleepCalibration != nil {
            firstLaunchManager.markOralablePaired()
            firstLaunchManager.markFirstFitCompleted()
        }
    }
}
