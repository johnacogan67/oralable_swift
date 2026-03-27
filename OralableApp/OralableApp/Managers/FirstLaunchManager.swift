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

    private static let defaultsKey = "oralable.hasCompletedFirstFit"

    @Published private(set) var hasCompletedFirstFit: Bool

    init() {
        hasCompletedFirstFit = UserDefaults.standard.bool(forKey: Self.defaultsKey)
    }

    func markFirstFitCompleted() {
        UserDefaults.standard.set(true, forKey: Self.defaultsKey)
        hasCompletedFirstFit = true
        Logger.shared.info("[FirstLaunchManager] First Temporalis fit gate completed")
    }
}
