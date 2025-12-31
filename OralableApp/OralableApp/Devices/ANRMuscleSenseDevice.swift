//
//  ANRMuscleSenseDevice.swift
//  OralableApp
//
//  Created by John A Cogan on 04/11/2025.
//  Updated: December 6, 2025 - Fixed service discovery stub methods
//

import Foundation
import CoreBluetooth
import Combine
import OralableCore

/// ANR Muscle Sense device implementation
@MainActor
class ANRMuscleSenseDevice: NSObject, BLEDeviceProtocol {
    
    // MARK: - BLE Service & Characteristics UUIDs (ANR M40 Design Guide)

    // Automation IO Service (EMG Data) - Primary data service
    private static let automationIOServiceUUID = CBUUID(string: "1815")
    private static let analogCharacteristicUUID = CBUUID(string: "2A58")  // EMG: 16-bit, 0-1023, 100ms notify
    private static let digitalCharacteristicUUID = CBUUID(string: "2A56") // Device ID: 8-bit, 1-24

    // Battery Service (v1.5+)
    private static let batteryServiceUUID = CBUUID(string: "180F")
    private static let batteryLevelUUID = CBUUID(string: "2A19")  // 8-bit, 0-100%

    // Device Information Service
    private static let deviceInfoServiceUUID = CBUUID(string: "180A")
    private static let modelNumberUUID = CBUUID(string: "2A24")
    private static let serialNumberUUID = CBUUID(string: "2A25")
    private static let firmwareRevisionUUID = CBUUID(string: "2A26")
    private static let hardwareRevisionUUID = CBUUID(string: "2A27")
    private static let softwareRevisionUUID = CBUUID(string: "2A28")

    // ANR Company ID for device discovery (from Bluetooth SIG)
    static let anrCompanyID: UInt16 = 0x05DA
    
    // MARK: - Protocol Properties
    
    var deviceInfo: DeviceInfo
    var deviceType: DeviceType { .anr }
    var name: String { deviceInfo.name }
    var peripheral: CBPeripheral?
    var connectionState: DeviceConnectionState { deviceInfo.connectionState }
    var isConnected: Bool { connectionState == .connected }
    var signalStrength: Int? { deviceInfo.signalStrength }
    var batteryLevel: Int? { deviceInfo.batteryLevel }
    var firmwareVersion: String? { deviceInfo.firmwareVersion }
    var hardwareVersion: String? { deviceInfo.hardwareVersion }
    
    private let sensorReadingsSubject = PassthroughSubject<SensorReading, Never>()
    var sensorReadings: AnyPublisher<SensorReading, Never> {
        sensorReadingsSubject.eraseToAnyPublisher()
    }

    private let sensorReadingsBatchSubject = PassthroughSubject<[SensorReading], Never>()
    var sensorReadingsBatch: AnyPublisher<[SensorReading], Never> {
        sensorReadingsBatchSubject.eraseToAnyPublisher()
    }

    var latestReadings: [SensorType: SensorReading] = [:]
    
    var supportedSensors: [SensorType] {
        DeviceType.anr.defaultSensors
    }
    
    // MARK: - Private Properties
    
    private var centralManager: CBCentralManager?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    
    // MARK: - Initialization
    
    init(peripheral: CBPeripheral, name: String) {
        self.peripheral = peripheral
        self.deviceInfo = DeviceInfo(
            type: .anr,
            name: name,
            peripheralIdentifier: peripheral.identifier,
            connectionState: .disconnected
        )
        super.init()
    }
    
    // MARK: - Connection Management
    
    func connect() async throws {
        guard let peripheral = peripheral else {
            throw DeviceError.invalidPeripheral("ANR peripheral is nil")
        }
        
        deviceInfo.connectionState = .connecting
        
        peripheral.delegate = self
    }
    
    func disconnect() async {
        deviceInfo.connectionState = .disconnecting
        
        await stopDataStream()
        
        deviceInfo.connectionState = .disconnected
    }
    
    func isAvailable() -> Bool {
        guard let peripheral = peripheral else { return false }
        return peripheral.state == .connected || peripheral.state == .connecting
    }
    
    // MARK: - Data Operations
    
    func startDataStream() async throws {
        guard isConnected else {
            throw DeviceError.notConnected("ANR device not connected")
        }

        guard let peripheral = peripheral else {
            throw DeviceError.invalidPeripheral("ANR peripheral is nil")
        }

        // Enable notifications for EMG data (Analog characteristic - 100ms interval)
        if let emgChar = characteristics[Self.analogCharacteristicUUID] {
            peripheral.setNotifyValue(true, for: emgChar)
            Logger.shared.info("[ANR] ✅ Enabled EMG notifications (Analog 0x2A58)")
        } else {
            Logger.shared.warning("[ANR] ⚠️ EMG characteristic not found - cannot enable notifications")
        }

        // Enable notifications for battery level
        if let batteryChar = characteristics[Self.batteryLevelUUID] {
            peripheral.setNotifyValue(true, for: batteryChar)
            Logger.shared.info("[ANR] ✅ Enabled battery notifications (0x2A19)")
        }
    }
    
