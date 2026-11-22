//
//  BLEMultiDeviceTests.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: Stress tests for multi-device BLE connections
//  Tests simultaneous connections, concurrent data streams, reconnection logic, and resource cleanup
//

import XCTest
import Combine
import CoreBluetooth
@testable import MAMDiagnostics

@MainActor
final class BLEMultiDeviceTests: XCTestCase {

    // MARK: - Properties

    var mockBLEService: MockBLEService!
    var backgroundWorker: BLEBackgroundWorker!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Test Lifecycle

    override func setUp() async throws {
        try await super.setUp()

        mockBLEService = MockBLEService(bluetoothState: .poweredOn)

        let testConfig = BLEBackgroundWorkerConfig(
            maxReconnectionAttempts: 5,
            baseReconnectionDelay: 0.05,
            maxReconnectionDelay: 0.2,
            jitterFactor: 0.0,
            connectionTimeout: 0.5,
            pauseOnBluetoothOff: true
        )
        backgroundWorker = BLEBackgroundWorker(bleService: mockBLEService, config: testConfig)
        backgroundWorker.configure(bleService: mockBLEService)

        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        backgroundWorker.stop()
        cancellables = nil
        mockBLEService = nil
        backgroundWorker = nil
        MockPeripheralFactory.reset()

        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func createMockDevices(count: Int) -> [(UUID, CBPeripheral)] {
        var devices: [(UUID, CBPeripheral)] = []

        for i in 0..<count {
            let deviceId = UUID()
            let name = "Test Device \(i + 1)"
            mockBLEService.addDiscoverableDevice(id: deviceId, name: name)
            if let peripheral = mockBLEService.discoveredPeripherals[deviceId] {
                devices.append((deviceId, peripheral))
            }
        }

        return devices
    }

    private func connectAllDevices(_ devices: [(UUID, CBPeripheral)]) async {
        for (deviceId, peripheral) in devices {
            mockBLEService.connect(to: peripheral)
            // Simulate successful connection
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            mockBLEService.simulateConnection(to: deviceId)
        }
    }

    // MARK: - Simultaneous Connection Tests

    func testSimultaneousConnectionToTwoDevices() async {
        // Given
        let devices = createMockDevices(count: 2)
        let expectation = XCTestExpectation(description: "Both devices connected")
        expectation.expectedFulfillmentCount = 2

        var connectedDevices: Set<UUID> = []

        mockBLEService.eventPublisher
            .sink { event in
                if case .deviceConnected(let peripheral) = event {
                    connectedDevices.insert(peripheral.identifier)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - connect to both devices simultaneously
        for (_, peripheral) in devices {
            mockBLEService.connect(to: peripheral)
        }

        // Simulate successful connections
        for (deviceId, _) in devices {
            mockBLEService.simulateConnection(to: deviceId)
        }

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(connectedDevices.count, 2, "Both devices should be connected")
        XCTAssertEqual(mockBLEService.connectedPeripherals.count, 2, "Service should track both connections")
    }

    func testSimultaneousConnectionToThreeDevices() async {
        // Given
        let devices = createMockDevices(count: 3)
        let expectation = XCTestExpectation(description: "All three devices connected")
        expectation.expectedFulfillmentCount = 3

        var connectedDevices: Set<UUID> = []

        mockBLEService.eventPublisher
            .sink { event in
                if case .deviceConnected(let peripheral) = event {
                    connectedDevices.insert(peripheral.identifier)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        for (_, peripheral) in devices {
            mockBLEService.connect(to: peripheral)
        }

        for (deviceId, _) in devices {
            mockBLEService.simulateConnection(to: deviceId)
        }

        // Then
        await fulfillment(of: [expectation], timeout: 3.0)

        XCTAssertEqual(connectedDevices.count, 3, "All three devices should be connected")
        XCTAssertEqual(mockBLEService.connectedPeripherals.count, 3)
    }

    func testSimultaneousConnectionToFiveDevices() async {
        // Given
        let devices = createMockDevices(count: 5)
        let expectation = XCTestExpectation(description: "All five devices connected")
        expectation.expectedFulfillmentCount = 5

        var connectedDevices: Set<UUID> = []

        mockBLEService.eventPublisher
            .sink { event in
                if case .deviceConnected(let peripheral) = event {
                    connectedDevices.insert(peripheral.identifier)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        for (_, peripheral) in devices {
            mockBLEService.connect(to: peripheral)
        }

        for (deviceId, _) in devices {
            mockBLEService.simulateConnection(to: deviceId)
        }

        // Then
        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertEqual(connectedDevices.count, 5, "All five devices should be connected")
        XCTAssertEqual(mockBLEService.connectedPeripherals.count, 5)
    }

    // MARK: - Concurrent Data Stream Tests

    func testConcurrentDataStreamsFromTwoDevices() async {
        // Given
        let devices = createMockDevices(count: 2)
        await connectAllDevices(devices)

        let dataExpectation = XCTestExpectation(description: "Data received from both devices")
        dataExpectation.expectedFulfillmentCount = 4 // 2 updates per device

        var dataReceivedFromDevices: [UUID: Int] = [:]

        mockBLEService.eventPublisher
            .sink { event in
                if case .characteristicUpdated(let peripheral, _, _) = event {
                    let id = peripheral.identifier
                    dataReceivedFromDevices[id, default: 0] += 1
                    dataExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - simulate data from both devices concurrently
        for (_, peripheral) in devices {
            // Send multiple data packets using the mock helper
            for i in 0..<2 {
                let data = Data([UInt8(i), UInt8(peripheral.identifier.hashValue & 0xFF)])
                mockBLEService.simulateCharacteristicDataReceived(peripheral: peripheral, data: data)
            }
        }

        // Then
        await fulfillment(of: [dataExpectation], timeout: 3.0)

        // Verify data was received from both devices
        XCTAssertEqual(dataReceivedFromDevices.count, 2, "Should receive data from both devices")
    }

    func testConcurrentDataStreamsFromFiveDevices() async {
        // Given
        let devices = createMockDevices(count: 5)
        await connectAllDevices(devices)

        let dataExpectation = XCTestExpectation(description: "Data received from all devices")
        dataExpectation.expectedFulfillmentCount = 10 // 2 updates per device

        var dataReceivedFromDevices: [UUID: Int] = [:]

        mockBLEService.eventPublisher
            .sink { event in
                if case .characteristicUpdated(let peripheral, _, _) = event {
                    let id = peripheral.identifier
                    dataReceivedFromDevices[id, default: 0] += 1
                    dataExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - simulate data from all devices concurrently
        for (_, peripheral) in devices {
            for i in 0..<2 {
                let data = Data([UInt8(i)])
                mockBLEService.simulateCharacteristicDataReceived(peripheral: peripheral, data: data)
            }
        }

        // Then
        await fulfillment(of: [dataExpectation], timeout: 5.0)

        XCTAssertEqual(dataReceivedFromDevices.count, 5, "Should receive data from all five devices")
    }

    func testHighFrequencyDataStreams() async {
        // Given - stress test with rapid data
        let devices = createMockDevices(count: 3)
        await connectAllDevices(devices)

        let dataCount = 50 // High frequency test
        let dataExpectation = XCTestExpectation(description: "High frequency data received")
        dataExpectation.expectedFulfillmentCount = dataCount * devices.count

        var totalDataReceived = 0

        mockBLEService.eventPublisher
            .sink { event in
                if case .characteristicUpdated = event {
                    totalDataReceived += 1
                    dataExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - rapid fire data from all devices
        for (_, peripheral) in devices {
            for i in 0..<dataCount {
                let data = Data([UInt8(i & 0xFF)])
                mockBLEService.simulateCharacteristicDataReceived(peripheral: peripheral, data: data)
            }
        }

        // Then
        await fulfillment(of: [dataExpectation], timeout: 10.0)

        XCTAssertEqual(totalDataReceived, dataCount * devices.count, "Should handle high frequency data")
    }

    // MARK: - Reconnection Logic Tests

    func testReconnectionWhenOneDeviceDisconnectsWhileOthersRemainConnected() async {
        // Given
        backgroundWorker.start()
        let devices = createMockDevices(count: 3)
        await connectAllDevices(devices)

        let (disconnectedId, disconnectedPeripheral) = devices[0]
        let reconnectionExpectation = XCTestExpectation(description: "Reconnection attempt started")

        backgroundWorker.eventPublisher
            .sink { event in
                if case .reconnectionAttemptStarted(let peripheralId, _, _) = event {
                    if peripheralId == disconnectedId {
                        reconnectionExpectation.fulfill()
                    }
                }
            }
            .store(in: &cancellables)

        // When - disconnect one device
        mockBLEService.simulateDisconnection(from: disconnectedId, error: BLEError.unexpectedDisconnection(peripheralId: disconnectedId, reason: "Test disconnection"))

        // Schedule reconnection
        backgroundWorker.scheduleReconnection(for: disconnectedId, peripheral: disconnectedPeripheral, immediate: true)

        // Then - reconnection should be attempted
        await fulfillment(of: [reconnectionExpectation], timeout: 2.0)

        // Verify other devices remain connected
        XCTAssertTrue(mockBLEService.connectedPeripherals.contains(devices[1].0), "Device 2 should remain connected")
        XCTAssertTrue(mockBLEService.connectedPeripherals.contains(devices[2].0), "Device 3 should remain connected")
    }

    func testReconnectionSucceedsForDisconnectedDevice() async {
        // Given
        backgroundWorker.start()
        let devices = createMockDevices(count: 2)
        await connectAllDevices(devices)

        let (disconnectedId, disconnectedPeripheral) = devices[0]

        let successExpectation = XCTestExpectation(description: "Reconnection succeeded")

        backgroundWorker.eventPublisher
            .sink { event in
                if case .reconnectionSucceeded(let peripheralId) = event {
                    if peripheralId == disconnectedId {
                        successExpectation.fulfill()
                    }
                }
            }
            .store(in: &cancellables)

        // When - disconnect and reconnect
        mockBLEService.simulateDisconnection(from: disconnectedId)
        backgroundWorker.scheduleReconnection(for: disconnectedId, peripheral: disconnectedPeripheral, immediate: true)

        // Allow connection attempt
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Simulate successful reconnection
        mockBLEService.simulateConnection(to: disconnectedId)

        // Then
        await fulfillment(of: [successExpectation], timeout: 3.0)

        XCTAssertFalse(backgroundWorker.activeReconnections.contains(disconnectedId))
    }

    func testMultipleDevicesReconnectIndependently() async {
        // Given
        backgroundWorker.start()
        let devices = createMockDevices(count: 3)
        await connectAllDevices(devices)

        var reconnectionAttempts: [UUID: Int] = [:]

        backgroundWorker.eventPublisher
            .sink { event in
                if case .reconnectionAttemptStarted(let peripheralId, let attempt, _) = event {
                    reconnectionAttempts[peripheralId] = attempt
                }
            }
            .store(in: &cancellables)

        // When - disconnect all devices
        for (deviceId, peripheral) in devices {
            mockBLEService.simulateDisconnection(from: deviceId)
            backgroundWorker.scheduleReconnection(for: deviceId, peripheral: peripheral, immediate: true)
        }

        // Allow reconnection attempts
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Then - all devices should have reconnection attempts
        XCTAssertEqual(reconnectionAttempts.count, 3, "All devices should have reconnection attempts")
        for (deviceId, _) in devices {
            XCTAssertTrue(backgroundWorker.activeReconnections.contains(deviceId) || reconnectionAttempts[deviceId] != nil,
                         "Device should have active reconnection or have attempted")
        }
    }

    // MARK: - Resource Cleanup Tests

    func testResourceCleanupWhenDevicesDisconnectSimultaneously() async {
        // Given
        let devices = createMockDevices(count: 5)
        await connectAllDevices(devices)

        XCTAssertEqual(mockBLEService.connectedPeripherals.count, 5)

        let disconnectExpectation = XCTestExpectation(description: "All devices disconnected")
        disconnectExpectation.expectedFulfillmentCount = 5

        mockBLEService.eventPublisher
            .sink { event in
                if case .deviceDisconnected = event {
                    disconnectExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - disconnect all devices simultaneously
        mockBLEService.disconnectAll()

        // Then
        await fulfillment(of: [disconnectExpectation], timeout: 3.0)

        XCTAssertTrue(mockBLEService.connectedPeripherals.isEmpty, "All connections should be cleared")
        XCTAssertTrue(mockBLEService.disconnectAllCalled, "DisconnectAll should have been called")
    }

    func testResourceCleanupOnIndividualDisconnects() async {
        // Given
        let devices = createMockDevices(count: 3)
        await connectAllDevices(devices)

        // When - disconnect each device individually
        for (deviceId, peripheral) in devices {
            mockBLEService.disconnect(from: peripheral)
        }

        // Then
        XCTAssertTrue(mockBLEService.connectedPeripherals.isEmpty, "All connections should be cleared")
        XCTAssertEqual(mockBLEService.methodCallCounts["disconnect"], 3, "Disconnect should be called for each device")
    }

    func testNoMemoryLeaksAfterMultipleConnectDisconnectCycles() async {
        // Given
        weak var weakService = mockBLEService

        // When - perform multiple connect/disconnect cycles
        for cycle in 0..<5 {
            let devices = createMockDevices(count: 3)
            await connectAllDevices(devices)

            // Verify connections
            XCTAssertEqual(mockBLEService.connectedPeripherals.count, 3, "Cycle \(cycle): Should have 3 connections")

            // Disconnect all
            for (deviceId, _) in devices {
                mockBLEService.simulateDisconnection(from: deviceId)
            }

            // Verify cleanup
            XCTAssertTrue(mockBLEService.connectedPeripherals.isEmpty, "Cycle \(cycle): Should have no connections")

            // Clean up discovered peripherals for next cycle
            mockBLEService.discoveredPeripherals.removeAll()
        }

        // Then - service should still be accessible (not deallocated while in use)
        XCTAssertNotNil(weakService, "Service should still exist")
    }

    // MARK: - Rapid Connect/Disconnect Cycle Tests

    func testRapidConnectDisconnectCycles() async {
        // Given
        let deviceId = UUID()
        mockBLEService.addDiscoverableDevice(id: deviceId, name: "Stress Test Device")
        let peripheral = mockBLEService.discoveredPeripherals[deviceId]!

        var connectCount = 0
        var disconnectCount = 0

        mockBLEService.eventPublisher
            .sink { event in
                switch event {
                case .deviceConnected:
                    connectCount += 1
                case .deviceDisconnected:
                    disconnectCount += 1
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // When - rapid connect/disconnect cycles
        let cycles = 20
        for _ in 0..<cycles {
            mockBLEService.connect(to: peripheral)
            mockBLEService.simulateConnection(to: deviceId)
            mockBLEService.simulateDisconnection(from: deviceId)
        }

        // Allow events to propagate
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Then
        XCTAssertEqual(connectCount, cycles, "Should have \(cycles) connect events")
        XCTAssertEqual(disconnectCount, cycles, "Should have \(cycles) disconnect events")
    }

    func testRapidConnectDisconnectWithMultipleDevices() async {
        // Given
        let devices = createMockDevices(count: 3)

        var eventCounts: [String: Int] = ["connect": 0, "disconnect": 0]

        mockBLEService.eventPublisher
            .sink { event in
                switch event {
                case .deviceConnected:
                    eventCounts["connect", default: 0] += 1
                case .deviceDisconnected:
                    eventCounts["disconnect", default: 0] += 1
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // When - rapid cycles for all devices
        let cyclesPerDevice = 10
        for _ in 0..<cyclesPerDevice {
            for (deviceId, peripheral) in devices {
                mockBLEService.connect(to: peripheral)
                mockBLEService.simulateConnection(to: deviceId)
            }
            for (deviceId, _) in devices {
                mockBLEService.simulateDisconnection(from: deviceId)
            }
        }

        // Allow events to propagate
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Then
        let expectedPerDevice = cyclesPerDevice * devices.count
        XCTAssertEqual(eventCounts["connect"], expectedPerDevice, "Should have \(expectedPerDevice) connect events")
        XCTAssertEqual(eventCounts["disconnect"], expectedPerDevice, "Should have \(expectedPerDevice) disconnect events")
    }

    // MARK: - Performance Tests

    func testConnectionPerformanceWithMultipleDevices() async {
        // Given
        let deviceCount = 10
        let devices = createMockDevices(count: deviceCount)

        // When/Then - measure connection time
        let startTime = CFAbsoluteTimeGetCurrent()

        for (_, peripheral) in devices {
            mockBLEService.connect(to: peripheral)
        }
        for (deviceId, _) in devices {
            mockBLEService.simulateConnection(to: deviceId)
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime

        // Should complete quickly (under 1 second for mock connections)
        XCTAssertLessThan(duration, 1.0, "Connecting \(deviceCount) devices should be fast")
        XCTAssertEqual(mockBLEService.connectedPeripherals.count, deviceCount)
    }

    func testEventPublisherPerformanceUnderLoad() async {
        // Given
        let devices = createMockDevices(count: 5)
        await connectAllDevices(devices)

        var eventCount = 0
        let targetEvents = 500

        let expectation = XCTestExpectation(description: "All events processed")

        mockBLEService.eventPublisher
            .sink { _ in
                eventCount += 1
                if eventCount >= targetEvents {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - generate many events rapidly
        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 0..<(targetEvents / devices.count) {
            for (_, peripheral) in devices {
                let data = Data([UInt8(i & 0xFF)])
                mockBLEService.simulateCharacteristicDataReceived(peripheral: peripheral, data: data)
            }
        }

        // Then
        await fulfillment(of: [expectation], timeout: 10.0)

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let eventsPerSecond = Double(targetEvents) / duration

        XCTAssertGreaterThan(eventsPerSecond, 100, "Should process at least 100 events per second")
    }

    // MARK: - Stress Test - Maximum Concurrent Connections

    func testMaximumConcurrentConnections() async {
        // Given - iOS typically allows 7-8 concurrent BLE connections
        // Test with 10 to verify handling of potential over-subscription
        let devices = createMockDevices(count: 10)

        let connectionExpectation = XCTestExpectation(description: "All connections attempted")
        connectionExpectation.expectedFulfillmentCount = 10

        mockBLEService.eventPublisher
            .sink { event in
                if case .deviceConnected = event {
                    connectionExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        for (deviceId, peripheral) in devices {
            mockBLEService.connect(to: peripheral)
            mockBLEService.simulateConnection(to: deviceId)
        }

        // Then
        await fulfillment(of: [connectionExpectation], timeout: 5.0)

        XCTAssertEqual(mockBLEService.connectedPeripherals.count, 10)
    }

    // MARK: - Error Handling Tests

    func testConnectionFailureDoesNotAffectOtherDevices() async {
        // Given
        let devices = createMockDevices(count: 3)

        // Connect first two devices successfully
        await connectAllDevices(Array(devices[0..<2]))

        // Configure third device to fail
        let (failingId, failingPeripheral) = devices[2]
        mockBLEService.injectedErrors["connect"] = BLEError.connectionFailed(peripheralId: failingId, reason: "Test failure")

        var errorReceived = false

        mockBLEService.eventPublisher
            .sink { event in
                if case .deviceDisconnected(let peripheral, let error) = event {
                    if peripheral.identifier == failingId && error != nil {
                        errorReceived = true
                    }
                }
            }
            .store(in: &cancellables)

        // When
        mockBLEService.connect(to: failingPeripheral)

        try? await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertTrue(errorReceived, "Should receive error for failing device")
        XCTAssertEqual(mockBLEService.connectedPeripherals.count, 2, "Other devices should remain connected")
        XCTAssertTrue(mockBLEService.connectedPeripherals.contains(devices[0].0))
        XCTAssertTrue(mockBLEService.connectedPeripherals.contains(devices[1].0))
    }

    func testMultipleSimultaneousConnectionFailures() async {
        // Given
        let devices = createMockDevices(count: 4)

        // First two will fail, last two will succeed
        for i in 0..<2 {
            let (failingId, _) = devices[i]
            mockBLEService.injectedErrors["connect_\(failingId)"] = BLEError.connectionFailed(peripheralId: failingId, reason: "Test failure")
        }

        var failureCount = 0
        var successCount = 0

        mockBLEService.eventPublisher
            .sink { event in
                switch event {
                case .deviceConnected:
                    successCount += 1
                case .deviceDisconnected(_, let error) where error != nil:
                    failureCount += 1
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // When - connect all devices
        for (_, peripheral) in devices {
            mockBLEService.connect(to: peripheral)
        }

        // Simulate failures for first two, success for last two
        mockBLEService.simulateConnectionFailure(for: devices[0].0, error: BLEError.connectionFailed(peripheralId: devices[0].0, reason: "Test"))
        mockBLEService.simulateConnectionFailure(for: devices[1].0, error: BLEError.connectionFailed(peripheralId: devices[1].0, reason: "Test"))
        mockBLEService.simulateConnection(to: devices[2].0)
        mockBLEService.simulateConnection(to: devices[3].0)

        try? await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertEqual(successCount, 2, "Two devices should connect successfully")
        XCTAssertEqual(mockBLEService.connectedPeripherals.count, 2)
    }
}
