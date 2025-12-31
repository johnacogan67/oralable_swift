//
//  OralableDevice.swift
//  OralableApp
//
//  Created: November 2024
//  UPDATED: December 25, 2025
//
//  Fixes Applied:
//  - Fix 1: Renamed ppgWaveform references to accelerometer (code clarity)
//  - Fix 2: Added proper timestamp calculation for sample timing (accuracy)
//  - Fix 3: Added BLE connection readiness state machine (reliability)
//  - Fix 4: Added AccelerometerConversion utility struct (convenience)
//  - Fix 6: CORRECTED PPG channel order mapping (IR at offset 0, Red at offset 1)
//  - Fix 7: Added tgmBatteryCharUUID to characteristic discovery (battery reporting)
//
//  Previous Updates:
//  - November 29, 2025 (Day 4): Batch updates to prevent performance flooding
//  - November 29, 2025 (Day 4): Removed PPG validation to allow all values for debugging
//  - December 10, 2025: Fixed PPG channel mapping based on observed LED pulse amplitudes
//

import Foundation
import CoreBluetooth
import Combine
import OralableCore

/// Oralable-specific BLE device implementation
class OralableDevice: NSObject, BLEDeviceProtocol {
    
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

    // MARK: - Sensor Configuration Constants (Fix 2)
    
    /// PPG sensor sample rate (samples per second)
    private let ppgSampleRate: Double = 50.0
    
    /// Accelerometer sample rate (Hz)
    private let accelerometerSampleRate: Double = 100.0
    
    /// PPG samples per BLE notification packet
    private let ppgSamplesPerPacket: Int = 20
    
    /// Accelerometer samples per BLE notification packet
    private let accelerometerSamplesPerPacket: Int = 25
    
    /// Accelerometer full scale setting (±2g)
    private let accelerometerFullScale: Int = 2
    
    // MARK: - TGM Service & Characteristics (Fix 1: Renamed)

    private let tgmServiceUUID = CBUUID(string: "3A0FF000-98C4-46B2-94AF-1AEE0FD4C48E")
    private let sensorDataCharUUID = CBUUID(string: "3A0FF001-98C4-46B2-94AF-1AEE0FD4C48E")      // PPG data (244 bytes)
    private let accelerometerCharUUID = CBUUID(string: "3A0FF002-98C4-46B2-94AF-1AEE0FD4C48E")  // Accelerometer (154 bytes)
    private let commandCharUUID = CBUUID(string: "3A0FF003-98C4-46B2-94AF-1AEE0FD4C48E")        // Temperature (8 bytes)
    private let tgmBatteryCharUUID = CBUUID(string: "3A0FF004-98C4-46B2-94AF-1AEE0FD4C48E")     // TGM Battery (millivolts)

    // MARK: - Standard BLE Battery Service (0x180F)
    
    private let batteryServiceUUID = CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB")
    private let batteryLevelCharUUID = CBUUID(string: "00002A19-0000-1000-8000-00805F9B34FB")

    private var tgmService: CBService?
    private var sensorDataCharacteristic: CBCharacteristic?
    private var commandCharacteristic: CBCharacteristic?
    private var accelerometerCharacteristic: CBCharacteristic?  // Fix 1: Renamed from ppgWaveformCharacteristic
    private var batteryLevelCharacteristic: CBCharacteristic?
    private var tgmBatteryCharacteristic: CBCharacteristic?
    
    // MARK: - Connection Readiness State (Fix 3)
    
    /// Tracks which BLE notifications have been confirmed enabled
    private struct NotificationReadiness: OptionSet {
        let rawValue: Int
        
        static let ppgData = NotificationReadiness(rawValue: 1 << 0)
        static let accelerometer = NotificationReadiness(rawValue: 1 << 1)
        static let temperature = NotificationReadiness(rawValue: 1 << 2)
        static let battery = NotificationReadiness(rawValue: 1 << 3)
        
        /// Required notifications for data collection to start
        static let allRequired: NotificationReadiness = [.ppgData, .accelerometer]
        
        /// Optional notifications (nice to have but not blocking)
        static let allOptional: NotificationReadiness = [.temperature, .battery]
        
        /// All notifications
        static let all: NotificationReadiness = [.ppgData, .accelerometer, .temperature, .battery]
    }
    
    /// Current notification readiness state
    private var notificationReadiness: NotificationReadiness = []
    
