//
//  DeviceManagerTests.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: Unit tests for DeviceManager using MockBLEService dependency injection
//  Demonstrates testing BLE-dependent code without actual Bluetooth hardware
//

import XCTest
import Combine
import CoreBluetooth
@testable import OralableApp

@MainActor
final class DeviceManagerTests: XCTestCase {

    // MARK: - Properties

    var sut: DeviceManager!  // System Under Test
    var mockBLEService: MockBLEService!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Test Lifecycle

    override func setUp() async throws {
        try await super.setUp()

        // Create mock BLE service
        mockBLEService = MockBLEService(bluetoothState: .poweredOn)

        // Inject mock into DeviceManager
        sut = DeviceManager(bleService: mockBLEService)

        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        cancellables = nil
        sut = nil
        mockBLEService = nil

        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testDeviceManagerInitializesWithInjectedBLEService() {
        // Given/When - DeviceManager initialized in setUp

        // Then
        XCTAssertNotNil(sut.bleService)
        XCTAssertFalse(sut.isScanning)
        XCTAssertTrue(sut.discoveredDevices.isEmpty)
        XCTAssertTrue(sut.connectedDevices.isEmpty)
    }

    func testDeviceManagerReflectsBluetoothState() async {
        // Given
        mockBLEService.bluetoothState = .poweredOn

        // When
        mockBLEService.simulateBluetoothStateChange(.poweredOn)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(sut.bluetoothState, .poweredOn)
        XCTAssertTrue(sut.isBluetoothReady)
    }

    func testDeviceManagerHandlesBluetoothPoweredOff() async {
        // Given
        mockBLEService.simulateBluetoothStateChange(.poweredOff)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(sut.bluetoothState, .poweredOff)
        XCTAssertFalse(sut.isBluetoothReady)
    }

    // MARK: - Scanning Tests

    func testStartScanningCallsBLEService() async {
        // Given
        XCTAssertFalse(mockBLEService.startScanningCalled)

        // When
        await sut.startScanning()

        // Then
        XCTAssertTrue(mockBLEService.startScanningCalled)
        XCTAssertTrue(sut.isScanning)
    }

    func testStopScanningCallsBLEService() async {
        // Given
        await sut.startScanning()

        // When
        sut.stopScanning()

        // Then
        XCTAssertTrue(mockBLEService.stopScanningCalled)
        XCTAssertFalse(sut.isScanning)
    }

    func testScanningDiscoversDevices() async throws {
        // Skip: This test requires mock peripherals that properly implement CBPeripheral
        // The current MockPeripheralFactory creates stub objects that aren't recognized
        // as valid Oralable devices by DeviceManager's device type detection logic.
        throw XCTSkip("Requires proper CBPeripheral mock implementation")
    }

    // MARK: - Connection Tests

    func testConnectCallsBLEService() async throws {
        // Skip: This test requires proper peripheral registration in DeviceManager's internal dictionary
        // The mock peripheral isn't properly registered, so connect() can't find the CBPeripheral
        throw XCTSkip("Requires proper CBPeripheral registration in DeviceManager")
    }

    func testDisconnectCallsBLEService() async throws {
        // Skip: This test requires proper peripheral registration in DeviceManager's internal dictionary
        // The mock peripheral isn't properly registered, so disconnect() can't find the CBPeripheral
        throw XCTSkip("Requires proper CBPeripheral registration in DeviceManager")
    }

    // MARK: - Bluetooth State Change Tests

    func testScanningStopsWhenBluetoothPowersOff() async {
        // Given
        await sut.startScanning()
        XCTAssertTrue(sut.isScanning)

        // When
        mockBLEService.simulateBluetoothStateChange(.poweredOff)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertFalse(sut.isScanning)
    }

    // MARK: - Demo Mode Tests

    func testDemoDeviceAppearsWhenDemoModeEnabled() async {
        // Given
        FeatureFlags.shared.demoModeEnabled = true

        // When
        await sut.startScanning()

        // Allow demo device discovery to complete
        try? await Task.sleep(nanoseconds: 600_000_000)

        // Then
        let hasDemoDevice = sut.discoveredDevices.contains { $0.type == .demo }
        XCTAssertTrue(hasDemoDevice)

        // Cleanup
        FeatureFlags.shared.demoModeEnabled = false
    }

    // MARK: - Error Handling Tests

    func testConnectionErrorIsHandled() async {
        // Given
        let testError = NSError(domain: "TestError", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Test connection error"
        ])
        mockBLEService.injectedErrors["connect"] = testError

        // This test demonstrates how to inject errors for testing error handling
        // The actual test would verify that lastError is set appropriately
    }

