//
//  FirstLaunchManagerTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

@MainActor
final class FirstLaunchManagerTests: XCTestCase {
    override func tearDown() async throws {
        FirstLaunchManager.clearPersistedState()
        try await super.tearDown()
    }

    func testResetClearsPersistedSetupFlags() {
        let manager = FirstLaunchManager()

        manager.markOralablePaired()
        manager.markFirstFitCompleted()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "oralable.hasCompletedFirstFit"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "oralable.hasPairedOralablePrimary"))

        manager.reset()

        XCTAssertFalse(manager.hasCompletedFirstFit)
        XCTAssertFalse(manager.hasPairedOralablePrimary)
        XCTAssertFalse(manager.isTrialSetupMode)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "oralable.hasCompletedFirstFit"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "oralable.hasPairedOralablePrimary"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "oralable.onboardingTrialSetupMode"))
    }
}
