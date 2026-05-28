//
//  SessionHistoryStoreTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp
import OralableCore

@MainActor
final class SessionHistoryStoreTests: XCTestCase {

    func testSleepCalibrationSurvivesTemporaryANRPrimary() {
        let store = SessionHistoryStore()
        store.clearTemporalisSleepCalibration()

        let oralableId = UUID()
        let anrId = UUID()
        store.recordTemporalisSleepCalibration(
            calibrationId: UUID(),
            baselineVoltage: 1.23,
            peripheralId: oralableId
        )

        store.applyPrimaryDeviceForSleepGate(primaryPeripheralId: anrId, primaryDeviceType: .anr)

        XCTAssertEqual(store.temporalisSleepCalibration?.peripheralId, oralableId)

        store.applyPrimaryDeviceForSleepGate(primaryPeripheralId: anrId, primaryDeviceType: .oralable)

        XCTAssertNil(store.temporalisSleepCalibration)
        store.clearTemporalisSleepCalibration()
    }
}
