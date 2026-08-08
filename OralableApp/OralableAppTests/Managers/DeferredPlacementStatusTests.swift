//
//  DeferredPlacementStatusTests.swift
//  OralableAppTests
//
//  Deferred Settings placement must not drive vitals "On body" while firmware is still off-body.
//

import XCTest
@testable import OralableApp
import OralableCore

final class DeferredPlacementStatusTests: XCTestCase {

    func testStatusPlacementUsesAppliedModeWhileConnected() {
        let resolved = DeviceManager.resolveStatusPlacementMode(
            isConnected: true,
            applied: .offDockIdle,
            preferred: .worn
        )
        XCTAssertEqual(resolved, .offDockIdle)
    }

    func testStatusPlacementFallsBackToPreferredWhenDisconnected() {
        let resolved = DeviceManager.resolveStatusPlacementMode(
            isConnected: false,
            applied: .offDockIdle,
            preferred: .worn
        )
        XCTAssertEqual(resolved, .worn)
    }

    func testStatusPlacementFallsBackToPreferredWhenAppliedUnknown() {
        let resolved = DeviceManager.resolveStatusPlacementMode(
            isConnected: true,
            applied: nil,
            preferred: .onCharger
        )
        XCTAssertEqual(resolved, .onCharger)
    }

    /// Documents the Core trap: preferred Worn alone makes operationalState `.onBody`
    /// even when firmware reports not worn — dashboard must pass applied mode instead.
    func testPreferredWornOverridesFirmwareNotWornInOperationalState() {
        let status = TGMDeviceStatus(
            onDock: false,
            chargeActive: false,
            worn: false,
            deviceState: 0,
            batteryPercent: 80
        )
        XCTAssertEqual(
            status.operationalState(userPlacementMode: FeatureFlags.DevicePlacementMode.worn.rawValue),
            .onBody,
            "Core treats preferred Worn as on-body; callers must not pass deferred preference"
        )
        XCTAssertEqual(
            status.operationalState(userPlacementMode: FeatureFlags.DevicePlacementMode.offDockIdle.rawValue),
            .benchIdle,
            "Applied Off charger + not worn stays bench/idle"
        )
    }
}
