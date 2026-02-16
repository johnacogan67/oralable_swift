//
//  OralableDevice.swift
//  OralableApp
//
//  Created: November 2024
//  UPDATED: January 29, 2026
//
//  Fixes Applied:
//  - Fix 1: Renamed ppgWaveform references to accelerometer (code clarity)
//  - Fix 2: Added proper timestamp calculation for sample timing (accuracy)
//  - Fix 3: Added BLE connection readiness state machine (reliability)
//  - Fix 4: Added AccelerometerConversion utility struct (convenience)
//  - Fix 6: CORRECTED PPG channel order mapping (Red at offset 0, IR at offset 4, Green at offset 8)
//  - Fix 7: Added tgmBatteryCharUUID to characteristic discovery (battery reporting)
//  - Fix 8: CRITICAL - Now uses OralableCore.BLEDataParser for proper frame counter handling (Jan 29, 2026)
//  - Fix 9: Added frame counter tracking for packet loss detection (Jan 29, 2026)
//

import Foundation
import CoreBluetooth
import Combine
import OralableCore

// MARK: - Oralable Device

/// Oralable-specific BLE device implementation
/// Uses OralableCore.BLEDataParser for packet parsing
class OralableDevice: NSObject, BLEDeviceProtocol {
    
    // MARK: - BLE UUIDs
    
    // TGM Service
    private let tgmServiceUUID = CBUUID(string: "3A0FF000-98C4-46B2-94AF-1AEE0FD4C48E")
    
    // Characteristics
    private let sensorDataCharUUID = CBUUID(string: "3A0FF001-98C4-46B2-94AF-1AEE0FD4C48E")      // PPG
    private let accelerometerCharUUID = CBUUID(string: "3A0FF002-98C4-46B2-94AF-1AEE0FD4C48E")  // Accelerometer
    private let commandCharUUID = CBUUID(string: "3A0FF003-98C4-46B2-94AF-1AEE0FD4C48E")        // Temperature/Command
    private let tgmBatteryCharUUID = CBUUID(string: "3A0FF004-98C4-46B2-94AF-1AEE0FD4C48E")     // Battery (millivolts)
    
    // Standard Battery Service
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelCharUUID = CBUUID(string: "2A19")
    
    // MARK: - BLE Protocol Properties

    var deviceInfo: DeviceInfo
    var peripheral: CBPeripheral?

    // MARK: - Protocol Required Properties

    var deviceType: DeviceType { .oralable }
    var name: String { deviceInfo.name }
    var connectionState: DeviceConnectionState { deviceInfo.connectionState }
    var isConnected: Bool { peripheral?.state == .connected }
    var signalStrength: Int? { deviceInfo.signalStrength }
    var firmwareVersion: String? { nil }
    var hardwareVersion: String? { nil }

    var supportedSensors: [SensorType] {
        [.ppgRed, .ppgInfrared, .ppgGreen, .accelerometerX, .accelerometerY, .accelerometerZ, .temperature, .battery]
    }

    private let readingsSubject = PassthroughSubject<SensorReading, Never>()
    var sensorReadings: AnyPublisher<SensorReading, Never> {
        readingsSubject.eraseToAnyPublisher()
    }

    private let readingsBatchSubject = PassthroughSubject<[SensorReading], Never>()
    var sensorReadingsBatch: AnyPublisher<[SensorReading], Never> {
        readingsBatchSubject.eraseToAnyPublisher()
    }

    @Published var latestReadings: [SensorType: SensorReading] = [:]
    @Published var batteryLevel: Int?

    // MARK: - Service & Characteristic References

    private var tgmService: CBService?
    private var sensorDataCharacteristic: CBCharacteristic?
    private var accelerometerCharacteristic: CBCharacteristic?
    private var commandCharacteristic: CBCharacteristic?
    private var tgmBatteryCharacteristic: CBCharacteristic?
    private var batteryLevelCharacteristic: CBCharacteristic?

    // MARK: - Connection State Machine (Fix 3)
    
    struct NotificationReadiness: OptionSet {
        let rawValue: Int
        
        static let ppgData = NotificationReadiness(rawValue: 1 << 0)
        static let accelerometer = NotificationReadiness(rawValue: 1 << 1)
        static let temperature = NotificationReadiness(rawValue: 1 << 2)
        static let battery = NotificationReadiness(rawValue: 1 << 3)
        
