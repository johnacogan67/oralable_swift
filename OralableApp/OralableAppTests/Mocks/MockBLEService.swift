//
//  MockBLEService.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: Mock BLE service for unit testing DeviceManager and other BLE-dependent classes
//  Allows tests to simulate BLE behavior without actual Bluetooth hardware
//

import Foundation
import Combine
import CoreBluetooth
@testable import OralableApp

/// Mock BLE Service for unit testing
/// Conforms to BLEService protocol and allows simulation of all BLE operations
class MockBLEService: BLEService {

    // MARK: - BLEService Protocol - State

    var bluetoothState: CBManagerState = .poweredOn
    var isReady: Bool { bluetoothState == .poweredOn }
    var isScanning: Bool = false

    /// Event publisher for BLE service events
    var eventPublisher: AnyPublisher<BLEServiceEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    // MARK: - Internal State for Testing

    private let eventSubject = PassthroughSubject<BLEServiceEvent, Never>()

    /// Simulated discovered peripherals
    var discoveredPeripherals: [UUID: MockPeripheral] = [:]

    /// Simulated connected peripherals
    var connectedPeripherals: Set<UUID> = []

    /// Pending operations queue
    private var pendingOperations: [() -> Void] = []

    // MARK: - Test Tracking Properties

    /// Tracks how many times each method was called
    var methodCallCounts: [String: Int] = [:]

    /// Tracks the parameters passed to methods
    var methodCallParameters: [String: [Any]] = [:]

    /// Errors to inject for testing error handling
    var injectedErrors: [String: Error] = [:]

    /// Delays to inject for testing async behavior (in seconds)
    var injectedDelays: [String: TimeInterval] = [:]

    // MARK: - Convenience Test Flags

    var startScanningCalled: Bool { (methodCallCounts["startScanning"] ?? 0) > 0 }
    var stopScanningCalled: Bool { (methodCallCounts["stopScanning"] ?? 0) > 0 }
    var connectCalled: Bool { (methodCallCounts["connect"] ?? 0) > 0 }
    var disconnectCalled: Bool { (methodCallCounts["disconnect"] ?? 0) > 0 }
    var disconnectAllCalled: Bool { (methodCallCounts["disconnectAll"] ?? 0) > 0 }
    var readValueCalled: Bool { (methodCallCounts["readValue"] ?? 0) > 0 }
    var writeValueCalled: Bool { (methodCallCounts["writeValue"] ?? 0) > 0 }
    var setNotifyValueCalled: Bool { (methodCallCounts["setNotifyValue"] ?? 0) > 0 }

    // MARK: - Initialization

    init(bluetoothState: CBManagerState = .poweredOn) {
        self.bluetoothState = bluetoothState
    }

    // MARK: - BLEService Protocol - Scanning

