//
//  BLEDeviceProtocol.swift
//  OralableApp
//
//  Created: November 3, 2025
//  Updated: November 10, 2025 - Consolidated DeviceError enum
//  Protocol defining interface for all BLE devices
//

import Foundation
import CoreBluetooth
import Combine
import OralableCore

/// Protocol that all BLE devices must implement
protocol BLEDeviceProtocol: AnyObject {
    
    // MARK: - Device Information
    
    /// Device information structure
    var deviceInfo: DeviceInfo { get }
    
    /// Device type
    var deviceType: DeviceType { get }
    
    /// Device name
    var name: String { get }
    
    /// BLE peripheral
    var peripheral: CBPeripheral? { get }
    
    // MARK: - Connection State
    
    /// Current connection state
    var connectionState: DeviceConnectionState { get }
    
    /// Whether device is currently connected
    var isConnected: Bool { get }
    
    /// Signal strength (RSSI)
    var signalStrength: Int? { get }
    
    // MARK: - Battery & System Info
    
    /// Current battery level (0-100)
    var batteryLevel: Int? { get }
    
    /// Firmware version
    var firmwareVersion: String? { get }
    
    /// Hardware version
    var hardwareVersion: String? { get }
    
    // MARK: - Sensor Data

    /// Publisher for sensor readings
    var sensorReadings: AnyPublisher<SensorReading, Never> { get }

    /// Publisher for sensor readings (legacy compatibility)
    var sensorReadingsPublisher: AnyPublisher<SensorReading, Never> { get }

    /// Batch publisher for efficient multi-reading delivery (preferred)
    var sensorReadingsBatch: AnyPublisher<[SensorReading], Never> { get }

    /// Latest readings by sensor type
    var latestReadings: [SensorType: SensorReading] { get }
    
    /// List of supported sensors
    var supportedSensors: [SensorType] { get }
    
    // MARK: - Connection Management
    
    /// Connect to the device
    func connect() async throws
    
    /// Disconnect from the device
    func disconnect() async
    
    /// Check if device is available
    func isAvailable() -> Bool
    
    // MARK: - Data Operations
    
    /// Start streaming sensor data
    func startDataStream() async throws
    
    /// Start data collection (legacy compatibility)
    func startDataCollection() async throws
    
    /// Stop streaming sensor data
    func stopDataStream() async
    
    /// Stop data collection (legacy compatibility)
    func stopDataCollection() async
    
    /// Request current sensor reading
    func requestReading(for sensorType: SensorType) async throws -> SensorReading?
    
    /// Parse raw BLE data into sensor readings
    func parseData(_ data: Data, from characteristic: CBCharacteristic) -> [SensorReading]
    
    // MARK: - Device Control
    
    /// Send command to device
    func sendCommand(_ command: DeviceCommand) async throws
    
    /// Update device configuration
    func updateConfiguration(_ config: DeviceConfiguration) async throws
    
    /// Request device information update
    func updateDeviceInfo() async throws
    
    // MARK: - Service Discovery (Added Day 2)
    
    /// Discover BLE services
    func discoverServices() async throws
    
    /// Discover BLE characteristics
    func discoverCharacteristics() async throws
    
    /// Enable notifications for data streaming
    func enableNotifications() async throws
}

// MARK: - Device Command

/// Commands that can be sent to devices
enum DeviceCommand {
    case startSensors
    case stopSensors
    case reset
    case calibrate
    case setSamplingRate(Hz: Int)
    case enableSensor(SensorType)
    case disableSensor(SensorType)
    case requestBatteryLevel
    case requestFirmwareVersion
    
    var rawValue: String {
        switch self {
        case .startSensors:
            return "START"
        case .stopSensors:
            return "STOP"
        case .reset:
            return "RESET"
        case .calibrate:
            return "CALIBRATE"
        case .setSamplingRate(let hz):
            return "RATE:\(hz)"
        case .enableSensor(let type):
            return "ENABLE:\(type.rawValue)"
        case .disableSensor(let type):
            return "DISABLE:\(type.rawValue)"
        case .requestBatteryLevel:
            return "BATTERY?"
        case .requestFirmwareVersion:
            return "VERSION?"
        }
    }
}

// MARK: - Device Configuration

/// Configuration settings for devices
struct DeviceConfiguration {
    
    /// Sampling rate in Hz
    var samplingRate: Int
    
    /// Enabled sensors
    var enabledSensors: Set<SensorType>
    
    /// Auto-reconnect on disconnect
    var autoReconnect: Bool
    
    /// Notification preferences
    var notificationsEnabled: Bool
    
    /// Data buffer size
    var bufferSize: Int
    
    // MARK: - Default Configurations
    