        static let allRequired: NotificationReadiness = [.ppgData, .accelerometer]
        static let all: NotificationReadiness = [.ppgData, .accelerometer, .temperature, .battery]
    }
    
    private var notificationReadiness: NotificationReadiness = []
    
    var isConnectionReady: Bool {
        notificationReadiness.contains(.allRequired)
    }

    // MARK: - Continuations for Async/Await

    private var serviceDiscoveryContinuation: CheckedContinuation<Void, Error>?
    private var characteristicDiscoveryContinuation: CheckedContinuation<Void, Error>?
    private var notificationEnableContinuation: CheckedContinuation<Void, Error>?
    private var connectionReadyContinuation: CheckedContinuation<Void, Never>?
    private var accelerometerNotificationContinuation: CheckedContinuation<Void, Error>?
    
    // MARK: - Frame Counter Tracking (Fix 9)
    
    private var lastPPGFrameCounter: UInt32?
    private var lastAccelFrameCounter: UInt32?
    private var ppgPacketsLost: Int = 0
    private var accelPacketsLost: Int = 0
    
    // MARK: - Statistics

    private var packetsReceived: Int = 0
    private var bytesReceived: Int = 0
    private var lastPacketTime: Date?
    private var ppgSampleCount: Int = 0

    // MARK: - Sample Rate Verification

    private var sampleRateStats = SampleRateStats()

    private struct SampleRateStats {
        var firstPacketTime: Date?
        var lastPacketTime: Date?
        var packetCount: Int = 0
        var frameCounterFirst: UInt32?
        var frameCounterLast: UInt32?
        var intervalSum: Double = 0
        var intervalCount: Int = 0
        var minInterval: Double = Double.greatestFiniteMagnitude
        var maxInterval: Double = 0
        var recentIntervals: [Double] = []
        let maxRecentIntervals = 100

        mutating func reset() {
            firstPacketTime = nil
            lastPacketTime = nil
            packetCount = 0
            frameCounterFirst = nil
            frameCounterLast = nil
            intervalSum = 0
            intervalCount = 0
            minInterval = Double.greatestFiniteMagnitude
            maxInterval = 0
            recentIntervals.removeAll()
        }

        mutating func recordPacket(time: Date, frameCounter: UInt32) {
            if firstPacketTime == nil {
                firstPacketTime = time
                frameCounterFirst = frameCounter
            }
            if let lastTime = lastPacketTime {
                let interval = time.timeIntervalSince(lastTime)
                intervalSum += interval
                intervalCount += 1
                minInterval = min(minInterval, interval)
                maxInterval = max(maxInterval, interval)
                recentIntervals.append(interval)
                if recentIntervals.count > maxRecentIntervals {
                    recentIntervals.removeFirst()
                }
            }
            lastPacketTime = time
            frameCounterLast = frameCounter
            packetCount += 1
        }

        var averageInterval: Double {
            guard intervalCount > 0 else { return 0 }
            return intervalSum / Double(intervalCount)
        }

        var recentAverageInterval: Double {
            guard !recentIntervals.isEmpty else { return 0 }
            return recentIntervals.reduce(0, +) / Double(recentIntervals.count)
        }

        var packetsPerSecond: Double {
            guard averageInterval > 0 else { return 0 }
            return 1.0 / averageInterval
        }

        var recentPacketsPerSecond: Double {
            guard recentAverageInterval > 0 else { return 0 }
            return 1.0 / recentAverageInterval
        }

        var totalDuration: Double {
            guard let first = firstPacketTime, let last = lastPacketTime else { return 0 }
            return last.timeIntervalSince(first)
        }
    }
    
    // MARK: - Initialization
    
    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        
        // Create device info
        self.deviceInfo = DeviceInfo(
            type: .oralable,
            name: peripheral.name ?? "Oralable",
            id: peripheral.identifier,
            connectionState: .disconnected
        )
        
        super.init()
        