    func startScanning(services: [CBUUID]?) {
        recordMethodCall("startScanning", parameters: [services as Any])

        guard bluetoothState == .poweredOn else {
            return
        }

        isScanning = true

        // Simulate discovery of pre-configured devices after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.simulateDiscoveryOfConfiguredDevices()
        }
    }

    func stopScanning() {
        recordMethodCall("stopScanning", parameters: [])
        isScanning = false
    }

    // MARK: - BLEService Protocol - Connection Management

    func connect(to peripheral: CBPeripheral) {
        recordMethodCall("connect", parameters: [peripheral])

        let peripheralId = peripheral.identifier

        // Simulate connection delay
        let delay = injectedDelays["connect"] ?? 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }

            // Check for injected error
            if let error = self.injectedErrors["connect"] {
                self.eventSubject.send(.deviceDisconnected(peripheral: peripheral, error: error))
                return
            }

            self.connectedPeripherals.insert(peripheralId)
            self.eventSubject.send(.deviceConnected(peripheral: peripheral))
        }
    }

    func disconnect(from peripheral: CBPeripheral) {
        recordMethodCall("disconnect", parameters: [peripheral])

        let peripheralId = peripheral.identifier
        connectedPeripherals.remove(peripheralId)

        // Emit disconnection event
        eventSubject.send(.deviceDisconnected(peripheral: peripheral, error: nil))
    }

    func disconnectAll() {
        recordMethodCall("disconnectAll", parameters: [])

        for peripheralId in connectedPeripherals {
            if let mockPeripheral = discoveredPeripherals[peripheralId] {
                eventSubject.send(.deviceDisconnected(peripheral: mockPeripheral, error: nil))
            }
        }
        connectedPeripherals.removeAll()
    }

    // MARK: - BLEService Protocol - Read/Write Operations

    func readValue(from characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        recordMethodCall("readValue", parameters: [characteristic, peripheral])

        // Simulate read completion with mock data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            let mockData = Data([0x00, 0x01, 0x02, 0x03])
            self?.eventSubject.send(.characteristicUpdated(
                peripheral: peripheral,
                characteristic: characteristic,
                data: mockData
            ))
        }
    }

    func writeValue(_ data: Data, to characteristic: CBCharacteristic, on peripheral: CBPeripheral, type: CBCharacteristicWriteType) {
        recordMethodCall("writeValue", parameters: [data, characteristic, peripheral, type])

        // Simulate write completion
        if type == .withResponse {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                let error = self?.injectedErrors["writeValue"]
                self?.eventSubject.send(.characteristicWritten(
                    peripheral: peripheral,
                    characteristic: characteristic,
                    error: error
                ))
            }
        }
    }

    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        recordMethodCall("setNotifyValue", parameters: [enabled, characteristic, peripheral])
    }

    // MARK: - BLEService Protocol - Service Discovery

    func discoverServices(_ services: [CBUUID]?, on peripheral: CBPeripheral) {
        recordMethodCall("discoverServices", parameters: [services as Any, peripheral])
    }

    func discoverCharacteristics(_ characteristics: [CBUUID]?, for service: CBService, on peripheral: CBPeripheral) {
        recordMethodCall("discoverCharacteristics", parameters: [characteristics as Any, service, peripheral])
    }

    // MARK: - BLEService Protocol - Utility

    func whenReady(_ operation: @escaping () -> Void) {
        recordMethodCall("whenReady", parameters: [])

        if isReady {
            operation()
        } else {
            pendingOperations.append(operation)
        }
    }

    func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] {
        recordMethodCall("retrievePeripherals", parameters: [identifiers])

        return identifiers.compactMap { discoveredPeripherals[$0] }
    }

    // MARK: - Test Helper Methods

    /// Record a method call for verification
    private func recordMethodCall(_ method: String, parameters: [Any]) {
        methodCallCounts[method, default: 0] += 1
        methodCallParameters[method, default: []].append(contentsOf: parameters)
    }

    /// Reset all test tracking state
    func reset() {
        methodCallCounts.removeAll()
        methodCallParameters.removeAll()
        injectedErrors.removeAll()
        injectedDelays.removeAll()
        discoveredPeripherals.removeAll()
        connectedPeripherals.removeAll()
        isScanning = false
        bluetoothState = .poweredOn
        simulatedAppState = .foreground
    }

    /// Simulate Bluetooth state change
    func simulateBluetoothStateChange(_ state: CBManagerState) {
        bluetoothState = state
        eventSubject.send(.bluetoothStateChanged(state: state))

        // Execute pending operations if becoming ready
        if state == .poweredOn {
            let operations = pendingOperations
            pendingOperations.removeAll()
            operations.forEach { $0() }
        }
    }

    /// Add a mock peripheral that will be "discovered" during scanning
    func addDiscoverableDevice(id: UUID, name: String, rssi: Int = -50) {
        let peripheral = MockPeripheralFactory.create(identifier: id, name: name)
        discoveredPeripherals[id] = peripheral
    }

    /// Simulate device discovery
    func simulateDeviceDiscovery(peripheral: CBPeripheral, name: String, rssi: Int) {
        eventSubject.send(.deviceDiscovered(peripheral: peripheral, name: name, rssi: rssi, advertisementData: [:]))
    }

    /// Simulate connection to a specific device
    func simulateConnection(to peripheralId: UUID) {
        guard let peripheral = discoveredPeripherals[peripheralId] else { return }
        connectedPeripherals.insert(peripheralId)
        eventSubject.send(.deviceConnected(peripheral: peripheral))
    }

    /// Simulate disconnection from a specific device
    func simulateDisconnection(from peripheralId: UUID, error: Error? = nil) {
        guard let peripheral = discoveredPeripherals[peripheralId] else { return }
        connectedPeripherals.remove(peripheralId)
        eventSubject.send(.deviceDisconnected(peripheral: peripheral, error: error))
    }

    /// Simulate characteristic update (for testing data reception)
    func simulateCharacteristicUpdate(peripheral: CBPeripheral, characteristic: CBCharacteristic, data: Data) {
        eventSubject.send(.characteristicUpdated(peripheral: peripheral, characteristic: characteristic, data: data))
    }

    /// Simulate a BLE error event
    func simulateError(_ error: BLEError) {
        eventSubject.send(.error(error))
    }

    /// Simulate connection failure with BLEError
    func simulateConnectionFailure(for peripheralId: UUID, error: BLEError) {
        guard let peripheral = discoveredPeripherals[peripheralId] else { return }
        connectedPeripherals.remove(peripheralId)
        eventSubject.send(.error(error))
        eventSubject.send(.deviceDisconnected(peripheral: peripheral, error: error))
    }

    // MARK: - Multi-Device Simulation Helpers

    /// Track simulated app state for testing background behavior
    private(set) var simulatedAppState: AppState = .foreground

    /// Simulated app states for testing
    enum AppState {
        case foreground
        case background
        case suspended
        case terminating
    }

    /// Simulate app entering background mode
    /// Maintains BLE connections but may affect operation timing
    func simulateAppEnterBackground() {
        simulatedAppState = .background
        recordMethodCall("simulateAppEnterBackground", parameters: [])
    }

    /// Simulate app returning to foreground
    func simulateAppEnterForeground() {
        simulatedAppState = .foreground
        recordMethodCall("simulateAppEnterForeground", parameters: [])
    }

    /// Simulate app suspension (for memory pressure, etc.)
    func simulateAppSuspend() {
        simulatedAppState = .suspended
        recordMethodCall("simulateAppSuspend", parameters: [])
    }

    /// Simulate app termination
    func simulateAppTermination() {
        simulatedAppState = .terminating
        recordMethodCall("simulateAppTermination", parameters: [])
        // Terminate all connections
        disconnectAll()
    }

    /// Simulate batch connection of multiple devices
    func simulateBatchConnection(deviceIds: [UUID]) {
        for deviceId in deviceIds {
            simulateConnection(to: deviceId)
        }
    }

    /// Simulate batch disconnection of multiple devices
    func simulateBatchDisconnection(deviceIds: [UUID], error: Error? = nil) {
        for deviceId in deviceIds {
            simulateDisconnection(from: deviceId, error: error)
        }
    }

    /// Simulate intermittent connectivity (connects then disconnects after delay)
    func simulateIntermittentConnection(to peripheralId: UUID, disconnectAfter delay: TimeInterval, error: Error? = nil) {
        simulateConnection(to: peripheralId)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.simulateDisconnection(from: peripheralId, error: error)
        }
    }

    /// Simulate rapid data stream from a device
    /// Note: Uses simulateCharacteristicDataReceived which doesn't require actual CBCharacteristic
    func simulateRapidDataStream(from peripheralId: UUID, count: Int, interval: TimeInterval = 0.01) {
        guard let peripheral = discoveredPeripherals[peripheralId] else { return }

        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + (interval * Double(i))) { [weak self] in
                let mockData = Data([UInt8(i & 0xFF), UInt8((i >> 8) & 0xFF)])
                // Simulate data received event
                self?.simulateCharacteristicDataReceived(peripheral: peripheral, data: mockData)
            }
        }
    }

    /// Simulate characteristic data received without requiring actual CBCharacteristic
    /// Creates a mock characteristic using runtime allocation
    func simulateCharacteristicDataReceived(peripheral: CBPeripheral, data: Data) {
        // Create mock characteristic using runtime allocation (same pattern as MockPeripheralFactory)
        if let mockCharacteristic = class_createInstance(CBCharacteristic.self, 0) as? CBCharacteristic {
            eventSubject.send(.characteristicUpdated(
                peripheral: peripheral,
                characteristic: mockCharacteristic,
                data: data
            ))
        }
    }

    /// Internal helper to discover pre-configured devices
    private func simulateDiscoveryOfConfiguredDevices() {
        guard isScanning else { return }

        for (_, peripheral) in discoveredPeripherals {
            eventSubject.send(.deviceDiscovered(
                peripheral: peripheral,
                name: peripheral.name ?? "Unknown",
                rssi: -50,
                advertisementData: [:]
            ))
        }
    }
}