    func stopDataStream() async {
        guard let peripheral = peripheral else { return }
        
        for characteristic in characteristics.values {
            peripheral.setNotifyValue(false, for: characteristic)
        }
    }
    
    func requestReading(for sensorType: SensorType) async throws -> SensorReading? {
        guard isConnected else {
            throw DeviceError.notConnected("ANR device not connected")
        }

        return latestReadings[sensorType]
    }
    
    func parseData(_ data: Data, from characteristic: CBCharacteristic) -> [SensorReading] {
        var readings: [SensorReading] = []
        let characteristicUUID = characteristic.uuid
        let timestamp = Date()

        // EMG Data (Analog characteristic 0x2A58)
        if characteristicUUID == Self.analogCharacteristicUUID {
            if let reading = parseEMGData(data, timestamp: timestamp) {
                readings.append(reading)
                Logger.shared.debug("[ANR] 📊 EMG: \(Int(reading.value))")
            }
        }
        // Battery Data (Battery Level 0x2A19)
        else if characteristicUUID == Self.batteryLevelUUID {
            if let reading = parseBatteryData(data, timestamp: timestamp) {
                readings.append(reading)
                Logger.shared.debug("[ANR] 🔋 Battery: \(Int(reading.value))%")
            }
        }
        // Device ID (Digital characteristic 0x2A56)
        else if characteristicUUID == Self.digitalCharacteristicUUID {
            parseDeviceID(data)
        }
        // Device Info characteristics
        else if characteristicUUID == Self.firmwareRevisionUUID {
            if let fwVersion = String(data: data, encoding: .utf8) {
                deviceInfo.firmwareVersion = fwVersion.trimmingCharacters(in: .controlCharacters)
                Logger.shared.info("[ANR] Firmware: \(deviceInfo.firmwareVersion ?? "?")")
            }
        }
        else if characteristicUUID == Self.hardwareRevisionUUID {
            if let hwVersion = String(data: data, encoding: .utf8) {
                deviceInfo.hardwareVersion = hwVersion.trimmingCharacters(in: .controlCharacters)
                Logger.shared.info("[ANR] Hardware: \(deviceInfo.hardwareVersion ?? "?")")
            }
        }

        // Batch update to prevent UI flooding
        var latestByType: [SensorType: SensorReading] = [:]
        for reading in readings {
            latestByType[reading.sensorType] = reading
            sensorReadingsSubject.send(reading)
        }

        // Single batch update to latestReadings
        for (type, reading) in latestByType {
            latestReadings[type] = reading
        }

        // Send batch for subscribers
        if !readings.isEmpty {
            sensorReadingsBatchSubject.send(readings)
        }

        return readings
    }
    
    // MARK: - Device Control
    
    func sendCommand(_ command: DeviceCommand) async throws {
        guard isConnected else {
            throw DeviceError.notConnected("ANR device not connected")
        }
        // Commands not implemented for ANR device
    }

    func updateConfiguration(_ config: DeviceConfiguration) async throws {
        guard isConnected else {
            throw DeviceError.notConnected("ANR device not connected")
        }
        // Configuration not implemented for ANR device
    }

    func updateDeviceInfo() async throws {
        guard isConnected else {
            throw DeviceError.notConnected("ANR device not connected")
        }

        guard let peripheral = peripheral else {
            throw DeviceError.invalidPeripheral("ANR peripheral is nil")
        }

        // Read battery level
        if let batteryChar = characteristics[Self.batteryLevelUUID] {
            peripheral.readValue(for: batteryChar)
        }

        // Read firmware version
        if let fwChar = characteristics[Self.firmwareRevisionUUID] {
            peripheral.readValue(for: fwChar)
        }

        // Read hardware version
        if let hwChar = characteristics[Self.hardwareRevisionUUID] {
            peripheral.readValue(for: hwChar)
        }

        // Read device ID
        if let deviceIDChar = characteristics[Self.digitalCharacteristicUUID] {
            peripheral.readValue(for: deviceIDChar)
        }
    }
    
    // MARK: - Data Parsing Helpers
    
    /// Parse EMG data from ANR M40 Analog characteristic (0x2A58)
    /// Format: 16-bit unsigned integer, range 0-1023, notify interval 100ms (10 Hz)
    private func parseEMGData(_ data: Data, timestamp: Date) -> SensorReading? {
        // ANR M40 Design Guide: Analog characteristic is 16-bit unsigned, 0-1023
        guard data.count >= 2 else {
            Logger.shared.warning("[ANR] EMG data too short: \(data.count) bytes")
            return nil
        }

        let emgValue = data.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }

        // Validate range (0-1023 per design guide)
        guard emgValue <= 1023 else {
            Logger.shared.warning("[ANR] EMG value out of range: \(emgValue)")
            return nil
        }