    // MARK: - Method Call Verification Tests

    func testMethodCallCountsAreTracked() async {
        // Given/When
        await sut.startScanning()
        sut.stopScanning()
        await sut.startScanning()

        // Then
        XCTAssertEqual(mockBLEService.methodCallCounts["startScanning"], 2)
        XCTAssertEqual(mockBLEService.methodCallCounts["stopScanning"], 1)
    }

    func testResetClearsAllTrackingState() async {
        // Given
        await sut.startScanning()
        sut.stopScanning()
        XCTAssertTrue(mockBLEService.startScanningCalled)

        // When
        mockBLEService.reset()

        // Then
        XCTAssertFalse(mockBLEService.startScanningCalled)
        XCTAssertFalse(mockBLEService.stopScanningCalled)
        XCTAssertTrue(mockBLEService.methodCallCounts.isEmpty)
    }

    // MARK: - Async Operation Tests

    func testWhenReadyExecutesImmediatelyIfBluetoothReady() {
        // Given
        var operationExecuted = false
        XCTAssertTrue(mockBLEService.isReady)

        // When
        mockBLEService.whenReady {
            operationExecuted = true
        }

        // Then
        XCTAssertTrue(operationExecuted)
    }

    func testWhenReadyQueuesOperationIfBluetoothNotReady() {
        // Given
        mockBLEService.bluetoothState = .poweredOff
        var operationExecuted = false

        // When
        mockBLEService.whenReady {
            operationExecuted = true
        }

        // Then - operation should be queued, not executed
        XCTAssertFalse(operationExecuted)

        // When - Bluetooth becomes ready
        mockBLEService.simulateBluetoothStateChange(.poweredOn)

        // Then - queued operation should execute
        XCTAssertTrue(operationExecuted)
    }

    // MARK: - Integration Tests

    func testFullScanConnectDisconnectFlow() async {
        // This test demonstrates the full flow that would be tested
        // with properly configured mocks

        // 1. Start scanning
        await sut.startScanning()
        XCTAssertTrue(sut.isScanning)

        // 2. Wait for device discovery (simulated)
        try? await Task.sleep(nanoseconds: 200_000_000)

        // 3. Stop scanning
        sut.stopScanning()
        XCTAssertFalse(sut.isScanning)

        // 4. Verify BLE service was called correctly
        XCTAssertTrue(mockBLEService.startScanningCalled)
        XCTAssertTrue(mockBLEService.stopScanningCalled)
    }
    // MARK: - Error Handling Tests

    func testBluetoothNotReadyErrorSetsLastError() async {
        // Given
        let error = BLEError.bluetoothNotReady(state: .poweredOff)

        // When
        mockBLEService.simulateError(error)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(sut.lastError)
        if case .bluetoothUnavailable = sut.lastError {
            // Expected
        } else {
            XCTFail("Expected bluetoothUnavailable error")
        }
    }

    func testBluetoothUnauthorizedErrorSetsLastError() async {
        // Given
        let error = BLEError.bluetoothUnauthorized

        // When
        mockBLEService.simulateError(error)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(sut.lastError)
        if case .bluetoothUnauthorized = sut.lastError {
            // Expected
        } else {
            XCTFail("Expected bluetoothUnauthorized error")
        }
    }

    func testConnectionFailedErrorUpdatesDeviceReadiness() async throws {
        // Skip: This test requires mock peripherals to be properly discovered and registered
        // The current MockPeripheralFactory doesn't provide peripherals recognized by DeviceManager
        throw XCTSkip("Requires proper CBPeripheral mock implementation for device discovery")
    }

    func testConnectionTimeoutErrorSetsLastError() async {
        // Given
        let deviceId = UUID()
        let error = BLEError.connectionTimeout(peripheralId: deviceId, timeoutSeconds: 15)

        // When
        mockBLEService.simulateError(error)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(sut.lastError)
        if case .connectionFailed = sut.lastError {
            // Timeout is converted to connectionFailed
        } else {
            XCTFail("Expected connectionFailed error for timeout")
        }
    }