    /// Whether connection is fully ready for data collection
    private var isConnectionReady: Bool {
        notificationReadiness.contains(.allRequired)
    }
    
    /// Continuation for waiting on connection readiness
    private var connectionReadyContinuation: CheckedContinuation<Void, Error>?
    
    // MARK: - Data Collection State
    
    private var isCollecting = false
    private var sessionStartTime: Date?
    
    // Continuations for async/await flow
    private var serviceDiscoveryContinuation: CheckedContinuation<Void, Error>?
    private var characteristicDiscoveryContinuation: CheckedContinuation<Void, Error>?
    private var notificationEnableContinuation: CheckedContinuation<Void, Error>?
    private var accelerometerNotificationContinuation: CheckedContinuation<Void, Error>?
    
    // MARK: - Statistics

    private var packetsReceived: Int = 0
    private var bytesReceived: Int = 0
    private var lastPacketTime: Date?
    private var ppgFrameCount: Int = 0

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
            peripheralIdentifier: peripheral.identifier,
            connectionState: .disconnected,
            signalStrength: nil
        )
        
        super.init()
        
        Logger.shared.info("[OralableDevice] Initialized for '\(deviceInfo.name)'")
        Logger.shared.info("[OralableDevice] Using TGM Service UUID: \(tgmServiceUUID.uuidString)")
        
        peripheral.delegate = self
    }
    
    // MARK: - Service Discovery
    
    func discoverServices() async throws {
        guard let peripheral = peripheral else {
            throw DeviceError.invalidPeripheral("Peripheral is nil")
        }

        Logger.shared.info("[OralableDevice] 🔍 Starting service discovery...")

        return try await withCheckedThrowingContinuation { continuation in
            self.serviceDiscoveryContinuation = continuation
            // Discover both TGM service and standard Battery Service
            peripheral.discoverServices([tgmServiceUUID, batteryServiceUUID])
        }
    }
    
    func discoverCharacteristics() async throws {
        guard let service = tgmService else {
            throw DeviceError.serviceNotFound("TGM service not found")
        }
        
        Logger.shared.info("[OralableDevice] 🔍 Starting characteristic discovery...")
        
        return try await withCheckedThrowingContinuation { continuation in
            self.characteristicDiscoveryContinuation = continuation
            peripheral?.discoverCharacteristics([
                sensorDataCharUUID,
                commandCharUUID,
                accelerometerCharUUID,  // Fix 1: Renamed
                tgmBatteryCharUUID      // Fix 7: TGM Battery for battery updates
            ], for: service)
        }
    }
    
    func enableNotifications() async throws {
        guard let peripheral = peripheral,
              let characteristic = sensorDataCharacteristic else {
            throw DeviceError.characteristicNotFound("Sensor data characteristic not found")
        }
        
        Logger.shared.info("[OralableDevice] 🔔 Enabling notifications on main characteristic...")
        
        return try await withCheckedThrowingContinuation { continuation in
            self.notificationEnableContinuation = continuation
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    // Enable accelerometer notifications (non-blocking)
    func enableAccelerometerNotifications() async {
        guard let peripheral = peripheral,
              let characteristic = accelerometerCharacteristic else {  // Fix 1: Renamed
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

    // MARK: - LED Configuration

    /// Configure PPG LED pulse amplitudes after connection
    func configurePPGLEDs() async throws {
        guard let peripheral = peripheral,
              let commandChar = commandCharacteristic else {
            Logger.shared.warning("[OralableDevice] ⚠️ Command characteristic not available for LED config")
            return
        }

        Logger.shared.info("[OralableDevice] 💡 Configuring PPG LEDs...")

        // LED pulse amplitude values (0x00 = off, 0xFF = max)
        // Start with moderate values to avoid saturation
        let irAmplitude: UInt8 = 0x60      // IR LED (register 0x24)
        let redAmplitude: UInt8 = 0x60     // Red LED (register 0x25)
        let greenAmplitude: UInt8 = 0x30   // Green LED (register 0x23)

        // Configure Green LED (LED1)
        let greenCommand = Data([0x23, greenAmplitude])
        peripheral.writeValue(greenCommand, for: commandChar, type: .withResponse)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms delay

        // Configure IR LED (LED2)
        let irCommand = Data([0x24, irAmplitude])
        peripheral.writeValue(irCommand, for: commandChar, type: .withResponse)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Configure Red LED (LED3)
        let redCommand = Data([0x25, redAmplitude])
        peripheral.writeValue(redCommand, for: commandChar, type: .withResponse)
        try await Task.sleep(nanoseconds: 100_000_000)

        Logger.shared.info("[OralableDevice] ✅ PPG LEDs configured - IR:0x\(String(format: "%02X", irAmplitude)), Red:0x\(String(format: "%02X", redAmplitude)), Green:0x\(String(format: "%02X", greenAmplitude))")
    }

    // MARK: - Continuation Cleanup

    /// Cancel any pending continuations to prevent hangs on disconnect
    func cancelPendingContinuations() {
        if let continuation = serviceDiscoveryContinuation {
            continuation.resume(throwing: DeviceError.connectionLost)
            serviceDiscoveryContinuation = nil
            Logger.shared.info("[OralableDevice] Cancelled pending service discovery continuation")
        }
        if let continuation = characteristicDiscoveryContinuation {
            continuation.resume(throwing: DeviceError.connectionLost)
            characteristicDiscoveryContinuation = nil
            Logger.shared.info("[OralableDevice] Cancelled pending characteristic discovery continuation")
        }
        if let continuation = notificationEnableContinuation {
            continuation.resume(throwing: DeviceError.connectionLost)
            notificationEnableContinuation = nil
            Logger.shared.info("[OralableDevice] Cancelled pending notification enable continuation")
        }
        if let continuation = accelerometerNotificationContinuation {
            continuation.resume(throwing: DeviceError.connectionLost)
            accelerometerNotificationContinuation = nil
            Logger.shared.info("[OralableDevice] Cancelled pending accelerometer notification continuation")
        }
        
        // Fix 3: Cancel connection ready waiting
        if let continuation = connectionReadyContinuation {
            continuation.resume(throwing: DeviceError.connectionLost)
            connectionReadyContinuation = nil
            Logger.shared.info("[OralableDevice] Cancelled pending connection ready continuation")
        }
        
        // Fix 3: Reset connection readiness state
        notificationReadiness = []
        Logger.shared.info("[OralableDevice] Reset notification readiness state")
    }

    // MARK: - Data Collection Control

    func startDataCollection() async throws {
        guard let peripheral = peripheral else {
            throw DeviceError.invalidPeripheral("Peripheral is nil")
        }

        guard peripheral.state == .connected else {
            throw DeviceError.notConnected("Peripheral not connected")
        }
        
        Logger.shared.info("[OralableDevice] Starting data collection...")
        
        // Fix 3: Wait for BLE connection to be fully ready before collecting data
        // This prevents the race condition where recording starts before notifications are enabled
        if !isConnectionReady {
            Logger.shared.info("[OralableDevice] ⏳ Waiting for BLE notifications to be ready...")
            try await waitForConnectionReady(timeout: 10.0)
        }
        
        isCollecting = true
        sessionStartTime = Date()
        packetsReceived = 0
        bytesReceived = 0
        ppgFrameCount = 0

        // Reset sample rate stats for new session
        sampleRateStats.reset()
        Logger.shared.info("[SAMPLE_RATE_CHECK] Logging enabled - iOS assumes \(ppgSampleRate) Hz")

        Logger.shared.info("[OralableDevice] ✅ Data collection started (notifications confirmed ready)")
    }
    
    func stopDataCollection() async throws {
        Logger.shared.info("[OralableDevice] Stopping data collection...")

        // Log final sample rate statistics
        let stats = sampleRateStats
        if stats.packetCount > 10 {
            let samplesPerSecond = stats.packetsPerSecond * Double(ppgSamplesPerPacket)
            Logger.shared.info("[SAMPLE_RATE_CHECK] FINAL: \(stats.packetCount) packets over \(String(format: "%.2f", stats.totalDuration))s | Avg interval: \(String(format: "%.2f", stats.averageInterval * 1000))ms | SAMPLES/sec: \(String(format: "%.1f", samplesPerSecond)) | MISMATCH: \(String(format: "%.2f", samplesPerSecond / ppgSampleRate))x")
        }

        isCollecting = false
        
        if let startTime = sessionStartTime {
            let duration = Date().timeIntervalSince(startTime)
            Logger.shared.info("[OralableDevice] Session duration: \(String(format: "%.1f", duration))s")
            Logger.shared.info("[OralableDevice] Packets received: \(packetsReceived)")
            Logger.shared.info("[OralableDevice] Bytes received: \(bytesReceived)")
            Logger.shared.info("[OralableDevice] PPG frames: \(ppgFrameCount)")
        }
        
        sessionStartTime = nil
        
        Logger.shared.info("[OralableDevice] ✅ Data collection stopped")
    }
    
    // MARK: - Connection Readiness (Fix 3)
    
    /// Wait for BLE connection to be fully ready for data collection
    /// This ensures service discovery and notification enabling is complete before recording starts
    /// - Parameter timeout: Maximum time to wait in seconds (default 10s)
    /// - Throws: DeviceError.timeout if readiness not achieved within timeout
    func waitForConnectionReady(timeout: TimeInterval = 10.0) async throws {
        // If already ready, return immediately
        if isConnectionReady {
            Logger.shared.info("[OralableDevice] ✅ Connection already ready")
            return
        }
        
        Logger.shared.info("[OralableDevice] ⏳ Waiting for connection readiness (timeout: \(timeout)s)...")
        Logger.shared.info("[OralableDevice] Current state: \(notificationReadiness), need: \(NotificationReadiness.allRequired)")
        
        // Wait for notifications to be confirmed with timeout
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectionReadyContinuation = continuation
            
            // Set up timeout task
            Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                
                // If continuation still exists, we timed out
                if let pendingContinuation = self.connectionReadyContinuation {
                    self.connectionReadyContinuation = nil
                    
                    Logger.shared.error("[OralableDevice] ❌ Connection readiness timeout after \(timeout)s")
                    Logger.shared.error("[OralableDevice] State at timeout: \(self.notificationReadiness)")
                    
                    pendingContinuation.resume(throwing: DeviceError.timeout)
                }
            }
        }
        
        Logger.shared.info("[OralableDevice] ✅ Connection ready confirmed")
    }

    // MARK: - Protocol Required Methods

    func connect() async throws {
        // Connection is handled by DeviceManager/BLECentralManager
        Logger.shared.info("[OralableDevice] Connect called - handled by BLE manager")
    }

    func disconnect() async {
        Logger.shared.info("[OralableDevice] Disconnect called")
    }

    func isAvailable() -> Bool {
        peripheral != nil
    }

    func startDataStream() async throws {
        try await startDataCollection()
    }

    func stopDataStream() async {
        try? await stopDataCollection()
    }

    func requestReading(for sensorType: SensorType) async throws -> SensorReading? {
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
        // Configuration updates handled via commands
        Logger.shared.info("[OralableDevice] Configuration update requested")
    }

    func updateDeviceInfo() async throws {
        Logger.shared.info("[OralableDevice] Device info update requested")
    }

    // MARK: - Data Parsing (Fix 2: Proper timestamps, Fix 6: Fixed firmware byte order)

    /// Maps byte offset index (0, 1, 2) to SensorType based on ACTUAL firmware byte order
    ///
    /// IMPORTANT: The firmware struct definition in tgm_service.h says { red, ir, green }
    /// but the ACTUAL FIFO data order observed from live logs is [Green, IR, Red]:
    /// - Offset 0: Green LED data (PA=0 when worn, produces ~0-10)
    /// - Offset 4: IR LED data (PA=128, produces ~14000-15000)
    /// - Offset 8: Red LED data (PA=32, produces ~2000-2500)
    ///
    /// - Parameter offsetIndex: 0 = first uint32, 1 = second uint32, 2 = third uint32
    /// - Returns: The correct SensorType for that byte position
    private func sensorTypeForOffset(_ offsetIndex: Int) -> SensorType {
        // ACTUAL firmware order: [Green, IR, Red]
        switch offsetIndex {
        case 0: return .ppgGreen    // First uint32 = Green LED data
        case 1: return .ppgInfrared // Second uint32 = IR LED data
        case 2: return .ppgRed      // Third uint32 = Red LED data
        default: return .ppgInfrared
        }
    }

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

        // Helper to read UInt32 little-endian
        func readUInt32(at offset: Int) -> UInt32? {
            guard offset + 3 < data.count else { return nil }
            return data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            }
        }

        // PPG packet format (from firmware tgm_service.h):
        // Bytes 0-3: Frame counter (uint32_t)
        // Bytes 4+: 20 samples, each 12 bytes (3 × uint32_t PPG values)
        // The order of the 3 values depends on firmware config - use ppgChannelOrder setting
        let frameCounter = readUInt32(at: 0) ?? 0

        // Log every packet for sample rate analysis
        Logger.shared.info("[RATE] Frame \(frameCounter) at \(Date().timeIntervalSince1970)")

        let samplesPerFrame = ppgSamplesPerPacket  // 20
        let sampleSizeBytes = 12  // 3 × uint32_t per sample
        let sampleDataStart = 4

        // Sample rate verification logging
        sampleRateStats.recordPacket(time: notificationTime, frameCounter: frameCounter)

        if sampleRateStats.packetCount % 50 == 0 && sampleRateStats.packetCount > 0 {
            let stats = sampleRateStats
            let samplesPerSecond = stats.recentPacketsPerSecond * Double(ppgSamplesPerPacket)
            Logger.shared.info("[SAMPLE_RATE_CHECK] Packet #\(stats.packetCount) | Interval: \(String(format: "%.2f", stats.recentAverageInterval * 1000))ms | Packets/sec: \(String(format: "%.2f", stats.recentPacketsPerSecond)) | SAMPLES/sec: \(String(format: "%.1f", samplesPerSecond)) (iOS assumes \(ppgSampleRate))")
        }

        #if DEBUG
        Logger.shared.debug("[OralableDevice] 📊 PPG Frame #\(frameCounter) | Samples: \(samplesPerFrame) | Size: \(data.count) bytes")
        #endif

        // Verify packet size
        let expectedSize = sampleDataStart + (samplesPerFrame * sampleSizeBytes)  // 4 + 240 = 244
        guard data.count >= expectedSize else {
            Logger.shared.warning("[OralableDevice] ⚠️ PPG packet size mismatch: got \(data.count), expected \(expectedSize)")
            return
        }

        // Fix 2: Calculate proper timestamps for each sample
        // Notification arrives at "now", samples are 10ms apart at 100 sps
        // Sample 0 is oldest, sample 19 is newest (most recent)
        let sampleInterval = 1.0 / ppgSampleRate  // 0.01 seconds = 10ms

        var readings: [SensorReading] = []

        // FIX: Use hardware frame number for deterministic grouping
        // This eliminates timestamp-based grouping issues in SensorDataProcessor
        for i in 0..<samplesPerFrame {
            let sampleOffset = sampleDataStart + (i * sampleSizeBytes)

            guard sampleOffset + sampleSizeBytes <= data.count else {
                Logger.shared.warning("[OralableDevice] ⚠️ PPG sample \(i) exceeds data bounds")
                break
            }

            // Calculate timestamp - sample 0 is oldest (190ms ago), sample 19 is newest (now)
            let sampleAge = Double(samplesPerFrame - 1 - i) * sampleInterval
            let sampleTimestamp = notificationTime.addingTimeInterval(-sampleAge)

            // Calculate per-sample frame number for deterministic grouping
            // Each packet has 20 samples, so multiply packet frame by 20 and add sample index
            let sampleFrameNumber = frameCounter * UInt32(samplesPerFrame) + UInt32(i)

            // Read all 3 PPG values for this sample at once
            guard let value0 = readUInt32(at: sampleOffset),
                  let value1 = readUInt32(at: sampleOffset + 4),
                  let value2 = readUInt32(at: sampleOffset + 8) else {
                Logger.shared.warning("[OralableDevice] ⚠️ Failed to read PPG sample \(i)")
                continue
            }

            // Map values to channels based on firmware documentation byte order [Red, IR, Green]
            // From tgm_service.h struct:
            // - Offset 0 (value0) = Red (PA=32, expected ~2000-2500)
            // - Offset 4 (value1) = IR (PA=128, expected ~14000-15000)
            // - Offset 8 (value2) = Green (PA=0 when worn, expected ~0-10)
            let redValue = value0    // Offset 0 = Red
            let irValue = value1     // Offset 4 = IR
            let greenValue = value2  // Offset 8 = Green

            // Create readings with correct sensor types
            // All 3 channels share the same frameNumber for deterministic grouping
            let deviceId = peripheral?.identifier.uuidString

            readings.append(SensorReading(
                sensorType: .ppgRed,
                value: Double(redValue),
                timestamp: sampleTimestamp,
                deviceId: deviceId,
                quality: redValue > 1000 ? 0.9 : 0.3,
                frameNumber: sampleFrameNumber
            ))

            readings.append(SensorReading(
                sensorType: .ppgInfrared,
                value: Double(irValue),
                timestamp: sampleTimestamp,
                deviceId: deviceId,
                quality: irValue > 10000 ? 0.9 : 0.3,
                frameNumber: sampleFrameNumber
            ))

            readings.append(SensorReading(
                sensorType: .ppgGreen,
                value: Double(greenValue),
                timestamp: sampleTimestamp,
                deviceId: deviceId,
                quality: 0.5,
                frameNumber: sampleFrameNumber
            ))

            // Log PPG values periodically for debugging channel mapping
            if i == 0 && ppgFrameCount % 50 == 0 {
                Logger.shared.info("[OralableDevice] 📊 PPG Frame #\(ppgFrameCount) sample #\(sampleFrameNumber) | Red=\(redValue) IR=\(irValue) Green=\(greenValue)")
            }
        }

        // Batch update latestReadings ONCE after loop
        var latestByType: [SensorType: SensorReading] = [:]
        for reading in readings {
            latestByType[reading.sensorType] = reading
        }

        for (type, reading) in latestByType {
            latestReadings[type] = reading
        }

        // Emit batch for downstream consumers
        if !readings.isEmpty {
            readingsBatchSubject.send(readings)

            ppgFrameCount += 1

            #if DEBUG
            if ppgFrameCount % 100 == 0 {
                Logger.shared.debug("[OralableDevice] 📊 PPG Frame #\(ppgFrameCount): \(readings.count) readings")
            }
            #endif
        }
    }

    // MARK: - Temperature Parsing

    private func parseTemperature(_ data: Data) {
        // Temperature packet format (8 bytes):
        // Bytes 0-3: Frame counter
        // Bytes 4-5: Temperature (int16, centidegrees Celsius)
        guard data.count >= 6 else {
            Logger.shared.warning("[OralableDevice] ⚠️ Temperature packet too small: \(data.count) bytes")
            return
        }

        func readInt16(at offset: Int) -> Int16? {
            guard offset + 1 < data.count else { return nil }
            return data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: offset, as: Int16.self)
            }
        }

        func readUInt32(at offset: Int) -> UInt32? {
            guard offset + 3 < data.count else { return nil }
            return data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            }
        }

        let frameCounter = readUInt32(at: 0) ?? 0
        guard let centitemp = readInt16(at: 4) else {
            Logger.shared.warning("[OralableDevice] ⚠️ Failed to parse temperature value")
            return
        }

        // Convert centidegrees to degrees
        let tempCelsius = Double(centitemp) / 100.0

        Logger.shared.debug("[OralableDevice] 🌡️ Temperature: \(String(format: "%.2f", tempCelsius))°C (frame #\(frameCounter))")

        let reading = SensorReading(
            sensorType: .temperature,
            value: tempCelsius,
            timestamp: Date(),
            deviceId: peripheral?.identifier.uuidString
        )

        latestReadings[.temperature] = reading
        readingsBatchSubject.send([reading])
    }

    // MARK: - Accelerometer Parsing (Fix 2: Proper timestamps)

    private func parseAccelerometerData(_ data: Data) {
        // Accelerometer packet format (154 bytes):
        // Bytes 0-3: Frame counter (uint32_t)
        // Bytes 4+: 25 samples, each 6 bytes (3 × int16_t for X, Y, Z)

        let notificationTime = Date()

        func readInt16(at offset: Int) -> Int16? {
            guard offset + 1 < data.count else { return nil }
            return data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: offset, as: Int16.self)
            }
        }

        func readUInt32(at offset: Int) -> UInt32? {
            guard offset + 3 < data.count else { return nil }
            return data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            }
        }

        let frameCounter = readUInt32(at: 0) ?? 0
        let sampleSizeBytes = 6  // 3 × int16_t per sample
        let sampleDataStart = 4
        let expectedSize = sampleDataStart + (accelerometerSamplesPerPacket * sampleSizeBytes)  // 4 + 150 = 154

        Logger.shared.debug("[OralableDevice] 🏃 Accelerometer packet | Size: \(data.count) bytes (expected: \(expectedSize))")

        // Calculate actual samples in packet (may be less than expected if packet truncated)
        let availableDataBytes = data.count - sampleDataStart
        let actualSamples = min(accelerometerSamplesPerPacket, availableDataBytes / sampleSizeBytes)

        guard actualSamples > 0 else {
            Logger.shared.warning("[OralableDevice] ⚠️ No accelerometer samples in packet")
            return
        }

        // Fix 2: Calculate proper timestamps for each sample
        // Samples are 10ms apart at 100 Hz
        let sampleInterval = 1.0 / accelerometerSampleRate  // 0.01 seconds = 10ms

        var readings: [SensorReading] = []

        for i in 0..<actualSamples {
            let sampleOffset = sampleDataStart + (i * sampleSizeBytes)

            // Calculate timestamp - sample 0 is oldest (240ms ago), sample 24 is newest (now)
            let sampleAge = Double(actualSamples - 1 - i) * sampleInterval
            let sampleTimestamp = notificationTime.addingTimeInterval(-sampleAge)

            // Calculate per-sample frame number for deterministic grouping
            // Each packet has 25 samples, so multiply packet frame by 25 and add sample index
            // Use high bit to distinguish accel frames from PPG frames
            let sampleFrameNumber = (frameCounter * UInt32(accelerometerSamplesPerPacket) + UInt32(i)) | 0x80000000

            let deviceId = peripheral?.identifier.uuidString

            // Accelerometer X (bytes 0-1)
            if let accelX = readInt16(at: sampleOffset) {
                readings.append(SensorReading(
                    sensorType: .accelerometerX,
                    value: Double(accelX),
                    timestamp: sampleTimestamp,
                    deviceId: deviceId,
                    frameNumber: sampleFrameNumber
                ))
            }

            // Accelerometer Y (bytes 2-3)
            if let accelY = readInt16(at: sampleOffset + 2) {
                readings.append(SensorReading(
                    sensorType: .accelerometerY,
                    value: Double(accelY),
                    timestamp: sampleTimestamp,
                    deviceId: deviceId,
                    frameNumber: sampleFrameNumber
                ))
            }

            // Accelerometer Z (bytes 4-5)
            if let accelZ = readInt16(at: sampleOffset + 4) {
                readings.append(SensorReading(
                    sensorType: .accelerometerZ,
                    value: Double(accelZ),
                    timestamp: sampleTimestamp,
                    deviceId: deviceId,
                    frameNumber: sampleFrameNumber
                ))
            }
        }

        // Batch update latestReadings ONCE after loop
        var latestByType: [SensorType: SensorReading] = [:]
        for reading in readings {
            latestByType[reading.sensorType] = reading
        }

        for (type, reading) in latestByType {
            latestReadings[type] = reading
        }

        // Emit batch
        if !readings.isEmpty {
            readingsBatchSubject.send(readings)

            // Log first sample values for debugging
            #if DEBUG
            if let x = latestByType[.accelerometerX]?.value,
               let y = latestByType[.accelerometerY]?.value,
               let z = latestByType[.accelerometerZ]?.value {
                Logger.shared.debug("[OralableDevice] 🏃 Accel (frame #\(frameCounter)): X=\(Int(x)), Y=\(Int(y)), Z=\(Int(z)) | \(actualSamples) samples")
            }
            #endif
        } else {
            Logger.shared.warning("[OralableDevice] ⚠️ No accelerometer readings parsed from \(data.count) byte packet")
        }
    }

    // MARK: - Battery Parsing

    private func parseBatteryData(_ data: Data) {
        // Battery packet: 4 bytes (int32_t millivolts)
        guard data.count >= 4 else {
            Logger.shared.warning("[OralableDevice] ⚠️ Battery packet too small: \(data.count) bytes")
            return
        }

        let millivolts = data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: 0, as: Int32.self)
        }

        // Use BatteryConversion for accurate LiPo curve
        let percentage = BatteryConversion.voltageToPercentage(millivolts: millivolts)
        let status = BatteryConversion.batteryStatus(percentage: percentage)

        Logger.shared.info("[OralableDevice] 🔋 Battery: \(millivolts)mV → \(String(format: "%.0f", percentage))% [\(status.rawValue)]")

        if BatteryConversion.needsCharging(percentage: percentage) {
            if BatteryConversion.isCritical(percentage: percentage) {
                Logger.shared.warning("[OralableDevice] ⚠️ BATTERY CRITICAL: \(String(format: "%.0f", percentage))%")
            } else {
                Logger.shared.warning("[OralableDevice] ⚠️ Battery low: \(String(format: "%.0f", percentage))%")
            }
        }

        batteryLevel = Int(percentage)

        let reading = SensorReading(
            sensorType: .battery,
            value: percentage,
            timestamp: Date(),
            deviceId: peripheral?.identifier.uuidString
        )

        latestReadings[.battery] = reading
        readingsBatchSubject.send([reading])
    }

    // MARK: - Standard Battery Level (0-100%)

    private func parseStandardBatteryLevel(_ data: Data) {
        guard data.count >= 1 else {
            Logger.shared.warning("[OralableDevice] ⚠️ Standard battery level packet too small")
            return
        }

        let level = Int(data[0])
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
                    // Enable notifications for battery level
                    peripheral.setNotifyValue(true, for: characteristic)
                    // Also read initial value
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

            case accelerometerCharUUID:  // Fix 1: Renamed
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

        if foundCount >= 1 {  // At minimum need sensor data characteristic
            Logger.shared.info("[OralableDevice] ✅ Found \(foundCount)/4 expected characteristics")
            characteristicDiscoveryContinuation?.resume()
            characteristicDiscoveryContinuation = nil
        } else {
            Logger.shared.error("[OralableDevice] ❌ Required characteristics not found")
            characteristicDiscoveryContinuation?.resume(throwing: DeviceError.characteristicNotFound("Required characteristics not found (found \(foundCount)/3)"))
            characteristicDiscoveryContinuation = nil
        }
    }

    // Fix 3: Updated notification state handler with readiness tracking
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Logger.shared.error("[OralableDevice] ❌ Notification state update failed: \(error.localizedDescription)")

            // Resume continuations with error
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

        // Fix 3: Track which notifications are ready
        if characteristic.isNotifying {
            switch characteristic.uuid {
            case sensorDataCharUUID:
                notificationReadiness.insert(.ppgData)
                Logger.shared.info("[OralableDevice] 📡 PPG notifications confirmed ready")
                notificationEnableContinuation?.resume()
                notificationEnableContinuation = nil

            case accelerometerCharUUID:  // Fix 1: Renamed
                notificationReadiness.insert(.accelerometer)
                Logger.shared.info("[OralableDevice] 📡 Accelerometer notifications confirmed ready")
                accelerometerNotificationContinuation?.resume()
                accelerometerNotificationContinuation = nil

            case commandCharUUID:
                notificationReadiness.insert(.temperature)
                Logger.shared.info("[OralableDevice] 📡 Temperature notifications confirmed ready")

            case batteryLevelCharUUID:
                notificationReadiness.insert(.battery)
                Logger.shared.info("[OralableDevice] 📡 Battery notifications confirmed ready")

            default:
                Logger.shared.debug("[OralableDevice] 📡 Unknown characteristic notifications enabled: \(charName)")
            }

            // Fix 3: Check if we're now fully ready for data collection
            Logger.shared.info("[OralableDevice] Readiness state: \(notificationReadiness) (need: \(NotificationReadiness.allRequired))")

            if isConnectionReady {
                Logger.shared.info("[OralableDevice] 🎉 Connection fully ready - all required notifications enabled")

                // Resume anyone waiting for readiness
                if let continuation = connectionReadyContinuation {
                    connectionReadyContinuation = nil
                    continuation.resume()
                }
            }
        } else {
            // Notification was disabled - remove from readiness
            switch characteristic.uuid {
            case sensorDataCharUUID:
                notificationReadiness.remove(.ppgData)
            case accelerometerCharUUID:
                notificationReadiness.remove(.accelerometer)
            case commandCharUUID:
                notificationReadiness.remove(.temperature)
            case batteryLevelCharUUID:
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
            // PPG data (244 bytes typically)
            Logger.shared.debug("[OralableDevice] 📦 Received \(data.count) bytes on characteristic: \(characteristic.uuid.uuidString.prefix(8))...")
            parseSensorData(data)

        case accelerometerCharUUID:
            // Accelerometer data (154 bytes typically)
            Logger.shared.debug("[OralableDevice] 📦 Received \(data.count) bytes on characteristic: \(characteristic.uuid.uuidString.prefix(8))...")
            parseAccelerometerData(data)

        case commandCharUUID:
            // Temperature data (8 bytes typically)
            Logger.shared.debug("[OralableDevice] 📦 Received \(data.count) bytes on characteristic: \(characteristic.uuid.uuidString.prefix(8))...")
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

