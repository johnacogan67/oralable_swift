//
//  OralableTemperatureNotificationTests.swift
//  OralableAppTests
//
//  Temperature CCC is optional telemetry and must not be part of readiness.
//

import XCTest
@testable import OralableApp

final class OralableTemperatureNotificationTests: XCTestCase {

    func testTemperatureIsNotRequiredForConnectionReadiness() {
        let required = OralableDevice.NotificationReadiness.allRequired
        XCTAssertFalse(
            required.contains(.temperature),
            "Temperature must remain optional so CCC failure cannot block streaming readiness"
        )
        XCTAssertTrue(required.contains(.ppgData))
        XCTAssertTrue(required.contains(.accelerometer))
        XCTAssertTrue(required.contains(.status))
        XCTAssertTrue(required.contains(.battery))
    }
}
