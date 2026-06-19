//
//  FirstLaunchManagerTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

@MainActor
final class FirstLaunchManagerTests: XCTestCase {
    private let fitKey = "oralable.hasCompletedFirstFit"
    private let pairedKey = "oralable.hasPairedOralablePrimary"
    private let trialKey = "oralable.onboardingTrialSetupMode"

    override func setUp() async throws {
        try await super.setUp()
        clearFirstLaunchDefaults()
    }

    override func tearDown() async throws {
        clearFirstLaunchDefaults()
        try await super.tearDown()
    }

    func testMarkOralablePairedIfReadyPersistsPairingAndClearsTrialMode() {
        let manager = FirstLaunchManager()
        manager.enterTrialSetupMode()

        let didMark = manager.markOralablePairedIfReady(
            primaryDevice: makeDevice(type: .oralable),
            readiness: .ready
        )

        XCTAssertTrue(didMark)
        XCTAssertTrue(manager.hasPairedOralablePrimary)
        XCTAssertFalse(manager.isTrialSetupMode)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: pairedKey))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: trialKey))
    }

    func testMarkOralablePairedIfReadyIgnoresNonReadyOrNonOralableDevices() {
        let manager = FirstLaunchManager()

        XCTAssertFalse(manager.markOralablePairedIfReady(
            primaryDevice: makeDevice(type: .oralable),
            readiness: .enablingNotifications
        ))
        XCTAssertFalse(manager.markOralablePairedIfReady(
            primaryDevice: makeDevice(type: .demo),
            readiness: .ready
        ))

        XCTAssertFalse(manager.hasPairedOralablePrimary)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: pairedKey))
    }

    func testOralablePairingInProgressRecognizesConnectingThroughReadyStates() {
        let oralable = makeDevice(type: .oralable)
        let activeStates: [ConnectionReadiness] = [
            .connecting,
            .connected,
            .discoveringServices,
            .servicesDiscovered,
            .discoveringCharacteristics,
            .characteristicsDiscovered,
            .enablingNotifications,
            .ready
        ]

        for readiness in activeStates {
            XCTAssertTrue(
                FirstLaunchManager.isOralablePairingInProgressOrReady(
                    primaryDevice: oralable,
                    readiness: readiness
                ),
                "\(readiness.displayText) should suppress trial fallback while pairing is active"
            )
        }
    }

    func testOralablePairingInProgressIgnoresDisconnectedFailedAndNonOralableDevices() {
        let oralable = makeDevice(type: .oralable)
        let demo = makeDevice(type: .demo)

        XCTAssertFalse(FirstLaunchManager.isOralablePairingInProgressOrReady(
            primaryDevice: oralable,
            readiness: .disconnected
        ))
        XCTAssertFalse(FirstLaunchManager.isOralablePairingInProgressOrReady(
            primaryDevice: oralable,
            readiness: .failed("timeout")
        ))
        XCTAssertFalse(FirstLaunchManager.isOralablePairingInProgressOrReady(
            primaryDevice: demo,
            readiness: .ready
        ))
    }

    private func clearFirstLaunchDefaults() {
        UserDefaults.standard.removeObject(forKey: fitKey)
        UserDefaults.standard.removeObject(forKey: pairedKey)
        UserDefaults.standard.removeObject(forKey: trialKey)
    }

    private func makeDevice(type: DeviceType) -> DeviceInfo {
        DeviceInfo(
            type: type,
            name: "Test \(type.displayName)",
            peripheralIdentifier: UUID(),
            connectionState: .connected
        )
    }
}
