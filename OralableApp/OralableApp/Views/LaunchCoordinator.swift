//
//  LaunchCoordinator.swift
//  OralableApp
//
//  Coordinates app launch flow based on authentication state.
//
//  Flow Logic:
//  1. If authenticated → Show MainTabView
//  2. If first launch → Show OnboardingView
//  3. Otherwise → Show LoginView
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
                if firstLaunchManager.hasCompletedFirstFit {
                    MainTabView()
                        .onAppear {
                            Logger.shared.info("🟢 LaunchCoordinator: Showing MainTabView (authenticated)")
                        }
                } else {
                    FirstLaunchOnboardingView(firstLaunchManager: firstLaunchManager)
                        .onAppear {
                            Logger.shared.info("🟡 LaunchCoordinator: Showing FirstLaunchOnboardingView (fit gate)")
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
               !firstLaunchManager.hasCompletedFirstFit,
               sessionHistoryStore.temporalisSleepCalibration != nil {
                firstLaunchManager.markFirstFitCompleted()
            }
            // Attempt to auto-reconnect to remembered devices on app launch
            deviceManager.attemptAutoReconnect()
        }
    }
}