// MARK: - Mock Peripheral Factory

/// Factory for creating mock CBPeripheral instances using Objective-C runtime
/// CoreBluetooth classes can't be directly subclassed, so we use runtime allocation
enum MockPeripheralFactory {
    /// Storage for mock peripheral properties (keyed by identifier)
    private static var mockIdentifiers: [ObjectIdentifier: UUID] = [:]
    private static var mockNames: [ObjectIdentifier: String?] = [:]
    private static var mockStates: [ObjectIdentifier: CBPeripheralState] = [:]

    /// Create a mock peripheral for testing
    static func create(identifier: UUID, name: String?) -> CBPeripheral {
        // Allocate CBPeripheral without calling init using runtime
        guard let instance = class_createInstance(CBPeripheral.self, 0) as? CBPeripheral else {
            fatalError("Failed to create mock peripheral")
        }

        // Store mock values in static dictionaries
        let objectId = ObjectIdentifier(instance)
        mockIdentifiers[objectId] = identifier
        mockNames[objectId] = name
        mockStates[objectId] = .disconnected

        return instance
    }

    /// Get stored identifier for a mock peripheral
    static func getIdentifier(for peripheral: CBPeripheral) -> UUID? {
        return mockIdentifiers[ObjectIdentifier(peripheral)]
    }

