//
//  BLEService.swift
//  OralableApp
//
//  Created: December 15, 2025
//  Purpose: Protocol abstraction for BLE service operations
//  Enables dependency injection, mocking, and testing
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - BLE Connection State

/// Represents the connection state of a BLE device
enum BLEConnectionState: String, Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting

    var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting..."
        }
    }
}

// MARK: - BLE Service Events

/// Events emitted by the BLE service
enum BLEServiceEvent {
    case deviceDiscovered(peripheral: CBPeripheral, name: String, rssi: Int, advertisementData: [String: Any])
    case deviceConnected(peripheral: CBPeripheral)
    case deviceDisconnected(peripheral: CBPeripheral, error: Error?)
    case bluetoothStateChanged(state: CBManagerState)
    case characteristicUpdated(peripheral: CBPeripheral, characteristic: CBCharacteristic, data: Data)
    case characteristicWritten(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?)
    case servicesDiscovered(peripheral: CBPeripheral, services: [CBService]?, error: Error?)
    case characteristicsDiscovered(peripheral: CBPeripheral, service: CBService, characteristics: [CBCharacteristic]?, error: Error?)
    case error(BLEError)
}

// MARK: - BLE Service Protocol

/// Protocol defining the BLE service interface for scanning, connection, and data operations
/// This abstraction allows for dependency injection and easy mocking in tests
protocol BLEService: AnyObject {

    // MARK: - State

    /// Current Bluetooth state
    var bluetoothState: CBManagerState { get }

    /// Whether Bluetooth is ready for operations
    var isReady: Bool { get }

    /// Whether currently scanning for devices
    var isScanning: Bool { get }

    /// Event publisher for BLE service events
    var eventPublisher: AnyPublisher<BLEServiceEvent, Never> { get }

    // MARK: - Scanning

    /// Start scanning for BLE peripherals
    /// - Parameter services: Optional array of service UUIDs to filter by
    func startScanning(services: [CBUUID]?)

    /// Stop scanning for peripherals
    func stopScanning()

    // MARK: - Connection Management

    /// Connect to a peripheral
    /// - Parameter peripheral: The peripheral to connect to
    func connect(to peripheral: CBPeripheral)

    /// Disconnect from a peripheral
    /// - Parameter peripheral: The peripheral to disconnect from
    func disconnect(from peripheral: CBPeripheral)

    /// Disconnect from all connected peripherals
    func disconnectAll()

    // MARK: - Read/Write Operations

    /// Read value from a characteristic
    /// - Parameters:
    ///   - characteristic: The characteristic to read from
    ///   - peripheral: The peripheral containing the characteristic
    func readValue(from characteristic: CBCharacteristic, on peripheral: CBPeripheral)

    /// Write value to a characteristic
    /// - Parameters:
    ///   - data: The data to write
    ///   - characteristic: The characteristic to write to
    ///   - peripheral: The peripheral containing the characteristic
    ///   - type: The write type (with or without response)
    func writeValue(_ data: Data, to characteristic: CBCharacteristic, on peripheral: CBPeripheral, type: CBCharacteristicWriteType)

    /// Enable/disable notifications for a characteristic
    /// - Parameters:
    ///   - enabled: Whether to enable notifications
    ///   - characteristic: The characteristic to set notifications for
    ///   - peripheral: The peripheral containing the characteristic
    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic, on peripheral: CBPeripheral)

    // MARK: - Service Discovery

    /// Discover services on a peripheral
    /// - Parameters:
    ///   - services: Optional array of service UUIDs to discover (nil discovers all)
    ///   - peripheral: The peripheral to discover services on
    func discoverServices(_ services: [CBUUID]?, on peripheral: CBPeripheral)

    /// Discover characteristics for a service
    /// - Parameters:
    ///   - characteristics: Optional array of characteristic UUIDs to discover (nil discovers all)
    ///   - service: The service to discover characteristics for
    ///   - peripheral: The peripheral containing the service
    func discoverCharacteristics(_ characteristics: [CBUUID]?, for service: CBService, on peripheral: CBPeripheral)

    // MARK: - Utility

    /// Execute an operation when Bluetooth is ready
    /// - Parameter operation: The operation to execute
    func whenReady(_ operation: @escaping () -> Void)

    /// Retrieve peripherals with the given identifiers
    /// - Parameter identifiers: The peripheral identifiers to retrieve
    /// - Returns: Array of peripherals matching the identifiers
    func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral]

    // MARK: - Throwing Variants (Optional)

    /// Validate Bluetooth state before operations (throws if not ready)
    /// - Throws: BLEError if Bluetooth is not in a valid state
    func validateBluetoothState() throws

    /// Start scanning with validation
    /// - Parameter services: Optional array of service UUIDs to filter by
    /// - Throws: BLEError if Bluetooth is not ready or already scanning
    func startScanningWithValidation(services: [CBUUID]?) throws

    /// Connect with validation
    /// - Parameter peripheral: The peripheral to connect to
    /// - Throws: BLEError if Bluetooth is not ready
    func connectWithValidation(to peripheral: CBPeripheral) throws
}

