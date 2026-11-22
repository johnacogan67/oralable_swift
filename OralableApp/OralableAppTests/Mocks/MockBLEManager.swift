//
//  MockBLEManager.swift
//  OralableAppTests
//
//  Created: Refactoring Phase 1
//  Purpose: Mock BLE manager for testing
//

import Foundation
import Combine
import CoreBluetooth
@testable import MAMDiagnostics

/// Mock CBPeripheral for testing
class MockCBPeripheral: CBPeripheral {
    // Mock peripheral provides a fixed identifier
    override var identifier: UUID {
        return UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    }

    override var name: String? {
        return "Mock Peripheral"
    }
}

/// Mock BLE Manager for unit testing
/// Allows tests to simulate BLE behavior without actual Bluetooth hardware
@MainActor
class MockBLEManager: BLEManagerProtocol {
    // MARK: - Connection State
    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    @Published var deviceName: String = "Mock Device"
    @Published var connectionState: String = "disconnected"
    @Published var deviceUUID: UUID? = UUID()

    // MARK: - Sensor Readings
    @Published var heartRate: Int = 72
    @Published var spO2: Int = 98
    @Published var heartRateQuality: Double = 0.95
    @Published var temperature: Double = 36.5
    @Published var batteryLevel: Double = 85.0
    @Published var accelX: Double = 0.0
    @Published var accelY: Double = 0.0
    @Published var accelZ: Double = 0.0

    // MARK: - PPG Data
    @Published var ppgRedValue: Double = 1000.0
    @Published var ppgIRValue: Double = 1200.0
    @Published var ppgGreenValue: Double = 900.0

    // MARK: - Recording State
    @Published var isRecording: Bool = false

    // MARK: - Device State
    @Published var deviceState: DeviceStateResult? = nil

    // MARK: - Test Helpers
    var startScanningCalled = false
    var stopScanningCalled = false
    var connectCalled = false
    var disconnectCalled = false
    var startRecordingCalled = false
    var stopRecordingCalled = false
    var clearHistoryCalled = false

    var connectError: Error?
    var recordingError: Error?

    // MARK: - Actions
    func startScanning() {
        startScanningCalled = true
        isScanning = true
    }

    func stopScanning() {
        stopScanningCalled = true
        isScanning = false
    }

    func connect(to peripheral: CBPeripheral) {
        connectCalled = true
        isConnected = true
        connectionState = "connected"
        deviceUUID = peripheral.identifier
    }

    func disconnect() {
        disconnectCalled = true
        isConnected = false
        connectionState = "disconnected"
    }

    func startRecording() {
        startRecordingCalled = true
        isRecording = true
    }

    func stopRecording() {
        stopRecordingCalled = true
        isRecording = false
    }

    func clearHistory() {
        clearHistoryCalled = true
    }

    // MARK: - Publishers
    var isConnectedPublisher: Published<Bool>.Publisher { $isConnected }
    var isScanningPublisher: Published<Bool>.Publisher { $isScanning }
    var deviceNamePublisher: Published<String>.Publisher { $deviceName }
    var heartRatePublisher: Published<Int>.Publisher { $heartRate }
    var spO2Publisher: Published<Int>.Publisher { $spO2 }
    var heartRateQualityPublisher: Published<Double>.Publisher { $heartRateQuality }
    var temperaturePublisher: Published<Double>.Publisher { $temperature }
    var batteryLevelPublisher: Published<Double>.Publisher { $batteryLevel }
    var ppgRedValuePublisher: Published<Double>.Publisher { $ppgRedValue }
    var ppgIRValuePublisher: Published<Double>.Publisher { $ppgIRValue }
    var ppgGreenValuePublisher: Published<Double>.Publisher { $ppgGreenValue }
    var accelXPublisher: Published<Double>.Publisher { $accelX }
    var accelYPublisher: Published<Double>.Publisher { $accelY }
    var accelZPublisher: Published<Double>.Publisher { $accelZ }
    var isRecordingPublisher: Published<Bool>.Publisher { $isRecording }
    var deviceStatePublisher: Published<DeviceStateResult?>.Publisher { $deviceState }

    // MARK: - Test Simulation Methods

    /// Simulate connection to a device
    func simulateConnection() {
        isConnected = true
        connectionState = "connected"
        deviceName = "Simulated Device"
    }

    /// Simulate disconnection
    func simulateDisconnection() {
        isConnected = false
        connectionState = "disconnected"
    }

    /// Simulate sensor data update
    func simulateSensorUpdate(hr: Int, spo2: Int, temp: Double, battery: Double) {
        heartRate = hr
        spO2 = spo2
        temperature = temp
        batteryLevel = battery
    }

    /// Simulate device state change
    func simulateDeviceState(_ state: DeviceStateResult) {
        deviceState = state
    }

    /// Reset all test flags
    func reset() {
        startScanningCalled = false
        stopScanningCalled = false
        connectCalled = false
        disconnectCalled = false
        startRecordingCalled = false
        stopRecordingCalled = false
        clearHistoryCalled = false
        connectError = nil
        recordingError = nil
    }
}
