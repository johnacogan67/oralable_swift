//
//  FirstLaunchManager.swift
//  OralableApp
//
//  First-run gate: pair → (optional) Protocol A Setup → General Mode (MainTab).
//

import Combine
import Foundation

@MainActor
final class FirstLaunchManager: ObservableObject {

    private static let fitKey = "oralable.hasCompletedFirstFit"
    private static let pairedKey = "oralable.hasPairedOralablePrimary"
    private static let trialKey = "oralable.onboardingTrialSetupMode"
    private static let protocolASetupKey = "oralable.hasCompletedProtocolASetup"

    @Published private(set) var hasCompletedFirstFit: Bool
    @Published private(set) var hasPairedOralablePrimary: Bool
    @Published private(set) var isTrialSetupMode: Bool
    @Published private(set) var hasCompletedProtocolASetup: Bool

    init() {
        let defaults = UserDefaults.standard
        hasCompletedFirstFit = defaults.bool(forKey: Self.fitKey)
        hasPairedOralablePrimary = defaults.bool(forKey: Self.pairedKey)
        isTrialSetupMode = defaults.bool(forKey: Self.trialKey)
        hasCompletedProtocolASetup = defaults.bool(forKey: Self.protocolASetupKey)
    }

    /// REV10 / Oralable primary reached full BLE readiness during onboarding.
    func markOralablePaired() {
        UserDefaults.standard.set(true, forKey: Self.pairedKey)
        hasPairedOralablePrimary = true
        UserDefaults.standard.set(false, forKey: Self.trialKey)
        isTrialSetupMode = false
        Logger.shared.info("[FirstLaunchManager] Oralable primary paired (onboarding)")
        // Vitals-only unlock to MainTab when Protocol A Setup gate is off.
        if FeatureFlags.shared.vitalsPhaseEnabled,
           !FeatureFlags.shared.requireProtocolASetup {
            markFirstFitCompleted()
            Logger.shared.info("[FirstLaunchManager] Vitals phase — skipped Temporalis fit/calibration gate")
        }
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

    /// Single-MAM Protocol A Setup finished (IR preflight + 360 s + export). Unlocks General Mode.
    func markProtocolASetupCompleted() {
        UserDefaults.standard.set(true, forKey: Self.protocolASetupKey)
        hasCompletedProtocolASetup = true
        markFirstFitCompleted()
        Logger.shared.info("[FirstLaunchManager] Protocol A Setup completed — General Mode eligible")
    }

    /// Desk / test reset of Protocol A gate only (does not unpair).
    func resetProtocolASetupForTesting() {
        UserDefaults.standard.set(false, forKey: Self.protocolASetupKey)
        hasCompletedProtocolASetup = false
        Logger.shared.info("[FirstLaunchManager] Protocol A Setup flag cleared")
    }
}