// MARK: - Default Implementations

extension BLEService {

    /// Convenience method to start scanning without service filter
    func startScanning() {
        startScanning(services: nil)
    }

    /// Convenience method to write with response
    func writeValue(_ data: Data, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        writeValue(data, to: characteristic, on: peripheral, type: .withResponse)
    }

    /// Convenience method to discover all services
    func discoverServices(on peripheral: CBPeripheral) {
        discoverServices(nil, on: peripheral)
    }

    /// Convenience method to discover all characteristics
    func discoverCharacteristics(for service: CBService, on peripheral: CBPeripheral) {
        discoverCharacteristics(nil, for: service, on: peripheral)
    }

    // MARK: - Throwing Method Default Implementations

    /// Default implementation validates Bluetooth state
    func validateBluetoothState() throws {
        switch bluetoothState {
        case .poweredOn:
            return // Valid state
        case .poweredOff:
            throw BLEError.bluetoothNotReady(state: bluetoothState)
        case .unauthorized:
            throw BLEError.bluetoothUnauthorized
        case .unsupported:
            throw BLEError.bluetoothUnsupported
        case .resetting:
            throw BLEError.bluetoothResetting
        case .unknown:
            throw BLEError.bluetoothNotReady(state: bluetoothState)
        @unknown default:
            throw BLEError.bluetoothNotReady(state: bluetoothState)
        }
    }

    /// Default implementation validates state then starts scanning
    func startScanningWithValidation(services: [CBUUID]?) throws {
        try validateBluetoothState()
        if isScanning {
            throw BLEError.alreadyScanning
        }
        startScanning(services: services)
    }

    /// Default implementation validates state then connects
    func connectWithValidation(to peripheral: CBPeripheral) throws {
        try validateBluetoothState()
        connect(to: peripheral)
    }

    // MARK: - Error Conversion Helpers

    /// Convert a generic Error to BLEError if possible
    func toBLEError(_ error: Error?) -> BLEError? {
        guard let error = error else { return nil }
        if let bleError = error as? BLEError {
            return bleError
        }
        return BLEError.internalError(reason: error.localizedDescription, underlyingError: error)
    }
}

// MARK: - BLE Error

/// Comprehensive error types for BLE operations
/// Provides structured error handling across the BLE stack
enum BLEError: Error, LocalizedError, Equatable {

    // MARK: - Bluetooth State Errors

    /// Bluetooth is not powered on
    case bluetoothNotReady(state: CBManagerState)

    /// Bluetooth access is not authorized by the user
    case bluetoothUnauthorized

    /// Bluetooth is not supported on this device
    case bluetoothUnsupported

    /// Bluetooth is currently resetting
    case bluetoothResetting

    // MARK: - Connection Errors

    /// Failed to connect to peripheral
    case connectionFailed(peripheralId: UUID, reason: String?)

    /// Connection timed out before completing
    case connectionTimeout(peripheralId: UUID, timeoutSeconds: TimeInterval)

    /// Peripheral disconnected unexpectedly
    case unexpectedDisconnection(peripheralId: UUID, reason: String?)

    /// Peripheral not found or no longer available
    case peripheralNotFound(peripheralId: UUID)

    /// Peripheral is not in connected state
    case peripheralNotConnected(peripheralId: UUID)

    /// Maximum connection attempts exceeded
    case maxReconnectionAttemptsExceeded(peripheralId: UUID, attempts: Int)

    // MARK: - Discovery Errors

    /// Service not found on peripheral
    case serviceNotFound(serviceUUID: CBUUID, peripheralId: UUID)

