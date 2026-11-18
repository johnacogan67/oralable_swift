//
//  BatteryStatusGaugeTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

final class BatteryStatusGaugeTests: XCTestCase {

    func testZeroStatusKeepsPreviousGauge() {
        XCTAssertEqual(OralableBatteryGauge.level(afterStatusPercent: 0, previous: 73), 73)
        XCTAssertFalse(OralableBatteryGauge.shouldPublishStatusReading(0))
    }

    func testZeroStatusWithNoPreviousStaysUnset() {
        XCTAssertNil(OralableBatteryGauge.level(afterStatusPercent: 0, previous: nil))
    }

    func testPositiveStatusReplacesGaugeAndPublishes() {
        XCTAssertEqual(OralableBatteryGauge.level(afterStatusPercent: 40, previous: 80), 40)
        XCTAssertTrue(OralableBatteryGauge.shouldPublishStatusReading(40))
    }

    func testExplicitEmptyGaugeStaysEmpty() {
        XCTAssertEqual(OralableBatteryGauge.level(afterStatusPercent: 0, previous: 0), 0)
    }
}
