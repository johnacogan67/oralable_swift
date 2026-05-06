//
//  OralableAppTests.swift
//  OralableAppTests
//
//  Created by John A Cogan on 15/09/2025.
//

import Testing
import Foundation
@testable import OralableApp

struct OralableAppTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @MainActor
    @Test func guestAuthenticationPersistsAcrossManagerReload() async throws {
        let keys = [
            "isAuthenticated",
            "userID",
            "userFullName",
            "userGivenName",
            "userFamilyName",
            "userEmail"
        ]
        let snapshot = snapshotDefaults(for: keys)
        defer { restoreDefaults(snapshot) }

        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }

        let manager = AuthenticationManager()
        manager.continueAsGuest()

        let reloadedManager = AuthenticationManager()
        #expect(reloadedManager.isAuthenticated)
        #expect(reloadedManager.userID == "guest")
        #expect(reloadedManager.userFullName == "Guest")
    }

    @MainActor
    @Test func accountDeletionClearsPersistedSetupAndClinicalState() async throws {
        let keys = [
            "isAuthenticated",
            "userID",
            "userFullName",
            "hasCompletedOnboarding",
            "hasAcceptedPrivacyPolicy",
            "hasAcceptedTerms",
            "oralable.hasCompletedFirstFit",
            "oralable.hasPairedOralablePrimary",
            "oralable.onboardingTrialSetupMode",
            "oralable.temporalis_sleep_calibration",
            "rememberedOralableDevices",
            "OralableClinical.ageYears",
            "notificationsEnabled",
            "feature.dashboard.showSpO2",
            "subscriptionTier"
        ]
        let snapshot = snapshotDefaults(for: keys)
        defer { restoreDefaults(snapshot) }

        UserDefaults.standard.set(true, forKey: "isAuthenticated")
        UserDefaults.standard.set("old-user", forKey: "userID")
        UserDefaults.standard.set("Old User", forKey: "userFullName")
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(true, forKey: "hasAcceptedPrivacyPolicy")
        UserDefaults.standard.set(true, forKey: "hasAcceptedTerms")
        UserDefaults.standard.set(true, forKey: "oralable.hasCompletedFirstFit")
        UserDefaults.standard.set(true, forKey: "oralable.hasPairedOralablePrimary")
        UserDefaults.standard.set(true, forKey: "oralable.onboardingTrialSetupMode")
        UserDefaults.standard.set(Data([0x7b, 0x7d]), forKey: "oralable.temporalis_sleep_calibration")
        UserDefaults.standard.set(Data([0x5b, 0x5d]), forKey: "rememberedOralableDevices")
        UserDefaults.standard.set(42, forKey: "OralableClinical.ageYears")
        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        UserDefaults.standard.set(true, forKey: "feature.dashboard.showSpO2")
        UserDefaults.standard.set("premium", forKey: "subscriptionTier")

        let manager = AuthenticationManager()
        await manager.deleteAccount()

        for key in keys {
            #expect(UserDefaults.standard.object(forKey: key) == nil)
        }
        #expect(!manager.isAuthenticated)
        #expect(manager.userID == nil)
        #expect(manager.userFullName == nil)
    }

    private func snapshotDefaults(for keys: [String]) -> [String: Any?] {
        let defaults = UserDefaults.standard
        return Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
    }

    private func restoreDefaults(_ snapshot: [String: Any?]) {
        let defaults = UserDefaults.standard
        for (key, value) in snapshot {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

}