        return SensorReading(
            sensorType: .emg,
            value: Double(emgValue),
            timestamp: timestamp,
            deviceId: deviceInfo.id.uuidString,
            quality: 0.95
        )
    }

    /// Parse Device ID from Digital characteristic (0x2A56)
    /// Format: 8-bit unsigned integer, range 1-24
    private func parseDeviceID(_ data: Data) {
        guard data.count >= 1 else { return }
        let deviceID = data[0]
        Logger.shared.info("[ANR] Device ID: \(deviceID)")
    }
    
    private func parseBatteryData(_ data: Data, timestamp: Date) -> SensorReading? {
        guard data.count >= 1 else { return nil }
        
        let batteryValue = data[0]
        deviceInfo.batteryLevel = Int(batteryValue)
        
        return SensorReading(
            sensorType: .battery,
            value: Double(batteryValue),
            timestamp: timestamp,
            deviceId: deviceInfo.id.uuidString
        )
    }
    
    // MARK: - Service Discovery Methods (Called by DeviceManager)
    
    /// Trigger service discovery on the peripheral
    func discoverServices() async throws {
        guard let peripheral = peripheral else {
            throw DeviceError.invalidPeripheral("ANR peripheral is nil")
        }
        
        Logger.shared.info("[ANR] 🔍 Starting service discovery...")
        
        // Set delegate to receive callbacks
        peripheral.delegate = self
        
        // Discover ANR M40 services
        let serviceUUIDs = [
            Self.automationIOServiceUUID,  // 0x1815 - EMG data
            Self.batteryServiceUUID,       // 0x180F - Battery
            Self.deviceInfoServiceUUID     // 0x180A - Device info
        ]
        
        peripheral.discoverServices(serviceUUIDs)
    }
    
    /// Characteristic discovery is handled automatically by didDiscoverServices delegate
    func discoverCharacteristics() async throws {
        // This is handled by the CBPeripheralDelegate callback
        // didDiscoverServices triggers discoverCharacteristics for each service
        Logger.shared.debug("[ANR] Characteristics discovered via delegate callback")
    }
    
    /// Enable notifications for data streaming
    func enableNotifications() async throws {
        Logger.shared.info("[ANR] 🔔 Enabling notifications...")
        try await startDataStream()
    }
}

// MARK: - CBPeripheralDelegate

extension ANRMuscleSenseDevice: CBPeripheralDelegate {
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            Logger.shared.error("[ANR] ❌ Service discovery error: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else {
            Logger.shared.warning("[ANR] ⚠️ No services found")
            return
        }

        Logger.shared.info("[ANR] 📡 Found \(services.count) service(s)")

        for service in services {
            switch service.uuid {
            case Self.automationIOServiceUUID:
                Logger.shared.info("[ANR] ✅ Found Automation IO service (0x1815)")
                peripheral.discoverCharacteristics([Self.analogCharacteristicUUID, Self.digitalCharacteristicUUID], for: service)
            case Self.batteryServiceUUID:
                Logger.shared.info("[ANR] ✅ Found Battery service (0x180F)")
                peripheral.discoverCharacteristics([Self.batteryLevelUUID], for: service)
            case Self.deviceInfoServiceUUID:
                Logger.shared.info("[ANR] ✅ Found Device Info service (0x180A)")
                peripheral.discoverCharacteristics([Self.firmwareRevisionUUID, Self.hardwareRevisionUUID, Self.modelNumberUUID, Self.serialNumberUUID], for: service)
            default:
                Logger.shared.debug("[ANR] Ignoring unknown service: \(service.uuid)")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            Logger.shared.error("[ANR] ❌ Characteristic discovery error: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else {
            Logger.shared.warning("[ANR] ⚠️ No characteristics found for service \(service.uuid)")
            return
        }

        Logger.shared.info("[ANR] 📡 Found \(characteristics.count) characteristic(s) for service \(service.uuid)")

        for characteristic in characteristics {
            Logger.shared.info("[ANR] ✅ Found characteristic: \(characteristic.uuid)")

            Task { @MainActor in
                self.characteristics[characteristic.uuid] = characteristic

                // Read initial values for readable characteristics
                switch characteristic.uuid {
                case Self.batteryLevelUUID:
                    Logger.shared.debug("[ANR] Reading battery level...")
                    peripheral.readValue(for: characteristic)
                case Self.firmwareRevisionUUID, Self.hardwareRevisionUUID, Self.modelNumberUUID, Self.serialNumberUUID:
                    peripheral.readValue(for: characteristic)
                case Self.digitalCharacteristicUUID:
                    Logger.shared.debug("[ANR] Reading device ID...")
                    peripheral.readValue(for: characteristic)
                case Self.analogCharacteristicUUID:
                    // Enable EMG notifications immediately
                    Logger.shared.info("[ANR] 🔔 Enabling EMG notifications...")
                    peripheral.setNotifyValue(true, for: characteristic)
                default:
                    break
                }
            }
        }

        Task { @MainActor in
            self.deviceInfo.connectionState = .connected
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Logger.shared.error("[ANR] ❌ Value update error: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else { return }

        Task { @MainActor in
            let _ = self.parseData(data, from: characteristic)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Logger.shared.error("[ANR] ❌ Notification state error for \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            let state = characteristic.isNotifying ? "✅ enabled" : "disabled"
            Logger.shared.info("[ANR] Notifications \(state) for \(characteristic.uuid)")
        }
    }
}
