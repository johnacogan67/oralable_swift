//
//  BLEDataPublisher.swift
//  OralableApp
//
//  Created: November 19, 2025
//  Responsibility: Manage @Published properties and UI state for BLE operations
//  - All @Published properties for UI bindings
//  - Connection state management
//  - Device discovery tracking
//  - Logging and error state
//  - MainActor isolation for UI updates
//

import Foundation
import Combine
import CoreBluetooth
import OralableCore

/// Manages all published properties and UI state for BLE operations
@MainActor
class BLEDataPublisher: ObservableObject {

    // MARK: - Discovered Device Info

    struct DiscoveredDeviceInfo: Identifiable {
        let id: UUID
        let name: String
        let peripheral: CBPeripheral
        var rssi: Int
    }

    // MARK: - Connection State

    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    @Published var deviceName: String = "No Device"
    @Published var connectedDevice: CBPeripheral?
    @Published var connectionState: String = "disconnected"
    @Published var deviceUUID: UUID? = nil
    @Published var rssi: Int = -50

    // MARK: - Device Discovery

    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var discoveredDevicesInfo: [DiscoveredDeviceInfo] = []
    @Published var discoveredServices: [String] = []

    // MARK: - Device State

    @Published var deviceState: DeviceStateResult?

    // MARK: - Recording State

    @Published var isRecording: Bool = false
    @Published var packetsReceived: Int = 0

    // MARK: - Error and Logging

    @Published var lastError: String? = nil
    @Published var logMessages: [LogMessage] = []

    // MARK: - Computed Properties

    var connectionStatus: String {
        if isConnected {
            return "Connected"
        } else if isScanning {
            return "Scanning..."
        } else {
            return "Disconnected"
        }
    }

    var sensorData: (batteryLevel: Int, firmwareVersion: String, deviceUUID: UInt64) {
        let battery = 0  // Will be provided by SensorDataProcessor
        let uuid: UInt64 = UInt64(connectedDevice?.identifier.uuidString.hash.magnitude ?? 0)
        return (battery, "1.0.0", uuid)
    }

    // MARK: - Initialization

    init() {
        Logger.shared.info("[BLEDataPublisher] Initialized")
    }

    // MARK: - Device Discovery Management

    /// Handle discovered device from BLE manager
    func handleDeviceDiscovered(peripheral: CBPeripheral, name: String, rssi: Int) {
        // Check if we already have this device
        if let index = discoveredDevicesInfo.firstIndex(where: { $0.id == peripheral.identifier }) {
            // Update RSSI for existing device
            discoveredDevicesInfo[index].rssi = rssi
            Logger.shared.debug("[BLEDataPublisher] Updated device: \(name) RSSI: \(rssi) dBm")
        } else {
            // Add new device
            let deviceInfo = DiscoveredDeviceInfo(
                id: peripheral.identifier,
                name: name,
                peripheral: peripheral,
                rssi: rssi
            )
            discoveredDevicesInfo.append(deviceInfo)
            Logger.shared.info("[BLEDataPublisher] Discovered new device: \(name) RSSI: \(rssi) dBm")
        }

        // Update legacy discoveredDevices array
        discoveredDevices = discoveredDevicesInfo.map { $0.peripheral }

        addLog("Found device: \(name) (\(rssi) dBm)")
    }

    /// Clear all discovered devices
    func clearDiscoveredDevices() {
        discoveredDevices.removeAll()
        discoveredDevicesInfo.removeAll()
        Logger.shared.info("[BLEDataPublisher] Cleared discovered devices")
    }

    // MARK: - Connection State Management

    /// Update connection state
    func updateConnectionState(isConnected: Bool, deviceName: String? = nil) {
        self.isConnected = isConnected
        if let name = deviceName {
            self.deviceName = name
        }
        connectionState = isConnected ? "connected" : "disconnected"
        Logger.shared.info("[BLEDataPublisher] Connection state: \(connectionState) | Device: \(self.deviceName)")
    }

    /// Update scanning state
    func updateScanningState(isScanning: Bool) {
        self.isScanning = isScanning
        Logger.shared.debug("[BLEDataPublisher] Scanning state: \(isScanning)")
    }

    /// Update connected device
    func updateConnectedDevice(_ peripheral: CBPeripheral?) {
        connectedDevice = peripheral
        deviceUUID = peripheral?.identifier
        if let name = peripheral?.name {
            deviceName = name
        }
    }

    // MARK: - Recording State Management

    /// Update recording state
    func updateRecordingState(isRecording: Bool) {
        self.isRecording = isRecording
        Logger.shared.info("[BLEDataPublisher] Recording state: \(isRecording)")
    }

    // MARK: - Error Management

    /// Set error message
    func setError(_ message: String) {
        lastError = message
        addLog("ERROR: \(message)")
        Logger.shared.error("[BLEDataPublisher] Error: \(message)")
    }

    /// Clear error
    func clearError() {
        lastError = nil
    }

    // MARK: - Logging

    /// Add log message
    func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = LogMessage(message: "[\(timestamp)] \(message)")
        logMessages.append(logMessage)

        // Keep only last 100 log messages
        if logMessages.count > 100 {
            logMessages.removeFirst(logMessages.count - 100)
        }
    }

    /// Clear all logs
    func clearLogs() {
        logMessages.removeAll()
        Logger.shared.info("[BLEDataPublisher] Cleared all logs")
    }

    // MARK: - Device State Management

    /// Update device state
    func updateDeviceState(_ state: DeviceStateResult) {
        deviceState = state
    }

    /// Reset all state
    func reset() {
        isConnected = false
        isScanning = false
        deviceName = "No Device"
        connectedDevice = nil
        connectionState = "disconnected"
        deviceUUID = nil
        discoveredDevices.removeAll()
        discoveredDevicesInfo.removeAll()
        isRecording = false
        packetsReceived = 0
        lastError = nil
        deviceState = nil
        Logger.shared.info("[BLEDataPublisher] Reset all state")
    }
}
