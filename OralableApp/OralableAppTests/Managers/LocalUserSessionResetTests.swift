//
//  LocalUserSessionResetTests.swift
//  OralableAppTests
//
//  Regression coverage for user-scoped local setup state.
//

import XCTest
@testable import OralableApp

@MainActor
final class LocalUserSessionResetTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearLocalUserSessionDefaults()
    }

    override func tearDown() {
        clearLocalUserSessionDefaults()
        super.tearDown()
    }

    func testAuthenticationSignOutClearsSetupCalibrationAndRememberedDevices() {
        seedUserScopedLocalState()

        let authManager = AuthenticationManager()
        authManager.userID = "user-a"
        authManager.userEmail = "user-a@example.com"
        authManager.userFullName = "User A"
        authManager.isAuthenticated = true

        authManager.signOut()

        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNil(authManager.userID)
        XCTAssertNil(authManager.userEmail)
        XCTAssertNil(authManager.userFullName)
        XCTAssertFalse(FirstLaunchManager().hasPairedOralablePrimary)
        XCTAssertFalse(FirstLaunchManager().hasCompletedFirstFit)
        XCTAssertNil(SessionHistoryStore().temporalisSleepCalibration)
        XCTAssertTrue(DevicePersistenceManager.shared.getRememberedDevices().isEmpty)
    }

    func testDeleteAccountClearsSetupCalibrationAndRememberedDevices() async {
        seedUserScopedLocalState()

        let authManager = AuthenticationManager()
        authManager.userID = "user-a"
        authManager.userEmail = "user-a@example.com"
        authManager.userFullName = "User A"
        authManager.isAuthenticated = true

        await authManager.deleteAccount()

        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNil(authManager.userID)
        XCTAssertNil(authManager.userEmail)
        XCTAssertNil(authManager.userFullName)
        XCTAssertFalse(FirstLaunchManager().hasPairedOralablePrimary)
        XCTAssertFalse(FirstLaunchManager().hasCompletedFirstFit)
        XCTAssertNil(SessionHistoryStore().temporalisSleepCalibration)
        XCTAssertTrue(DevicePersistenceManager.shared.getRememberedDevices().isEmpty)
    }

    private func seedUserScopedLocalState() {
        let firstLaunchManager = FirstLaunchManager()
        firstLaunchManager.markOralablePaired()
        firstLaunchManager.markFirstFitCompleted()

        let sessionHistoryStore = SessionHistoryStore()
        sessionHistoryStore.recordTemporalisSleepCalibration(
            calibrationId: UUID(),
            baselineVoltage: 1.23,
            peripheralId: UUID(),
            rawCalibrationCSVFileName: "temporalis_calibration_user_a.csv"
        )

        DevicePersistenceManager.shared.rememberDevice(id: UUID().uuidString, name: "Oralable REV10")

        XCTAssertTrue(FirstLaunchManager().hasPairedOralablePrimary)
        XCTAssertTrue(FirstLaunchManager().hasCompletedFirstFit)
        XCTAssertNotNil(SessionHistoryStore().temporalisSleepCalibration)
        XCTAssertFalse(DevicePersistenceManager.shared.getRememberedDevices().isEmpty)
    }

    private func clearLocalUserSessionDefaults() {
        FirstLaunchManager.clearPersistedState()
        SessionHistoryStore.clearPersistedTemporalisSleepCalibration(deleteRawCalibrationFiles: true)
        DevicePersistenceManager.shared.forgetAllDevices()
        UserDefaults.standard.removeObject(forKey: "isAuthenticated")
        UserDefaults.standard.removeObject(forKey: "userID")
        UserDefaults.standard.removeObject(forKey: "userFullName")
        UserDefaults.standard.removeObject(forKey: "userGivenName")
        UserDefaults.standard.removeObject(forKey: "userFamilyName")
        UserDefaults.standard.removeObject(forKey: "userEmail")
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
    }
}
