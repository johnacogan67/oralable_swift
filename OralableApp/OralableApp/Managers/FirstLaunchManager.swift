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

    static func isReadyOralablePrimary(primaryDevice: DeviceInfo?, readiness: ConnectionReadiness) -> Bool {
        guard readiness == .ready,
              primaryDevice?.type == .oralable else {
            return false
        }
        return true
    }

    static func isOralablePairingInProgressOrReady(primaryDevice: DeviceInfo?, readiness: ConnectionReadiness) -> Bool {
        guard primaryDevice?.type == .oralable else { return false }

        switch readiness {
        case .connecting, .connected, .discoveringServices, .servicesDiscovered,
             .discoveringCharacteristics, .characteristicsDiscovered,
             .enablingNotifications, .ready:
            return true
        case .disconnected, .failed(_):
            return false
        }
    }

    /// REV10 / Oralable primary reached full BLE readiness during onboarding.
    func markOralablePaired() {
        UserDefaults.standard.set(true, forKey: Self.pairedKey)
        hasPairedOralablePrimary = true
        UserDefaults.standard.set(false, forKey: Self.trialKey)
        isTrialSetupMode = false
        Logger.shared.info("[FirstLaunchManager] Oralable primary paired (onboarding)")
    }

    @discardableResult
    func markOralablePairedIfReady(primaryDevice: DeviceInfo?, readiness: ConnectionReadiness) -> Bool {
        guard Self.isReadyOralablePrimary(primaryDevice: primaryDevice, readiness: readiness) else {
            return false
        }
        if !hasPairedOralablePrimary {
            markOralablePaired()
        }
        return true
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