    /// Characteristic not found in service
    case characteristicNotFound(characteristicUUID: CBUUID, serviceUUID: CBUUID)

    /// Service discovery failed
    case serviceDiscoveryFailed(peripheralId: UUID, reason: String?)

    /// Characteristic discovery failed
    case characteristicDiscoveryFailed(serviceUUID: CBUUID, reason: String?)

    // MARK: - Data Transfer Errors

    /// Write operation failed
    case writeFailed(characteristicUUID: CBUUID, reason: String?)

    /// Read operation failed
    case readFailed(characteristicUUID: CBUUID, reason: String?)

    /// Notification setup failed
    case notificationSetupFailed(characteristicUUID: CBUUID, reason: String?)

    /// Data received was corrupted or malformed
    case dataCorrupted(description: String)

    /// Data validation failed
    case dataValidationFailed(expected: String, received: String)

    /// Invalid data format
    case invalidDataFormat(description: String)

    // MARK: - Operation Errors

    /// Operation timed out
    case timeout(operation: String, timeoutSeconds: TimeInterval)

    /// Operation was cancelled
    case cancelled(operation: String)

    /// Operation not permitted in current state
    case operationNotPermitted(operation: String, currentState: String)

    /// Already scanning
    case alreadyScanning

    /// Not currently scanning
    case notScanning

    // MARK: - Internal Errors

    /// Internal error with underlying cause
    case internalError(reason: String, underlyingError: Error?)

    /// Unknown error
    case unknown(description: String)

    // MARK: - LocalizedError Conformance

    var errorDescription: String? {
        switch self {
        // Bluetooth State
        case .bluetoothNotReady(let state):
            return "Bluetooth is not ready (state: \(stateDescription(state)))"
        case .bluetoothUnauthorized:
            return "Bluetooth access is not authorized. Please enable Bluetooth permission in Settings."
        case .bluetoothUnsupported:
            return "Bluetooth Low Energy is not supported on this device"
        case .bluetoothResetting:
            return "Bluetooth is resetting. Please wait and try again."

        // Connection
        case .connectionFailed(_, let reason):
            return "Connection failed: \(reason ?? "Unknown reason")"
        case .connectionTimeout(_, let timeout):
            return "Connection timed out after \(Int(timeout)) seconds"
        case .unexpectedDisconnection(_, let reason):
            return "Device disconnected unexpectedly: \(reason ?? "Unknown reason")"
        case .peripheralNotFound:
            return "Device not found. Make sure it's powered on and nearby."
        case .peripheralNotConnected:
            return "Device is not connected"
        case .maxReconnectionAttemptsExceeded(_, let attempts):
            return "Failed to reconnect after \(attempts) attempts"

        // Discovery
        case .serviceNotFound(let uuid, _):
            return "Required service not found: \(uuid.uuidString)"
        case .characteristicNotFound(let uuid, _):
            return "Required characteristic not found: \(uuid.uuidString)"
        case .serviceDiscoveryFailed(_, let reason):
            return "Service discovery failed: \(reason ?? "Unknown reason")"
        case .characteristicDiscoveryFailed(_, let reason):
            return "Characteristic discovery failed: \(reason ?? "Unknown reason")"

        // Data Transfer
        case .writeFailed(_, let reason):
            return "Write operation failed: \(reason ?? "Unknown reason")"
        case .readFailed(_, let reason):
            return "Read operation failed: \(reason ?? "Unknown reason")"
        case .notificationSetupFailed(_, let reason):
            return "Failed to enable notifications: \(reason ?? "Unknown reason")"
        case .dataCorrupted(let description):
            return "Data corrupted: \(description)"
        case .dataValidationFailed(let expected, let received):
            return "Data validation failed. Expected: \(expected), Received: \(received)"
        case .invalidDataFormat(let description):
            return "Invalid data format: \(description)"

        // Operation
        case .timeout(let operation, let timeout):
            return "\(operation) timed out after \(Int(timeout)) seconds"
        case .cancelled(let operation):
            return "\(operation) was cancelled"
        case .operationNotPermitted(let operation, let state):
            return "\(operation) not permitted in \(state) state"
        case .alreadyScanning:
            return "Already scanning for devices"
        case .notScanning:
            return "Not currently scanning"

        // Internal
        case .internalError(let reason, _):
            return "Internal error: \(reason)"
        case .unknown(let description):
            return "Unknown error: \(description)"
        }
    }

