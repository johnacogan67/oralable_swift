//
//  WornPlacementBatteryGateTests.swift
//  OralableAppTests
//
//  Worn temple mode at low/unknown battery drops Gen1 BLE within seconds.
//  Connect must fail closed until a fresh gauge is available.
//

import XCTest
@testable import OralableApp

final class WornPlacementBatteryGateTests: XCTestCase {

    func testWornAllowedWhenBatteryAtOrAboveMinimum() {
        let mode = DeviceManager.wornPlacementModeAfterBatteryGate(
            requested: .worn,
            batteryPercent: DeviceManager.wornPlacementMinimumBatteryPercent,
            vitalsPhaseEnabled: true
        )
        XCTAssertEqual(mode, .worn)
    }

    func testWornBlockedWhenBatteryBelowMinimum() {
        let mode = DeviceManager.wornPlacementModeAfterBatteryGate(
            requested: .worn,
            batteryPercent: DeviceManager.wornPlacementMinimumBatteryPercent - 1,
            vitalsPhaseEnabled: true
        )
        XCTAssertEqual(mode, .offDockIdle)
    }

    func testWornBlockedWhenBatteryUnknown() {
        let mode = DeviceManager.wornPlacementModeAfterBatteryGate(
            requested: .worn,
            batteryPercent: nil,
            vitalsPhaseEnabled: true
        )
        XCTAssertEqual(mode, .offDockIdle, "Cold connect must not apply worn before a gauge arrives")
    }

    func testNonWornModesUnchangedWhenBatteryUnknown() {
        for requested: FeatureFlags.DevicePlacementMode in [.auto, .onCharger, .offDockIdle] {
            let mode = DeviceManager.wornPlacementModeAfterBatteryGate(
                requested: requested,
                batteryPercent: nil,
                vitalsPhaseEnabled: true
            )
            XCTAssertEqual(mode, requested)
        }
    }

    func testGateDisabledOutsideVitalsPhase() {
        let mode = DeviceManager.wornPlacementModeAfterBatteryGate(
            requested: .worn,
            batteryPercent: nil,
            vitalsPhaseEnabled: false
        )
        XCTAssertEqual(mode, .worn)
    }
}
