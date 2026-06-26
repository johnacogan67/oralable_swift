//
//  FirstLaunchOralableReadinessTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

final class FirstLaunchOralableReadinessTests: XCTestCase {

    func testReadyOralablePrimaryIsRecognized() {
        let device = DeviceInfo(
            type: .oralable,
            name: "Oralable REV10",
            peripheralIdentifier: UUID(),
            connectionState: .connected
        )

        XCTAssertTrue(
            FirstLaunchOralableReadiness.isReadyOralablePrimary(
                device,
                readiness: .ready
            )
        )
    }

    func testNonReadyOrNonOralablePrimaryIsRejected() {
        let oralable = DeviceInfo(
            type: .oralable,
            name: "Oralable REV10",
            peripheralIdentifier: UUID(),
            connectionState: .connected
        )
        let anr = DeviceInfo(
            type: .anr,
            name: "ANR MuscleSense",
            peripheralIdentifier: UUID(),
            connectionState: .connected
        )

        XCTAssertFalse(
            FirstLaunchOralableReadiness.isReadyOralablePrimary(
                oralable,
                readiness: .enablingNotifications
            )
        )
        XCTAssertFalse(
            FirstLaunchOralableReadiness.isReadyOralablePrimary(
                anr,
                readiness: .ready
            )
        )
        XCTAssertFalse(
            FirstLaunchOralableReadiness.isReadyOralablePrimary(
                nil,
                readiness: .ready
            )
        )
    }
}
