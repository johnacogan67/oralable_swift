//
//  DevicesViewModelTests.swift
//  OralableAppTests
//
//  Created: Refactoring Phase 1
//  Purpose: Unit tests for DevicesViewModel using protocol-based DI
//

import XCTest
import Combine
@testable import MAMDiagnostics

@MainActor
final class DevicesViewModelTests: XCTestCase {
    var mockBLE: MockBLEManager!
    var viewModel: DevicesViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockBLE = MockBLEManager()
        viewModel = DevicesViewModel(bleManager: mockBLE)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        mockBLE = nil
        viewModel = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialState() {
        // Then
        XCTAssertFalse(viewModel.isConnected, "Should not be connected initially")
        XCTAssertFalse(viewModel.isScanning, "Should not be scanning initially")
        XCTAssertEqual(viewModel.deviceName, "Mock Device", "Should have mock device name")
        XCTAssertTrue(viewModel.discoveredDevices.isEmpty, "Should have no discovered devices initially")
    }

    // MARK: - Connection Tests

    func testConnectionStatusUpdate() async {
        // Given
        let expectation = XCTestExpectation(description: "Connection status updates")

        viewModel.$isConnected
            .dropFirst()  // Skip initial value
            .sink { isConnected in
                XCTAssertTrue(isConnected, "Should be connected")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        mockBLE.simulateConnection()

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(viewModel.deviceName, "Simulated Device")
    }

    func testDisconnection() async {
        // Given - Start connected
        mockBLE.simulateConnection()

        // Wait for connection
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        let expectation = XCTestExpectation(description: "Disconnection updates")

        viewModel.$isConnected
            .dropFirst()  // Skip current connected state
            .sink { isConnected in
                if !isConnected {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        mockBLE.simulateDisconnection()

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertFalse(viewModel.isConnected)
    }

    func testDisconnectAction() {
        // Given
        mockBLE.simulateConnection()
        XCTAssertFalse(mockBLE.disconnectCalled)

        // When
        viewModel.disconnect()

        // Then
        XCTAssertTrue(mockBLE.disconnectCalled, "Should call disconnect on BLE manager")
    }

    // MARK: - Scanning Tests

    func testToggleScanningStart() {
        // Given
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertFalse(mockBLE.startScanningCalled)

        // When
        viewModel.toggleScanning()

        // Then
        XCTAssertTrue(mockBLE.startScanningCalled, "Should start scanning")
    }

    func testToggleScanningStop() {
        // Given - Start scanning first
        mockBLE.isScanning = true
        viewModel.toggleScanning()  // This starts scanning

        XCTAssertFalse(mockBLE.stopScanningCalled)

        // When - Toggle again to stop
        viewModel.toggleScanning()

        // Then
        XCTAssertTrue(mockBLE.stopScanningCalled, "Should stop scanning")
    }

    func testScanningStatusUpdate() async {
        // Given
        let expectation = XCTestExpectation(description: "Scanning status updates")

        viewModel.$isScanning
            .dropFirst()  // Skip initial value
            .sink { isScanning in
                if isScanning {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        mockBLE.isScanning = true

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(viewModel.isScanning)
    }

    // MARK: - Device Name Tests

    func testDeviceNameUpdate() async {
        // Given
        let expectation = XCTestExpectation(description: "Device name updates")

        viewModel.$deviceName
            .dropFirst()  // Skip initial value
            .sink { name in
                if name == "Test Device" {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        mockBLE.deviceName = "Test Device"

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(viewModel.deviceName, "Test Device")
    }

    // MARK: - Settings Tests

    func testAutoConnectSetting() {
        // Given
        XCTAssertTrue(viewModel.autoConnect, "Should default to true")

        // When
        viewModel.autoConnect = false

        // Then
        XCTAssertFalse(viewModel.autoConnect, "Should update autoConnect setting")
    }

    func testLEDBrightnessSetting() {
        // Given
        XCTAssertEqual(viewModel.ledBrightness, 0.5, "Should default to 0.5")

        // When
        viewModel.ledBrightness = 0.8

        // Then
        XCTAssertEqual(viewModel.ledBrightness, 0.8, "Should update LED brightness")
    }

    func testSampleRateSetting() {
        // Given
        XCTAssertEqual(viewModel.sampleRate, 50, "Should default to 50")

        // When
        viewModel.sampleRate = 100

        // Then
        XCTAssertEqual(viewModel.sampleRate, 100, "Should update sample rate")
    }

    // MARK: - Device Info Tests

    func testDeviceInfo() {
        // Then
        XCTAssertEqual(viewModel.serialNumber, "ORA-2025-001")
        XCTAssertEqual(viewModel.firmwareVersion, "1.0.0")
        XCTAssertEqual(viewModel.lastSyncTime, "Just now")
    }

    // MARK: - Integration Tests

    func testConnectionFlow() async {
        // Given
        XCTAssertFalse(viewModel.isConnected)
        XCTAssertEqual(viewModel.deviceName, "Mock Device")

        let expectation = XCTestExpectation(description: "Full connection flow")

        viewModel.$isConnected
            .dropFirst()
            .sink { isConnected in
                if isConnected {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - Simulate connection
        mockBLE.simulateConnection()

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(viewModel.isConnected)
        XCTAssertEqual(viewModel.deviceName, "Simulated Device")
    }

    func testScanningFlow() {
        // Given
        XCTAssertFalse(viewModel.isScanning)

        // When - Start scanning
        viewModel.toggleScanning()

        // Then
        XCTAssertTrue(mockBLE.startScanningCalled)

        // When - Stop scanning
        mockBLE.isScanning = true
        viewModel.toggleScanning()

        // Then
        XCTAssertTrue(mockBLE.stopScanningCalled)
    }
}