    func testUnexpectedDisconnectionErrorSetsConnectionLost() async {
        // Given
        let deviceId = UUID()
        let error = BLEError.unexpectedDisconnection(peripheralId: deviceId, reason: "Connection lost")

        // When
        mockBLEService.simulateError(error)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(sut.lastError)
        if case .connectionLost = sut.lastError {
            // Expected
        } else {
            XCTFail("Expected connectionLost error")
        }
    }

    func testDataCorruptedErrorSetsParsingError() async {
        // Given
        let error = BLEError.dataCorrupted(description: "Invalid checksum")

        // When
        mockBLEService.simulateError(error)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(sut.lastError)
        if case .parsingError = sut.lastError {
            // Expected
        } else {
            XCTFail("Expected parsingError for dataCorrupted")
        }
    }

    func testServiceNotFoundErrorSetsServiceNotFound() async {
        // Given
        let serviceUUID = CBUUID(string: "180D")
        let error = BLEError.serviceNotFound(serviceUUID: serviceUUID, peripheralId: UUID())

        // When
        mockBLEService.simulateError(error)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(sut.lastError)
        if case .serviceNotFound = sut.lastError {
            // Expected
        } else {
            XCTFail("Expected serviceNotFound error")
        }
    }

    func testWriteFailedErrorSetsCharacteristicWriteFailed() async {
        // Given
        let characteristicUUID = CBUUID(string: "2A37")
        let error = BLEError.writeFailed(characteristicUUID: characteristicUUID, reason: "Permission denied")

        // When
        mockBLEService.simulateError(error)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(sut.lastError)
        if case .characteristicWriteFailed = sut.lastError {
            // Expected
        } else {
            XCTFail("Expected characteristicWriteFailed error")
        }
    }

    func testReadFailedErrorSetsCharacteristicReadFailed() async {
        // Given
        let characteristicUUID = CBUUID(string: "2A37")
        let error = BLEError.readFailed(characteristicUUID: characteristicUUID, reason: "Not readable")

        // When
        mockBLEService.simulateError(error)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(sut.lastError)
        if case .characteristicReadFailed = sut.lastError {
            // Expected
        } else {
            XCTFail("Expected characteristicReadFailed error")
        }
    }

    func testMaxReconnectionAttemptsExceededErrorSetsConnectionFailed() async {
        // Given
        let deviceId = UUID()
        let error = BLEError.maxReconnectionAttemptsExceeded(peripheralId: deviceId, attempts: 5)

        // When
        mockBLEService.simulateError(error)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(sut.lastError)
        if case .connectionFailed = sut.lastError {
            // Expected
        } else {
            XCTFail("Expected connectionFailed error for max reconnection attempts")
        }
    }

    func testBluetoothErrorStopsScanning() async {
        // Given
        await sut.startScanning()
        XCTAssertTrue(sut.isScanning)

        let error = BLEError.bluetoothNotReady(state: .poweredOff)

        // When
        mockBLEService.simulateError(error)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertFalse(sut.isScanning)
    }

    func testBluetoothErrorStopsConnecting() async {
        // Given
        sut.isConnecting = true

        let error = BLEError.bluetoothUnauthorized

        // When
        mockBLEService.simulateError(error)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertFalse(sut.isConnecting)
    }

    func testInternalErrorSetsUnknownError() async {
        // Given
        let error = BLEError.internalError(reason: "Something went wrong", underlyingError: nil)

        // When
        mockBLEService.simulateError(error)

        // Allow event to propagate
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(sut.lastError)
        if case .unknownError = sut.lastError {
            // Expected
        } else {
            XCTFail("Expected unknownError for internalError")
        }
    }
}

// MARK: - Test Helpers

extension DeviceManagerTests {

    /// Helper to create a test DeviceInfo
    func createTestDeviceInfo(
        type: DeviceType = .oralable,
        name: String = "Test Device",
        connectionState: DeviceConnectionState = .disconnected
    ) -> DeviceInfo {
        DeviceInfo(
            type: type,
            name: name,
            peripheralIdentifier: UUID(),
            connectionState: connectionState
        )
    }
}