    static let defaultOralable = DeviceConfiguration(
        samplingRate: 50,
        enabledSensors: [
            .ppgRed,
            .ppgInfrared,
            .ppgGreen,
            .accelerometerX,
            .accelerometerY,
            .accelerometerZ,
            .temperature,
            .battery
        ],
        autoReconnect: true,
        notificationsEnabled: true,
        bufferSize: 100
    )
    
    static let defaultANR = DeviceConfiguration(
        samplingRate: 100,
        enabledSensors: [
            .emg,
            .battery
        ],
        autoReconnect: true,
        notificationsEnabled: true,
        bufferSize: 200
    )
}

// MARK: - Protocol Extension (Default Implementations)

extension BLEDeviceProtocol {
    
    /// Check if specific sensor is supported
    func supports(sensor: SensorType) -> Bool {
        supportedSensors.contains(sensor)
    }
    
    /// Get latest reading for sensor type
    func latestReading(for sensorType: SensorType) -> SensorReading? {
        latestReadings[sensorType]
    }
    
    /// Check if device is streaming data
    var isStreaming: Bool {
        isConnected && connectionState == .connected
    }
    
    /// Default implementation for sensorReadingsPublisher (legacy compatibility)
    var sensorReadingsPublisher: AnyPublisher<SensorReading, Never> {
        sensorReadings
    }
    
    /// Default implementation for startDataCollection (legacy compatibility)
    func startDataCollection() async throws {
        try await startDataStream()
    }
    
    /// Default implementation for stopDataCollection (legacy compatibility)
    func stopDataCollection() async {
        await stopDataStream()
    }
}

// MARK: - Preview Helper

#if DEBUG

/// Mock device for testing
class MockBLEDevice: BLEDeviceProtocol {
    
    var deviceInfo: DeviceInfo
    var deviceType: DeviceType
    var name: String
    var peripheral: CBPeripheral?
    var connectionState: DeviceConnectionState = .disconnected
    var signalStrength: Int? = -55
    var batteryLevel: Int? = 85
    var firmwareVersion: String? = "1.0.0"
    var hardwareVersion: String? = "2.0"
    
    private let sensorReadingsSubject = PassthroughSubject<SensorReading, Never>()
    var sensorReadings: AnyPublisher<SensorReading, Never> {
        sensorReadingsSubject.eraseToAnyPublisher()
    }

    private let sensorReadingsBatchSubject = PassthroughSubject<[SensorReading], Never>()
    var sensorReadingsBatch: AnyPublisher<[SensorReading], Never> {
        sensorReadingsBatchSubject.eraseToAnyPublisher()
    }

    var latestReadings: [SensorType: SensorReading] = [:]
    var supportedSensors: [SensorType]
    
    var isConnected: Bool {
        connectionState == .connected
    }
    
    init(type: DeviceType) {
        self.deviceType = type
        self.name = type.displayName
        self.deviceInfo = DeviceInfo.demo(type: type)
        self.supportedSensors = type.defaultSensors
    }
    
    func connect() async throws {
        connectionState = .connecting
        try await Task.sleep(nanoseconds: 500_000_000)
        connectionState = .connected
    }
    
    func disconnect() async {
        connectionState = .disconnecting
        try? await Task.sleep(nanoseconds: 200_000_000)
        connectionState = .disconnected
    }
    
    func isAvailable() -> Bool {
        true
    }
    
    func startDataStream() async throws {
        guard isConnected else { throw DeviceError.notConnected("Mock device not connected") }
        // Simulate data streaming
    }

    func stopDataStream() async {
        // Stop streaming
    }

    func requestReading(for sensorType: SensorType) async throws -> SensorReading? {
        guard isConnected else { throw DeviceError.notConnected("Mock device not connected") }
        return SensorReading.mock(sensorType: sensorType)
    }

    func parseData(_ data: Data, from characteristic: CBCharacteristic) -> [SensorReading] {
        []
    }

    func sendCommand(_ command: DeviceCommand) async throws {
        guard isConnected else { throw DeviceError.notConnected("Mock device not connected") }
    }

    func updateConfiguration(_ config: DeviceConfiguration) async throws {
        guard isConnected else { throw DeviceError.notConnected("Mock device not connected") }
    }

    func updateDeviceInfo() async throws {
        guard isConnected else { throw DeviceError.notConnected("Mock device not connected") }
    }
    
    // MARK: - Service Discovery (Added Day 2)
    
    func discoverServices() async throws {
        // Mock implementation - simulate delay
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    func discoverCharacteristics() async throws {
        // Mock implementation - simulate delay
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    func enableNotifications() async throws {
        // Mock implementation - simulate delay
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
}

#endif
