//
//  StaleConnectionRecoveryReconnectTests.swift
//  OralableAppTests
//
//  Regression: recoverStaleConnection uses cancelPeripheralConnection, which delivers
//  didDisconnect with error == nil. That path must still auto-reconnect.
//

import XCTest
import CoreBluetooth
@testable import OralableApp

@MainActor
final class StaleConnectionRecoveryReconnectTests: XCTestCase {

    var sut: BLEBackgroundWorker!
    var mockBLEService: MockBLEService!

    override func setUp() async throws {
        try await super.setUp()
        mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let testConfig = BLEBackgroundWorkerConfig(
            maxReconnectionAttempts: 3,
            baseReconnectionDelay: 0.05,
            maxReconnectionDelay: 0.2,
            jitterFactor: 0.0,
            connectionTimeout: 0.5,
            autoReconnectEnabled: true
        )
        sut = BLEBackgroundWorker(bleService: mockBLEService, config: testConfig)
        sut.configure(bleService: mockBLEService)
        sut.start()
    }

    override func tearDown() async throws {
        sut.stop()
        sut = nil
        mockBLEService = nil
        try await super.tearDown()
    }

    func testStaleRecoveryNilErrorDisconnectSchedulesReconnect() async {
        let deviceId = UUID()
        mockBLEService.addDiscoverableDevice(id: deviceId, name: "Oralable")
        let peripheral = mockBLEService.discoveredPeripherals[deviceId]!

        sut.markStaleRecoveryReconnectForTesting(deviceId)
        sut.handleDisconnection(
            for: deviceId,
            peripheral: peripheral,
            wasUnexpected: false,
            error: nil
        )

        XCTAssertTrue(
            sut.activeReconnections.contains(deviceId) || sut.hasActiveOrPendingReconnection,
            "Stale recovery cancel (nil disconnect error) must schedule auto-reconnect"
        )
    }

    func testIntentionalDisconnectWithoutStaleMarkerDoesNotReconnect() async {
        let deviceId = UUID()
        mockBLEService.addDiscoverableDevice(id: deviceId, name: "Oralable")
        let peripheral = mockBLEService.discoveredPeripherals[deviceId]!

        sut.handleDisconnection(
            for: deviceId,
            peripheral: peripheral,
            wasUnexpected: false,
            error: nil
        )

        XCTAssertFalse(sut.activeReconnections.contains(deviceId))
        XCTAssertFalse(sut.hasActiveOrPendingReconnection)
    }

    func testUnexpectedDisconnectStillReconnects() async {
        let deviceId = UUID()
        mockBLEService.addDiscoverableDevice(id: deviceId, name: "Oralable")
        let peripheral = mockBLEService.discoveredPeripherals[deviceId]!

        sut.handleDisconnection(
            for: deviceId,
            peripheral: peripheral,
            wasUnexpected: true,
            error: BLEError.unexpectedDisconnection(peripheralId: deviceId, reason: "link loss")
        )

        XCTAssertTrue(
            sut.activeReconnections.contains(deviceId) || sut.hasActiveOrPendingReconnection
        )
    }
}
