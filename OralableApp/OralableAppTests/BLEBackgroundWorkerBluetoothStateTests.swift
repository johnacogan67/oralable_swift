//
//  BLEBackgroundWorkerBluetoothStateTests.swift
//  OralableAppTests
//
//  Regression tests for Bluetooth power-state reconnection transitions.
//

import XCTest
import CoreBluetooth
@testable import OralableApp

@MainActor
final class BLEBackgroundWorkerBluetoothStateTests: XCTestCase {

    func testActiveReconnectionPausedByBluetoothOffResumesWhenBluetoothReturns() async {
        let mockBLEService = MockBLEService(bluetoothState: .poweredOn)
        let config = BLEBackgroundWorkerConfig(
            maxReconnectionAttempts: 3,
            baseReconnectionDelay: 0.2,
            maxReconnectionDelay: 0.2,
            jitterFactor: 0.0,
            connectionTimeout: 0.3,
            pauseOnBluetoothOff: true
        )
        let worker = BLEBackgroundWorker(bleService: mockBLEService, config: config)
        worker.configure(bleService: mockBLEService)
        worker.start()
        defer { worker.stop() }

        let deviceId = UUID()
        mockBLEService.addDiscoverableDevice(id: deviceId, name: "Test Device")
        let peripheral = mockBLEService.discoveredPeripherals[deviceId]!

        worker.scheduleReconnection(for: deviceId, peripheral: peripheral, immediate: false)
        XCTAssertTrue(worker.activeReconnections.contains(deviceId))

        mockBLEService.simulateBluetoothStateChange(.poweredOff)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(worker.activeReconnections.contains(deviceId))
        XCTAssertFalse(mockBLEService.connectCalled)

        mockBLEService.simulateBluetoothStateChange(.poweredOn)
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(mockBLEService.connectCalled)
    }
}
