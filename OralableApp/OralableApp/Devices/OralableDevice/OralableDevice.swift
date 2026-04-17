//
//  OralableDevice.swift
//  OralableApp
//
//  Created: November 2024
//  UPDATED: February 2026
//
//  Core class declaration for OralableDevice.
//  Contains stored properties, initializer, BLE UUIDs, protocol conformance,
//  connection state machine, and core lifecycle methods.
//
//  Extensions in separate files:
//  - OralableDevice+DataParsing.swift      — PPG, accelerometer, temperature, battery parsing
//  - OralableDevice+CBPeripheralDelegate.swift — CBPeripheralDelegate methods
//  - OralableDevice+Statistics.swift        — Sample rate stats, packet loss tracking, diagnostics
//
//  Original fixes preserved:
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
    let tgmServiceUUID = CBUUID(string: "3A0FF000-98C4-46B2-94AF-1AEE0FD4C48E")

    // Characteristics
    let sensorDataCharUUID = CBUUID(string: "3A0FF001-98C4-46B2-94AF-1AEE0FD4C48E")      // PPG
    let accelerometerCharUUID = CBUUID(string: "3A0FF002-98C4-46B2-94AF-1AEE0FD4C48E")    // Accelerometer
    let commandCharUUID = CBUUID(string: "3A0FF003-98C4-46B2-94AF-1AEE0FD4C48E")          // Temperature/Command
    let tgmBatteryCharUUID = CBUUID(string: "3A0FF004-98C4-46B2-94AF-1AEE0FD4C48E")       // Battery (millivolts)
    let firmwareVersionCharUUID = CBUUID(string: "3A0FF006-98C4-46B2-94AF-1AEE0FD4C48E")  // Firmware string (read)
    let firmwareLogCharUUID = CBUUID(string: "3A0FF00A-98C4-46B2-94AF-1AEE0FD4C48E")      // Firmware logs (notify)
    let firmwareConfigCharUUID = CBUUID(string: "3A0FF00B-98C4-46B2-94AF-1AEE0FD4C48E")   // Firmware config (write)
    let firmwareConfigStateCharUUID = CBUUID(string: "3A0FF00C-98C4-46B2-94AF-1AEE0FD4C48E") // Firmware config state (read/notify)

    // Standard Battery Service
    let batteryServiceUUID = CBUUID(string: "180F")
    let batteryLevelCharUUID = CBUUID(string: "2A19")

    // MARK: - BLE Protocol Properties

    var deviceInfo: DeviceInfo
    var peripheral: CBPeripheral?

    // MARK: - Protocol Required Properties

    var deviceType: DeviceType { .oralable }
    var name: String { deviceInfo.name }
    var connectionState: DeviceConnectionState { deviceInfo.connectionState }
    var isConnected: Bool { peripheral?.state == .connected }
    var signalStrength: Int? { deviceInfo.signalStrength }
    var firmwareVersion: String? { deviceInfo.firmwareVersion }
    var hardwareVersion: String? { nil }

    var supportedSensors: [SensorType] {
        [.ppgRed, .ppgInfrared, .ppgGreen, .accelerometerX, .accelerometerY, .accelerometerZ, .temperature, .battery]
    }

    let readingsSubject = PassthroughSubject<SensorReading, Never>()
    var sensorReadings: AnyPublisher<SensorReading, Never> {
        readingsSubject.eraseToAnyPublisher()
    }

    let readingsBatchSubject = PassthroughSubject<[SensorReading], Never>()
    var sensorReadingsBatch: AnyPublisher<[SensorReading], Never> {
        readingsBatchSubject.eraseToAnyPublisher()
    }

    @Published var latestReadings: [SensorType: SensorReading] = [:]
    @Published var batteryLevel: Int?

    // MARK: - Service & Characteristic References

    var tgmService: CBService?
    var sensorDataCharacteristic: CBCharacteristic?
    var accelerometerCharacteristic: CBCharacteristic?
    var commandCharacteristic: CBCharacteristic?
    var tgmBatteryCharacteristic: CBCharacteristic?
    var firmwareVersionCharacteristic: CBCharacteristic?
    var firmwareLogCharacteristic: CBCharacteristic?
    var firmwareConfigCharacteristic: CBCharacteristic?
    var firmwareConfigStateCharacteristic: CBCharacteristic?
    var batteryLevelCharacteristic: CBCharacteristic?

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

    var notificationReadiness: NotificationReadiness = []

    var isConnectionReady: Bool {
        notificationReadiness.contains(.allRequired)
    }

    // MARK: - Continuations for Async/Await

    var serviceDiscoveryContinuation: CheckedContinuation<Void, Error>?
    var characteristicDiscoveryContinuation: CheckedContinuation<Void, Error>?
    var notificationEnableContinuation: CheckedContinuation<Void, Error>?
    var connectionReadyContinuation: CheckedContinuation<Void, Never>?
    var accelerometerNotificationContinuation: CheckedContinuation<Void, Error>?
    var writeCompletionContinuation: CheckedContinuation<Void, Error>?
    var firmwareReadContinuation: CheckedContinuation<String, Error>?

    // MARK: - Frame Counter Tracking (Fix 9)

    var lastPPGFrameCounter: UInt32?
    var lastAccelFrameCounter: UInt32?
    var ppgPacketsLost: Int = 0
    var accelPacketsLost: Int = 0

    // MARK: - Statistics

    var packetsReceived: Int = 0
    var bytesReceived: Int = 0
    var lastPacketTime: Date?
    var ppgSampleCount: Int = 0
    var lastBatteryParseFailureLogAt: Date?
    var lastTemperatureDebugLogAt: Date?
    var lastTemperatureDebugValue: Double?

    /// Called after each successful `readRSSI` (e.g. for link-quality summaries in `BLEBackgroundWorker`).
    var linkMetricsHandler: ((UUID, Int) -> Void)?

    // MARK: - Sample Rate Verification

    var sampleRateStats = SampleRateStats()

    // MARK: - Initialization

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral

        // Create device info
        self.deviceInfo = DeviceInfo(
            id: peripheral.identifier,
            type: .oralable,
            name: peripheral.name ?? "Oralable",
            peripheralIdentifier: peripheral.identifier,
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

    func disconnect() async {
        Logger.shared.info("[OralableDevice] 🔌 Disconnect requested")
        deviceInfo.connectionState = .disconnecting

        // Cancel any pending write continuation to avoid leaked continuations
        if let continuation = writeCompletionContinuation {
            writeCompletionContinuation = nil
            continuation.resume(throwing: DeviceError.connectionFailed("Device disconnected"))
        }

        // Reset state
        notificationReadiness = []
        lastPPGFrameCounter = nil
        lastAccelFrameCounter = nil
        ppgPacketsLost = 0
        accelPacketsLost = 0
        sampleRateStats.reset()
    }

    /// Cancel any pending async continuations to prevent hangs on disconnect
    func cancelPendingContinuations() {
        serviceDiscoveryContinuation?.resume(throwing: DeviceError.connectionFailed("Device disconnected"))
        serviceDiscoveryContinuation = nil
        characteristicDiscoveryContinuation?.resume(throwing: DeviceError.connectionFailed("Device disconnected"))
        characteristicDiscoveryContinuation = nil
        notificationEnableContinuation?.resume(throwing: DeviceError.connectionFailed("Device disconnected"))
        notificationEnableContinuation = nil
        connectionReadyContinuation?.resume()
        connectionReadyContinuation = nil
        accelerometerNotificationContinuation?.resume(throwing: DeviceError.connectionFailed("Device disconnected"))
        accelerometerNotificationContinuation = nil
        writeCompletionContinuation?.resume(throwing: DeviceError.connectionFailed("Device disconnected"))
        writeCompletionContinuation = nil
        firmwareReadContinuation?.resume(throwing: DeviceError.connectionFailed("Device disconnected"))
        firmwareReadContinuation = nil
    }

    func isAvailable() -> Bool {
        guard let peripheral = peripheral else { return false }
        return peripheral.state == .connected || peripheral.state == .connecting
    }

    func startDataStream() async throws {
        guard isConnected else {
            throw DeviceError.notConnected("Oralable device not connected")
        }
        try await enableNotifications()
        try await enableAccelerometerNotifications()
        await enableTemperatureNotifications()
    }

    func stopDataStream() async {
        guard let peripheral = peripheral else { return }
        sensorDataCharacteristic.map { peripheral.setNotifyValue(false, for: $0) }
        accelerometerCharacteristic.map { peripheral.setNotifyValue(false, for: $0) }
        commandCharacteristic.map { peripheral.setNotifyValue(false, for: $0) }
        tgmBatteryCharacteristic.map { peripheral.setNotifyValue(false, for: $0) }
    }

    func requestReading(for sensorType: SensorType) async throws -> SensorReading? {
        guard isConnected else {
            throw DeviceError.notConnected("Oralable device not connected")
        }
        return latestReadings[sensorType]
    }

    func discoverServices() async throws {
        guard let peripheral = peripheral else {
            throw DeviceError.invalidPeripheral("Peripheral is nil")
        }
        guard serviceDiscoveryContinuation == nil else {
            Logger.shared.warning("[OralableDevice] ⚠️ discoverServices called while a previous request is still pending")
            throw DeviceError.deviceBusy
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
        guard characteristicDiscoveryContinuation == nil else {
            Logger.shared.warning("[OralableDevice] ⚠️ discoverCharacteristics called while a previous request is still pending")
            throw DeviceError.deviceBusy
        }

        Logger.shared.info("[OralableDevice] 🔍 Discovering characteristics for TGM service...")

        return try await withCheckedThrowingContinuation { continuation in
            self.characteristicDiscoveryContinuation = continuation
            peripheral.discoverCharacteristics(
                [
                    sensorDataCharUUID,
                    accelerometerCharUUID,
                    commandCharUUID,
                    tgmBatteryCharUUID,
                    firmwareVersionCharUUID,
                    firmwareLogCharUUID,
                    firmwareConfigCharUUID,
                    firmwareConfigStateCharUUID
                ],
                for: service
            )
        }
    }

    // MARK: - Firmware configuration

    enum FirmwareConfigOpcode: UInt8 {
        case setLedPA = 0x01
        case setStatsPeriodSeconds = 0x02
        case requestConnParamUpdate = 0x03
        case setBatteryIntervalSeconds = 0x04
        case setTempIntervalSeconds = 0x05
        case setStreamEnableMask = 0x06
    }

    enum FirmwareLedID: UInt8 {
        case green = 0
        case ir = 1
        case red = 2
    }

    /// Best-effort config write. Firmware applies immediately at runtime.
    func writeFirmwareConfig(_ data: Data) throws {
        guard let peripheral, let characteristic = firmwareConfigCharacteristic else {
            throw DeviceError.characteristicNotFound("Firmware config characteristic not found")
        }
        let canWriteWithResponse = characteristic.properties.contains(.write)
        let type: CBCharacteristicWriteType = canWriteWithResponse ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    func setFirmwareLedPA(_ led: FirmwareLedID, pa: UInt8) throws {
        try writeFirmwareConfig(Data([FirmwareConfigOpcode.setLedPA.rawValue, led.rawValue, pa]))
    }

    func setFirmwareStreamStatsPeriodSeconds(_ seconds: UInt8) throws {
        try writeFirmwareConfig(Data([FirmwareConfigOpcode.setStatsPeriodSeconds.rawValue, seconds]))
    }

    func requestFirmwareConnParamUpdate() throws {
        try writeFirmwareConfig(Data([FirmwareConfigOpcode.requestConnParamUpdate.rawValue]))
    }

    func setFirmwareBatteryIntervalSeconds(_ seconds: UInt8) throws {
        try writeFirmwareConfig(Data([FirmwareConfigOpcode.setBatteryIntervalSeconds.rawValue, seconds]))
    }

    func setFirmwareTempIntervalSeconds(_ seconds: UInt8) throws {
        try writeFirmwareConfig(Data([FirmwareConfigOpcode.setTempIntervalSeconds.rawValue, seconds]))
    }

    /// bit0=PPG, bit1=ACC
    func setFirmwareStreamEnableMask(_ mask: UInt8) throws {
        try writeFirmwareConfig(Data([FirmwareConfigOpcode.setStreamEnableMask.rawValue, mask]))
    }

    /// Reads `3A0FF006` firmware string (must run after characteristic discovery).
    func readFirmwareVersion() async throws -> String {
        guard let peripheral = peripheral,
              let characteristic = firmwareVersionCharacteristic else {
            throw DeviceError.characteristicNotFound("Firmware version characteristic not found")
        }
        guard firmwareReadContinuation == nil else {
            Logger.shared.warning("[OralableDevice] ⚠️ readFirmwareVersion called while a previous read is still pending")
            throw DeviceError.deviceBusy
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.firmwareReadContinuation = continuation
            peripheral.readValue(for: characteristic)
        }
    }

    func enableNotifications() async throws {
        guard let peripheral = peripheral,
              let characteristic = sensorDataCharacteristic else {
            throw DeviceError.characteristicNotFound("Sensor data characteristic not found")
        }
        guard notificationEnableContinuation == nil else {
            Logger.shared.warning("[OralableDevice] ⚠️ enableNotifications called while a previous request is still pending")
            throw DeviceError.deviceBusy
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
        guard accelerometerNotificationContinuation == nil else {
            Logger.shared.warning("[OralableDevice] ⚠️ Accelerometer notification enable already pending")
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
            throw DeviceError.characteristicNotFound("Command characteristic not found")
        }
        guard writeCompletionContinuation == nil else {
            Logger.shared.warning("[OralableDevice] ⚠️ configurePPGLEDs called while a write is already pending")
            throw DeviceError.deviceBusy
        }

        // Some firmware builds expose 3A0FF003 as notify-only (temperature) and do not permit writes.
        // Avoid spamming CoreBluetooth with a write that will always fail.
        let canWriteWithResponse = commandChar.properties.contains(.write)
        let canWriteWithoutResponse = commandChar.properties.contains(.writeWithoutResponse)
        guard canWriteWithResponse || canWriteWithoutResponse else {
            Logger.shared.debug("[OralableDevice] 💡 Skipping LED configuration (command characteristic not writable)")
            return
        }

        Logger.shared.info("[OralableDevice] 💡 Configuring PPG LED amplitudes...")

        // LED configuration command format depends on firmware
        let configCommand = Data([0x01, 0x00])

        if canWriteWithResponse {
            return try await withCheckedThrowingContinuation { continuation in
                self.writeCompletionContinuation = continuation
                peripheral.writeValue(configCommand, for: commandChar, type: .withResponse)
            }
        } else {
            // Without-response writes may not trigger didWrite callbacks; treat as fire-and-forget.
            peripheral.writeValue(configCommand, for: commandChar, type: .withoutResponse)
            return
        }
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
        guard writeCompletionContinuation == nil else {
            Logger.shared.warning("[OralableDevice] ⚠️ sendCommand called while a write is already pending")
            throw DeviceError.deviceBusy
        }

        let commandData = command.rawValue.data(using: .utf8) ?? Data()

        return try await withCheckedThrowingContinuation { continuation in
            self.writeCompletionContinuation = continuation
            peripheral.writeValue(commandData, for: characteristic, type: .withResponse)
        }
    }

    func updateConfiguration(_ config: DeviceConfiguration) async throws {
        Logger.shared.info("[OralableDevice] Configuration update requested")
    }

    func updateDeviceInfo() async throws {
        Logger.shared.info("[OralableDevice] Device info update requested")
    }
}
