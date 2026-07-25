//
//  FeatureFlagsPlacementPersistenceTests.swift
//  OralableAppTests
//
//  Placement mode must survive process relaunch so overnight vitals reconnects
//  re-apply Worn / Off-charger instead of silently falling back to the default.
//

import XCTest
@testable import OralableApp

final class FeatureFlagsPlacementPersistenceTests: XCTestCase {

    private let placementKey = "feature.device.placementMode"
    private let rebootKey = "feature.pilot.debugRebootIntervalMinutes"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: placementKey)
        UserDefaults.standard.removeObject(forKey: rebootKey)
        super.tearDown()
    }

    func testUserDefaultsUInt8CastCannotRoundTripPlacementRawValue() {
        // Documents the underlying Foundation bridging bug this fix avoids.
        UserDefaults.standard.set(Int(FeatureFlags.DevicePlacementMode.worn.rawValue), forKey: placementKey)
        XCTAssertNil(
            UserDefaults.standard.object(forKey: placementKey) as? UInt8,
            "NSNumber-backed UserDefaults values do not cast to UInt8"
        )
        XCTAssertEqual(UserDefaults.standard.integer(forKey: placementKey), 3)
    }

    func testPlacementModePersistsAcrossFeatureFlagsRelaunch() {
        UserDefaults.standard.removeObject(forKey: placementKey)

        let writer = FeatureFlags()
        writer.devicePlacementMode = .worn
        XCTAssertEqual(UserDefaults.standard.integer(forKey: placementKey), 3)

        let reader = FeatureFlags()
        XCTAssertEqual(
            reader.devicePlacementMode,
            .worn,
            "Worn placement must reload after process relaunch so connect applies streaming mode"
        )
    }

    func testLoadUIntUsesIntegerForKeyNotUIntCast() {
        UserDefaults.standard.set(Int(FeatureFlags.DevicePlacementMode.onCharger.rawValue), forKey: placementKey)
        let loaded: UInt8 = FeatureFlags.loadUInt(
            forKey: placementKey,
            default: FeatureFlags.DevicePlacementMode.offDockIdle.rawValue,
            from: .standard
        )
        XCTAssertEqual(loaded, FeatureFlags.DevicePlacementMode.onCharger.rawValue)
    }

    func testMissingPlacementKeyFallsBackToDefault() {
        UserDefaults.standard.removeObject(forKey: placementKey)
        let loaded: UInt8 = FeatureFlags.loadUInt(
            forKey: placementKey,
            default: FeatureFlags.DevicePlacementMode.offDockIdle.rawValue,
            from: .standard
        )
        XCTAssertEqual(loaded, FeatureFlags.DevicePlacementMode.offDockIdle.rawValue)
    }
}
