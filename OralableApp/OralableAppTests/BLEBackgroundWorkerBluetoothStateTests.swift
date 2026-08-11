//
//  BLEBackgroundWorkerBluetoothStateTests.swift
//  OralableAppTests
//
//  Regression tests for Bluetooth state transitions during reconnects.
//

import XCTest
@testable import OralableApp

@MainActor
extension BLEBackgroundWorkerTests {

    func testActiveReconnectionResumesAfterBluetoothPowerCycle() async {
        // Given
        sut.start()
        let deviceId = UUID()
        mockBLEService.addDiscoverableDevice(id: deviceId, name: "Power Cycle Device")
        let peripheral = mockBLEService.discoveredPeripherals[deviceId]!

        // Start a delayed reconnect, then power Bluetooth off before the task attempts to connect.
        sut.scheduleReconnection(for: deviceId, peripheral: peripheral, immediate: false)
        XCTAssertTrue(sut.activeReconnections.contains(deviceId))

        mockBLEService.simulateBluetoothStateChange(.poweredOff)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(sut.activeReconnections.contains(deviceId))

        mockBLEService.methodCallCounts.removeAll()

        // When
        mockBLEService.simulateBluetoothStateChange(.poweredOn)

        // Then - the pending reconnect should be scheduled instead of rejected as already active.
        try? await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertTrue(mockBLEService.connectCalled)
    }
}