    var failureReason: String? {
        switch self {
        case .bluetoothNotReady:
            return "Bluetooth must be powered on to perform this operation"
        case .bluetoothUnauthorized:
            return "App does not have permission to use Bluetooth"
        case .connectionTimeout:
            return "The device may be out of range or powered off"
        case .dataCorrupted:
            return "The data received from the device was invalid"
        default:
            return nil
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .bluetoothNotReady:
            return "Turn on Bluetooth in Settings or Control Center"
        case .bluetoothUnauthorized:
            return "Go to Settings > Privacy > Bluetooth and enable access for this app"
        case .connectionFailed, .connectionTimeout:
            return "Move closer to the device and try again"
        case .peripheralNotFound:
            return "Make sure the device is powered on and in pairing mode"
        case .maxReconnectionAttemptsExceeded:
            return "Try manually reconnecting or restarting the device"
        case .dataCorrupted, .dataValidationFailed:
            return "Try disconnecting and reconnecting to the device"
        default:
            return nil
        }
    }

    // MARK: - Error Classification

    /// Whether this error is recoverable through retry
    var isRecoverable: Bool {
        switch self {
        case .connectionTimeout, .unexpectedDisconnection, .timeout,
             .bluetoothResetting, .dataCorrupted:
            return true
        case .bluetoothUnauthorized, .bluetoothUnsupported,
             .maxReconnectionAttemptsExceeded, .cancelled:
            return false
        default:
            return true
        }
    }

    /// Whether this error should trigger a reconnection attempt
    var shouldTriggerReconnection: Bool {
        switch self {
        case .unexpectedDisconnection, .connectionTimeout:
            return true
        default:
            return false
        }
    }

    /// Severity level for logging purposes
    var severity: BLEErrorSeverity {
        switch self {
        case .alreadyScanning, .notScanning, .cancelled:
            return .info
        case .bluetoothResetting, .timeout, .connectionTimeout:
            return .warning
        case .bluetoothNotReady, .connectionFailed, .unexpectedDisconnection,
             .writeFailed, .readFailed, .dataCorrupted:
            return .error
        case .bluetoothUnauthorized, .bluetoothUnsupported, .internalError:
            return .critical
        default:
            return .warning
        }
    }

    // MARK: - Equatable Conformance

    static func == (lhs: BLEError, rhs: BLEError) -> Bool {
        switch (lhs, rhs) {
        case (.bluetoothNotReady(let s1), .bluetoothNotReady(let s2)):
            return s1 == s2
        case (.bluetoothUnauthorized, .bluetoothUnauthorized),
             (.bluetoothUnsupported, .bluetoothUnsupported),
             (.bluetoothResetting, .bluetoothResetting),
             (.alreadyScanning, .alreadyScanning),
             (.notScanning, .notScanning):
            return true
        case (.connectionFailed(let id1, _), .connectionFailed(let id2, _)):
            return id1 == id2
        case (.connectionTimeout(let id1, _), .connectionTimeout(let id2, _)):
            return id1 == id2
        case (.peripheralNotFound(let id1), .peripheralNotFound(let id2)):
            return id1 == id2
        case (.peripheralNotConnected(let id1), .peripheralNotConnected(let id2)):
            return id1 == id2
        case (.timeout(let op1, _), .timeout(let op2, _)):
            return op1 == op2
        case (.cancelled(let op1), .cancelled(let op2)):
            return op1 == op2
        default:
            return false
        }
    }

    // MARK: - Helper Methods

    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "Unknown"
        case .resetting: return "Resetting"
        case .unsupported: return "Unsupported"
        case .unauthorized: return "Unauthorized"
        case .poweredOff: return "Powered Off"
        case .poweredOn: return "Powered On"
        @unknown default: return "Unknown (\(state.rawValue))"
        }
    }
}

// MARK: - Error Severity

/// Severity levels for BLE errors
enum BLEErrorSeverity: Int, Comparable {
    case info = 0
    case warning = 1
    case error = 2
    case critical = 3

    static func < (lhs: BLEErrorSeverity, rhs: BLEErrorSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Legacy Alias

/// Type alias for backward compatibility
typealias BLEServiceError = BLEError