        peripheral.delegate = self
    }
    
    // MARK: - BLEDeviceProtocol Methods
    
    func connect() async throws {
        Logger.shared.info("[OralableDevice] 🔗 Connect requested")
        deviceInfo.connectionState = .connecting
    }
    
    func disconnect() {
        Logger.shared.info("[OralableDevice] 🔌 Disconnect requested")
        deviceInfo.connectionState = .disconnecting
        
        // Reset state
        notificationReadiness = []
        lastPPGFrameCounter = nil
        lastAccelFrameCounter = nil
        ppgPacketsLost = 0
        accelPacketsLost = 0
        sampleRateStats.reset()
    }

    func discoverServices() async throws {
        guard let peripheral = peripheral else {
            throw DeviceError.invalidPeripheral("Peripheral is nil")
        }

        Logger.shared.info("[OralableDevice] 🔍 Starting service discovery...")

        peripheral.delegate = self

        return try await withCheckedThrowingContinuation { continuation in
            self.serviceDiscoveryContinuation = continuation
            peripheral.discoverServices([tgmServiceUUID, batteryServiceUUID])
        }
    }

    func discoverCharacteristics() async throws {
        guard let peripheral = peripheral,
              let service = tgmService else {
            throw DeviceError.serviceNotFound("TGM service not found")
        }

        Logger.shared.info("[OralableDevice] 🔍 Discovering characteristics for TGM service...")

        return try await withCheckedThrowingContinuation { continuation in
            self.characteristicDiscoveryContinuation = continuation
            peripheral.discoverCharacteristics(
                [sensorDataCharUUID, accelerometerCharUUID, commandCharUUID, tgmBatteryCharUUID],
                for: service
            )
        }
    }

    func enableNotifications() async throws {
        guard let peripheral = peripheral,
              let characteristic = sensorDataCharacteristic else {
            throw DeviceError.characteristicNotFound("Sensor data characteristic not found")
        }

        Logger.shared.info("[OralableDevice] 🔔 Enabling notifications on sensor data characteristic...")
        
        return try await withCheckedThrowingContinuation { continuation in
            self.notificationEnableContinuation = continuation
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    // Enable accelerometer notifications (non-blocking)
    func enableAccelerometerNotifications() async {
        guard let peripheral = peripheral,
              let characteristic = accelerometerCharacteristic else {
            Logger.shared.warning("[OralableDevice] ⚠️ Accelerometer characteristic not found")
            return
        }

        Logger.shared.info("[OralableDevice] 🔔 Enabling notifications on accelerometer characteristic...")

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.accelerometerNotificationContinuation = continuation
                peripheral.setNotifyValue(true, for: characteristic)
            }
            Logger.shared.info("[OralableDevice] ✅ Accelerometer notifications enabled")
        } catch {
            Logger.shared.warning("[OralableDevice] ⚠️ Failed to enable accelerometer notifications: \(error.localizedDescription)")
        }
    }

    // Enable temperature notifications on 3A0FF003
    func enableTemperatureNotifications() async {
        guard let peripheral = peripheral,
              let characteristic = commandCharacteristic else {
            Logger.shared.warning("[OralableDevice] ⚠️ Command characteristic not found for temperature")
            return
        }

        Logger.shared.info("[OralableDevice] 🔔 Enabling notifications on temperature characteristic (3A0FF003)...")
        peripheral.setNotifyValue(true, for: characteristic)
        Logger.shared.info("[OralableDevice] ✅ Temperature notifications enabled")
    }
    
    /// Wait for connection to be fully ready (all required notifications enabled)
    func waitForConnectionReady() async {
        if isConnectionReady {
            Logger.shared.info("[OralableDevice] Connection already ready")
            return
        }
        
        Logger.shared.info("[OralableDevice] ⏳ Waiting for connection readiness...")
        
        await withCheckedContinuation { continuation in
            self.connectionReadyContinuation = continuation
        }
        
        Logger.shared.info("[OralableDevice] ✅ Connection ready")
    }

    // MARK: - LED Configuration

    /// Configure PPG LED pulse amplitudes after connection
    func configurePPGLEDs() async throws {
        guard let peripheral = peripheral,
              let commandChar = commandCharacteristic else {
            Logger.shared.warning("[OralableDevice] ⚠️ Cannot configure LEDs - command characteristic not found")
            return
        }

        Logger.shared.info("[OralableDevice] 💡 Configuring PPG LED amplitudes...")
        
        // LED configuration command format depends on firmware
        let configCommand = Data([0x01, 0x00])
        peripheral.writeValue(configCommand, for: commandChar, type: .withResponse)
    }

    // MARK: - BLEDeviceProtocol - Reading Methods

    func reading(for sensorType: SensorType) -> SensorReading? {
        latestReadings[sensorType]
    }

    func parseData(_ data: Data, from characteristic: CBCharacteristic) -> [SensorReading] {
        // Parsing is handled internally by delegate methods
        []
    }

    func sendCommand(_ command: DeviceCommand) async throws {
        guard let peripheral = peripheral,
              let characteristic = commandCharacteristic else {
            throw DeviceError.characteristicNotFound("Command characteristic not found")
        }

        let commandData = command.rawValue.data(using: .utf8) ?? Data()
        peripheral.writeValue(commandData, for: characteristic, type: .withResponse)
    }

    func updateConfiguration(_ config: DeviceConfiguration) async throws {
        Logger.shared.info("[OralableDevice] Configuration update requested")
    }

    func updateDeviceInfo() async throws {
        Logger.shared.info("[OralableDevice] Device info update requested")
    }

    // MARK: - Data Parsing (Fix 8: Uses OralableCore.BLEDataParser)

    /// Parse PPG sensor data using OralableCore.BLEDataParser
    private func parseSensorData(_ data: Data) {
        // Update packet statistics
        packetsReceived += 1
        bytesReceived += data.count

        let notificationTime = Date()

        if let lastTime = lastPacketTime {
            let interval = notificationTime.timeIntervalSince(lastTime)
            #if DEBUG
            if interval > 0.25 {
                Logger.shared.debug("[OralableDevice] ⚠️ Large packet interval: \(String(format: "%.3f", interval))s")
            }
            #endif
        }
        lastPacketTime = notificationTime

        // Use OralableCore.BLEDataParser for parsing (handles frame counter)
        guard let result = BLEDataParser.parsePPGPacket(data, notificationTime: notificationTime) else {
            Logger.shared.warning("[OralableDevice] ⚠️ Failed to parse PPG packet (\(data.count) bytes)")
            return
        }
        
        let frameCounter = result.frameCounter
        let samples = result.samples
        
        // Track frame counter for packet loss detection (Fix 9)
        if let lastFrame = lastPPGFrameCounter {
            let expectedFrame = lastFrame + 1
            if frameCounter != expectedFrame && frameCounter != 0 {
                let lost = frameCounter > expectedFrame ? Int(frameCounter - expectedFrame) : 0
                ppgPacketsLost += lost
                Logger.shared.warning("[OralableDevice] PPG frame gap: expected \(expectedFrame), got \(frameCounter), lost ~\(lost) packets (total: \(ppgPacketsLost))")
            }
        }
        lastPPGFrameCounter = frameCounter
        
        // Update sample rate stats
        sampleRateStats.recordPacket(time: notificationTime, frameCounter: frameCounter)

        // Convert PPGData to SensorReadings
        var readings: [SensorReading] = []
        readings.reserveCapacity(samples.count * 3)
        
        let deviceId = peripheral?.identifier.uuidString

        for sample in samples {
            let redReading = SensorReading(
                sensorType: .ppgRed,
                value: Double(sample.red),
                timestamp: sample.timestamp,
                deviceId: deviceId
            )
            
            let irReading = SensorReading(
                sensorType: .ppgInfrared,
                value: Double(sample.ir),
                timestamp: sample.timestamp,
                deviceId: deviceId
            )
            
            let greenReading = SensorReading(
                sensorType: .ppgGreen,
                value: Double(sample.green),
                timestamp: sample.timestamp,
                deviceId: deviceId
            )

            readings.append(redReading)
            readings.append(irReading)
            readings.append(greenReading)

            // Update latest readings
            latestReadings[.ppgRed] = redReading
            latestReadings[.ppgInfrared] = irReading
            latestReadings[.ppgGreen] = greenReading
        }

        ppgSampleCount += samples.count

        // Emit batch
        if !readings.isEmpty {
            readingsBatchSubject.send(readings)
        }

        #if DEBUG
        if packetsReceived % 50 == 0 {
            Logger.shared.debug("[OralableDevice] PPG stats: \(samples.count) samples, frame \(frameCounter), total \(ppgSampleCount) samples, \(String(format: "%.1f", sampleRateStats.recentPacketsPerSecond)) pkt/s")
        }
        #endif
    }

    /// Parse accelerometer data using OralableCore.BLEDataParser
    private func parseAccelerometerData(_ data: Data) {
        let notificationTime = Date()
        
        // Use OralableCore.BLEDataParser for parsing (handles frame counter)
        guard let result = BLEDataParser.parseAccelerometerPacket(data, notificationTime: notificationTime) else {
            Logger.shared.warning("[OralableDevice] ⚠️ Failed to parse accelerometer packet (\(data.count) bytes)")
            return
        }
        
        let frameCounter = result.frameCounter
        let samples = result.samples
        
        // Track frame counter for packet loss detection
        if let lastFrame = lastAccelFrameCounter {
            let expectedFrame = lastFrame + 1
            if frameCounter != expectedFrame && frameCounter != 0 {
                let lost = frameCounter > expectedFrame ? Int(frameCounter - expectedFrame) : 0
                accelPacketsLost += lost
                Logger.shared.warning("[OralableDevice] Accel frame gap: expected \(expectedFrame), got \(frameCounter), lost ~\(lost) packets")
            }
        }
        lastAccelFrameCounter = frameCounter

        // Convert AccelerometerData to SensorReadings
        var readings: [SensorReading] = []
        readings.reserveCapacity(samples.count * 3)
        
        let deviceId = peripheral?.identifier.uuidString

        for sample in samples {
            let xReading = SensorReading(
                sensorType: .accelerometerX,
                value: Double(sample.x),
                timestamp: sample.timestamp,
                deviceId: deviceId
            )
            
            let yReading = SensorReading(
                sensorType: .accelerometerY,
                value: Double(sample.y),
                timestamp: sample.timestamp,
                deviceId: deviceId
            )
            
            let zReading = SensorReading(
                sensorType: .accelerometerZ,
                value: Double(sample.z),
                timestamp: sample.timestamp,
                deviceId: deviceId
            )

            readings.append(xReading)
            readings.append(yReading)
            readings.append(zReading)

            // Update latest readings
            latestReadings[.accelerometerX] = xReading
            latestReadings[.accelerometerY] = yReading
            latestReadings[.accelerometerZ] = zReading
        }

        // Emit batch
        if !readings.isEmpty {
            readingsBatchSubject.send(readings)
        }
    }

    /// Parse temperature data using OralableCore.BLEDataParser
    private func parseTemperature(_ data: Data) {
        // Use OralableCore.BLEDataParser for parsing
        guard let result = BLEDataParser.parseTemperaturePacket(data) else {
            Logger.shared.warning("[OralableDevice] ⚠️ Failed to parse temperature packet (\(data.count) bytes)")
            return
        }
        
        let tempCelsius = result.temperatureCelsius

        Logger.shared.debug("[OralableDevice] 🌡️ Temperature: \(String(format: "%.2f", tempCelsius))°C")

        let reading = SensorReading(
            sensorType: .temperature,
            value: tempCelsius,
            timestamp: Date(),
            deviceId: peripheral?.identifier.uuidString
        )

        latestReadings[.temperature] = reading
        readingsBatchSubject.send([reading])
    }

    /// Parse TGM battery data using OralableCore.BLEDataParser
    private func parseBatteryData(_ data: Data) {
        // Use OralableCore.BLEDataParser for parsing
        guard let batteryData = BLEDataParser.parseTGMBatteryData(data) else {
            Logger.shared.warning("[OralableDevice] ⚠️ Failed to parse battery packet (\(data.count) bytes)")
            return
        }
        
        let percentage = batteryData.percentage

        Logger.shared.debug("[OralableDevice] 🔋 Battery: \(percentage)%")

        // Log warnings for low battery
        if BatteryConversion.needsCharging(percentage: Double(percentage)) {
            if BatteryConversion.isCritical(percentage: Double(percentage)) {
                Logger.shared.warning("[OralableDevice] ⚠️ BATTERY CRITICAL: \(percentage)%")
            } else {
                Logger.shared.warning("[OralableDevice] ⚠️ Battery low: \(percentage)%")
            }
        }

        batteryLevel = percentage

        let reading = SensorReading(
            sensorType: .battery,
            value: Double(percentage),
            timestamp: Date(),
            deviceId: peripheral?.identifier.uuidString
        )

        latestReadings[.battery] = reading
        readingsBatchSubject.send([reading])
    }

    /// Parse standard battery level using OralableCore.BLEDataParser
    private func parseStandardBatteryLevel(_ data: Data) {
        guard let level = BLEDataParser.parseStandardBatteryLevel(data) else {
            Logger.shared.warning("[OralableDevice] ⚠️ Failed to parse standard battery level")
            return
        }

        Logger.shared.info("[OralableDevice] 🔋 Standard Battery Level: \(level)%")

        batteryLevel = level

        let reading = SensorReading(
            sensorType: .battery,
            value: Double(level),
            timestamp: Date(),
            deviceId: peripheral?.identifier.uuidString
        )

        latestReadings[.battery] = reading
        readingsBatchSubject.send([reading])
    }
    
    // MARK: - Statistics
    
    /// Get current packet loss statistics
    var packetLossStats: (ppgLost: Int, accelLost: Int) {
        return (ppgPacketsLost, accelPacketsLost)
    }
    
    /// Reset packet loss counters
    func resetPacketLossStats() {
        ppgPacketsLost = 0
        accelPacketsLost = 0
        lastPPGFrameCounter = nil
        lastAccelFrameCounter = nil
    }
}