    /// Get stored name for a mock peripheral
    static func getName(for peripheral: CBPeripheral) -> String? {
        return mockNames[ObjectIdentifier(peripheral)] ?? nil
    }

    /// Set state for a mock peripheral
    static func setState(_ state: CBPeripheralState, for peripheral: CBPeripheral) {
        mockStates[ObjectIdentifier(peripheral)] = state
    }

    /// Clean up mock peripheral data
    static func cleanup(peripheral: CBPeripheral) {
        let objectId = ObjectIdentifier(peripheral)
        mockIdentifiers.removeValue(forKey: objectId)
        mockNames.removeValue(forKey: objectId)
        mockStates.removeValue(forKey: objectId)
    }

    /// Reset all mock data
    static func reset() {
        mockIdentifiers.removeAll()
        mockNames.removeAll()
        mockStates.removeAll()
    }
}

/// Type alias for compatibility with existing code
typealias MockPeripheral = CBPeripheral

/// Extension to make mock peripheral creation easier
extension CBPeripheral {
    /// Create a mock peripheral for testing
    static func mock(identifier: UUID, name: String?) -> CBPeripheral {
        return MockPeripheralFactory.create(identifier: identifier, name: name)
    }
}

// MARK: - Mock Characteristic

/// Mock CBCharacteristic for testing
/// Note: CBCharacteristic can't be directly instantiated, use MockCharacteristicData instead
struct MockCharacteristicData {
    let uuid: CBUUID
    let properties: CBCharacteristicProperties

    init(uuid: CBUUID, properties: CBCharacteristicProperties = [.read, .write, .notify]) {
        self.uuid = uuid
        self.properties = properties
    }
}

// MARK: - Mock Service

/// Mock CBService for testing
/// Note: CBService can't be directly instantiated, use MockServiceData instead
struct MockServiceData {
    let uuid: CBUUID
    let characteristics: [MockCharacteristicData]

    init(uuid: CBUUID, characteristics: [MockCharacteristicData] = []) {
        self.uuid = uuid
        self.characteristics = characteristics
    }
}
