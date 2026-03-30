//
//  LaunchCoordinator.swift
//  OralableApp
//
//  Coordinates app launch flow based on authentication state.
//
//  Flow Logic:
//  1. If authenticated and pairing + first fit complete → MainTabView
//  2. If authenticated and trial mode (pairing skipped) → TrialSetupDashboardView
//  3. If authenticated otherwise → FirstLaunchOnboardingView
//  4. If first launch (unauthenticated) → OnboardingView
//  5. Otherwise → LoginView
//
//  Gold-standard setup / MainTab transition:
//  CalibrationWizardView runs inside TemporalisFitGuideView. On successful calibration,
//  TemporalisFitGuideView presents SetupSuccessView before any call to markFirstFitCompleted().
//  Only after the user taps “Go to dashboard” does onCalibrationSucceeded run, FirstLaunchManager
//  finalizes setup (trial + provisional flags cleared), and this coordinator reveals MainTabView.
//
//  Purpose:
//  Single point of control for the initial view hierarchy.
//  Responds to authentication state changes reactively.
//
//  Created by John A Cogan on 23/11/2025.
//


import SwiftUI

struct LaunchCoordinator: View {
    @EnvironmentObject var authenticationManager: AuthenticationManager
    @EnvironmentObject var historicalDataManager: HistoricalDataManager
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var sessionHistoryStore: SessionHistoryStore
    @EnvironmentObject var firstLaunchManager: FirstLaunchManager

    var body: some View {
        Group {
            // IMPORTANT: Check authentication BEFORE first launch
            // Once authenticated, show first-fit onboarding until Temporalis calibration completes.
            if authenticationManager.isAuthenticated {
                // Main app unlocks only after SetupSuccessView → “Go to dashboard” → markFirstFitCompleted()
                if firstLaunchManager.hasCompletedFirstFit,
                   firstLaunchManager.hasPairedOralablePrimary {
                    MainTabView()
                        .onAppear {
                            Logger.shared.info("🟢 LaunchCoordinator: Showing MainTabView (authenticated, setup complete)")
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
            if authenticationManager.isAuthenticated,
               firstLaunchManager.hasCompletedFirstFit,
               !firstLaunchManager.hasPairedOralablePrimary {
                firstLaunchManager.markOralablePaired()
            }
            if authenticationManager.isAuthenticated,
               !firstLaunchManager.hasCompletedFirstFit,
               sessionHistoryStore.temporalisSleepCalibration != nil {
                firstLaunchManager.markOralablePaired()
                firstLaunchManager.markFirstFitCompleted()
            }
            // Attempt to auto-reconnect to remembered devices on app launch
            deviceManager.attemptAutoReconnect()
        }
    }
}
