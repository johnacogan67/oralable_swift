//
//  FirstLaunchManager.swift
//  OralableApp
//
//  First-run gate: Temporalis fit + calibration before Home (trial subjects).
//

import Combine
import Foundation

@MainActor
final class FirstLaunchManager: ObservableObject {

    private static let fitKey = "oralable.hasCompletedFirstFit"
    private static let pairedKey = "oralable.hasPairedOralablePrimary"
    private static let trialKey = "oralable.onboardingTrialSetupMode"

    @Published private(set) var hasCompletedFirstFit: Bool
    @Published private(set) var hasPairedOralablePrimary: Bool
    @Published private(set) var isTrialSetupMode: Bool

    init() {
        let defaults = UserDefaults.standard
        hasCompletedFirstFit = defaults.bool(forKey: Self.fitKey)
        hasPairedOralablePrimary = defaults.bool(forKey: Self.pairedKey)
        isTrialSetupMode = defaults.bool(forKey: Self.trialKey)
    }

    /// REV10 / Oralable primary reached full BLE readiness during onboarding.
    func markOralablePaired() {
        UserDefaults.standard.set(true, forKey: Self.pairedKey)
        hasPairedOralablePrimary = true
        UserDefaults.standard.set(false, forKey: Self.trialKey)
        isTrialSetupMode = false
        Logger.shared.info("[FirstLaunchManager] Oralable primary paired (onboarding)")
    }

    /// User closed pairing without connecting; limited trial dashboard.
    func enterTrialSetupMode() {
        UserDefaults.standard.set(true, forKey: Self.trialKey)
        isTrialSetupMode = true
        Logger.shared.info("[FirstLaunchManager] Trial setup mode (no device)")
    }

    func exitTrialSetupMode() {
        UserDefaults.standard.set(false, forKey: Self.trialKey)
        isTrialSetupMode = false
    }

    /// Call from `SetupSuccessView` after calibration succeeds (not directly from the wizard).
    /// Clears trial / provisional onboarding so `LaunchCoordinator` can show `MainTabView`.
    func markFirstFitCompleted() {
        UserDefaults.standard.set(true, forKey: Self.fitKey)
        hasCompletedFirstFit = true
        exitTrialSetupMode()
        Logger.shared.info("[FirstLaunchManager] First Temporalis fit gate completed (setup finalized, MainTab eligible)")
    }
}