// MARK: - CBPeripheralDelegate

extension OralableDevice: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            Logger.shared.error("[OralableDevice] ❌ Service discovery failed: \(error.localizedDescription)")
            serviceDiscoveryContinuation?.resume(throwing: error)
            serviceDiscoveryContinuation = nil
            return
        }

        guard let services = peripheral.services else {
            Logger.shared.error("[OralableDevice] ❌ No services found")
            serviceDiscoveryContinuation?.resume(throwing: DeviceError.serviceNotFound("No services found"))
            serviceDiscoveryContinuation = nil
            return
        }

        Logger.shared.info("[OralableDevice] Found \(services.count) services:")

        for service in services {
            Logger.shared.info("[OralableDevice]   - \(service.uuid.uuidString)")

            if service.uuid == tgmServiceUUID {
                tgmService = service
                Logger.shared.info("[OralableDevice] ✅ TGM service found")
            } else if service.uuid == batteryServiceUUID {
                Logger.shared.info("[OralableDevice] 🔋 Battery service found - discovering characteristics...")
                peripheral.discoverCharacteristics([batteryLevelCharUUID], for: service)
            }
        }

        if tgmService != nil {
            serviceDiscoveryContinuation?.resume()
            serviceDiscoveryContinuation = nil
        } else {
            Logger.shared.error("[OralableDevice] ❌ TGM service not found")
            serviceDiscoveryContinuation?.resume(throwing: DeviceError.serviceNotFound("TGM service not found"))
            serviceDiscoveryContinuation = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            Logger.shared.error("[OralableDevice] ❌ Characteristic discovery failed: \(error.localizedDescription)")
            characteristicDiscoveryContinuation?.resume(throwing: error)
            characteristicDiscoveryContinuation = nil
            return
        }

        guard let characteristics = service.characteristics else {
            Logger.shared.warning("[OralableDevice] ⚠️ No characteristics found for service \(service.uuid.uuidString)")
            return
        }

        // Handle Battery Service characteristics separately
        if service.uuid == batteryServiceUUID {
            for characteristic in characteristics {
                if characteristic.uuid == batteryLevelCharUUID {
                    batteryLevelCharacteristic = characteristic
                    Logger.shared.info("[OralableDevice] 🔋 Battery Level characteristic found")
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.readValue(for: characteristic)
                }
            }
            return
        }

        Logger.shared.info("[OralableDevice] Found \(characteristics.count) characteristics for TGM service:")

        var foundCount = 0

        for characteristic in characteristics {
            switch characteristic.uuid {
            case sensorDataCharUUID:
                sensorDataCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] ✅ Sensor Data characteristic found (3A0FF001)")
                foundCount += 1

            case commandCharUUID:
                commandCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] ✅ Command characteristic found (3A0FF003)")
                foundCount += 1

            case accelerometerCharUUID:
                accelerometerCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] ✅ Accelerometer characteristic found (3A0FF002)")
                foundCount += 1

            case tgmBatteryCharUUID:
                tgmBatteryCharacteristic = characteristic
                Logger.shared.info("[OralableDevice] 🔋 TGM Battery characteristic found (3A0FF004)")
                peripheral.setNotifyValue(true, for: characteristic)
                foundCount += 1

            default:
                Logger.shared.debug("[OralableDevice] Other characteristic: \(characteristic.uuid.uuidString)")
            }
        }

        if foundCount >= 1 {
            Logger.shared.info("[OralableDevice] ✅ Found \(foundCount)/4 expected characteristics")
            characteristicDiscoveryContinuation?.resume()
            characteristicDiscoveryContinuation = nil
        } else {
            Logger.shared.error("[OralableDevice] ❌ Required characteristics not found")
            characteristicDiscoveryContinuation?.resume(throwing: DeviceError.characteristicNotFound("Required characteristics not found (found \(foundCount)/4)"))
            characteristicDiscoveryContinuation = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Logger.shared.error("[OralableDevice] ❌ Notification state update failed: \(error.localizedDescription)")

            if characteristic.uuid == sensorDataCharUUID {
                notificationEnableContinuation?.resume(throwing: error)
                notificationEnableContinuation = nil
            } else if characteristic.uuid == accelerometerCharUUID {
                accelerometerNotificationContinuation?.resume(throwing: error)
                accelerometerNotificationContinuation = nil
            }
            return
        }

        let charName = characteristic.uuid.uuidString.prefix(12)
        Logger.shared.info("[OralableDevice] ✅ Notification \(characteristic.isNotifying ? "enabled" : "disabled") for \(charName)...")

        if characteristic.isNotifying {
            switch characteristic.uuid {
            case sensorDataCharUUID:
                notificationReadiness.insert(.ppgData)
                Logger.shared.info("[OralableDevice] 📡 PPG notifications confirmed ready")
                notificationEnableContinuation?.resume()
                notificationEnableContinuation = nil

            case accelerometerCharUUID:
                notificationReadiness.insert(.accelerometer)
                Logger.shared.info("[OralableDevice] 📡 Accelerometer notifications confirmed ready")
                accelerometerNotificationContinuation?.resume()
                accelerometerNotificationContinuation = nil

            case commandCharUUID:
                notificationReadiness.insert(.temperature)
                Logger.shared.info("[OralableDevice] 📡 Temperature notifications confirmed ready")

            case batteryLevelCharUUID, tgmBatteryCharUUID:
                notificationReadiness.insert(.battery)
                Logger.shared.info("[OralableDevice] 📡 Battery notifications confirmed ready")

            default:
                Logger.shared.debug("[OralableDevice] 📡 Unknown characteristic notifications enabled: \(charName)")
            }

            Logger.shared.info("[OralableDevice] Readiness state: \(notificationReadiness) (need: \(NotificationReadiness.allRequired))")

            if isConnectionReady {
                Logger.shared.info("[OralableDevice] 🎉 Connection fully ready - all required notifications enabled")

                if let continuation = connectionReadyContinuation {
                    connectionReadyContinuation = nil
                    continuation.resume()
                }
            }
        } else {
            switch characteristic.uuid {
            case sensorDataCharUUID:
                notificationReadiness.remove(.ppgData)
            case accelerometerCharUUID:
                notificationReadiness.remove(.accelerometer)
            case commandCharUUID:
                notificationReadiness.remove(.temperature)
            case batteryLevelCharUUID, tgmBatteryCharUUID:
                notificationReadiness.remove(.battery)
            default:
                break
            }
            Logger.shared.warning("[OralableDevice] ⚠️ Notifications disabled for \(charName)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Logger.shared.error("[OralableDevice] ❌ Value update error: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else {
            Logger.shared.warning("[OralableDevice] ⚠️ Received nil data from characteristic")
            return
        }

        // Route data based on characteristic UUID
        switch characteristic.uuid {
        case sensorDataCharUUID:
            // PPG data (244 bytes typically: 4 + 20×12)
            #if DEBUG
            Logger.shared.debug("[OralableDevice] 📦 Received \(data.count) bytes on PPG characteristic")
            #endif
            parseSensorData(data)

        case accelerometerCharUUID:
            // Accelerometer data (154 bytes typically: 4 + 25×6)
            #if DEBUG
            Logger.shared.debug("[OralableDevice] 📦 Received \(data.count) bytes on accelerometer characteristic")
            #endif
            parseAccelerometerData(data)

        case commandCharUUID:
            // Temperature data (6 bytes typically: 4 + 2)
            #if DEBUG
            Logger.shared.debug("[OralableDevice] 📦 Received \(data.count) bytes on temperature characteristic")
            #endif
            parseTemperature(data)

        case batteryLevelCharUUID:
            // Standard battery level (1 byte, 0-100%)
            parseStandardBatteryLevel(data)

        case tgmBatteryCharUUID:
            // TGM Battery (4 bytes, millivolts)
            parseBatteryData(data)

        default:
            Logger.shared.debug("[OralableDevice] 📦 Received \(data.count) bytes on unknown characteristic: \(characteristic.uuid.uuidString)")
        }
    }
}
