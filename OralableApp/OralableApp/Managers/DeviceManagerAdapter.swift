//
//  DeviceManagerAdapter.swift
//  OralableApp
//
//  Adapts raw sensor data from DeviceManager to published properties.
//
//  Responsibilities:
//  - Receives sensor readings from DeviceManager
//  - Updates published properties for UI binding
//  - Maintains local sensor data history
//  - Forwards data to SensorDataProcessor for storage
//
//  Published Properties:
//  - ppgIRValue, ppgRedValue, ppgGreenValue
//  - accelX, accelY, accelZ (raw LSB values)
//  - temperature
//  - batteryLevel
//
//  History Buffer:
//  - Maintains recent samples for real-time charts
//  - Limited size to prevent memory issues
//
//  Created: November 24, 2025
//  Updated: December 8, 2025 - Fixed battery tracking for dual-device
//

import Foundation
import Combine
import CoreBluetooth
import OralableCore

/// Adapter that wraps DeviceManager and conforms to BLEManagerProtocol
/// This allows existing ViewModels (like DashboardViewModel) to work with DeviceManager
@MainActor
final class DeviceManagerAdapter: ObservableObject, BLEManagerProtocol {

    // MARK: - Dependencies

    private let deviceManager: DeviceManager
    private let sensorDataProcessor: SensorDataProcessor
    private let sessionHistoryStore: SessionHistoryStore?
    private let unifiedBiometricProcessor = UnifiedBiometricProcessor()
    private let bioMetricCalculator = BioMetricCalculator()
    private let heartRateCalculator = HeartRateCalculator(sampleRate: 50.0)
    private var cancellables = Set<AnyCancellable>()
    private let deviceStateDetector = DeviceStateDetector()
    private var sensorDataBuffer: [SensorData] = []
    private let sensorDataBufferLimit = 20
    private var emgSessionPeak: Double = 1

    // Local sensor data history (since SensorDataProcessor's history is private(set))
    private var localSensorDataHistory: [SensorData] = []
    private let maxLocalHistoryCount = 10000

    // MARK: - Published Properties (conforming to BLEManagerProtocol)

    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    @Published var deviceName: String = "Unknown Device"
    @Published var connectionState: String = "Disconnected"
    @Published var deviceUUID: UUID?
    @Published var heartRate: Int = 0
    @Published var spO2: Int = 0
    @Published var heartRateQuality: Double = 0.0
    @Published var temperature: Double = 0.0
    @Published var batteryLevel: Double = 0.0
    @Published var accelX: Double = 0.0
    @Published var accelY: Double = 0.0
    @Published var accelZ: Double = 0.0
    @Published var ppgRedValue: Double = 0.0
    @Published var ppgIRValue: Double = 0.0
    @Published var ppgGreenValue: Double = 0.0
    @Published var emgValue: Double = 0.0  // EMG value from ANR M40
    /// Session-peak–normalized EMG (0–100) for dual REV10 + ANR secondary card.
    @Published private(set) var emgActivityPercent: Double = 0
    @Published var isRecording: Bool = false
    @Published var deviceState: DeviceStateResult?

    @Published var temporalisFatigueIndexPercent: Double = 50
    @Published private(set) var latestTemporalisProbabilities: TemporalisProbabilities?

    // MARK: - Initialization

    init(deviceManager: DeviceManager, sensorDataProcessor: SensorDataProcessor, sessionHistoryStore: SessionHistoryStore? = nil) {
        self.deviceManager = deviceManager
        self.sensorDataProcessor = sensorDataProcessor
        self.sessionHistoryStore = sessionHistoryStore
        setupBindings()
        Task {
            await unifiedBiometricProcessor.setOnTemporalisProbabilities { [weak self] probs in
                Task { @MainActor in
                    self?.latestTemporalisProbabilities = probs
                    self?.sessionHistoryStore?.recordTemporalis(probs, at: Date())
                }
            }
        }
        Logger.shared.info("[DeviceManagerAdapter] Initialized with DeviceManager and SensorDataProcessor")
    }

    // MARK: - Setup Bindings

    private func setupBindings() {
        // Bind connection state
        deviceManager.$connectedDevices
            .map { !$0.isEmpty }
            .assign(to: &$isConnected)

        deviceManager.$isScanning
            .assign(to: &$isScanning)

        // Bind primary device info
        deviceManager.$primaryDevice
            .map { $0?.name ?? "Unknown Device" }
            .assign(to: &$deviceName)

        deviceManager.$primaryDevice
            .map { $0?.peripheralIdentifier }
            .assign(to: &$deviceUUID)

        // Bind connection state string
        deviceManager.$connectedDevices
            .map { $0.isEmpty ? "Disconnected" : "Connected" }
            .assign(to: &$connectionState)

        // Live metrics, history, and biometrics all arrive via readingsBatchPublisher (see below).

        // Single 100ms pipeline: history + unified biometrics (one Task per tick, no per-packet work)
        let biometricProcessor = unifiedBiometricProcessor
        deviceManager.readingsBatchPublisher
            .collect(.byTime(DispatchQueue.global(qos: .userInitiated), .milliseconds(100)))
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] batches in
                guard let self else { return }
                let flat = batches.flatMap { $0 }
                guard !flat.isEmpty else { return }
                let processor = biometricProcessor
                Task.detached(priority: .userInitiated) { [weak self, processor, flat] in
                    guard let self else { return }
                    let latestByType = DeviceManagerAdapter.latestBySensorType(from: flat)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.ingestLiveMetricsFromLatestReadings(latestByType)
                        let oral = DeviceManagerAdapter.oralableSensorDataRows(
                            from: flat,
                            heartRate: self.heartRate,
                            heartRateQuality: self.heartRateQuality,
                            temperature: self.temperature,
                            batteryLevel: self.batteryLevel
                        )
                        let anr = DeviceManagerAdapter.anrSensorDataRows(from: flat)
                        if !oral.isEmpty || !anr.isEmpty {
                            let allNew = oral + anr
                            self.applyStreamingHistoryRows(oral: oral, anr: anr)
                            self.deviceManager.appendBatchToUnifiedSensorStream(allNew)
                        }
                    }

                    let arrays = DeviceManagerAdapter.biometricSampleArrays(from: flat)
                    guard !arrays.ir.isEmpty else { return }

                    let result = await processor.processBatch(
                        irSamples: arrays.ir,
                        redSamples: arrays.red,
                        greenSamples: arrays.green,
                        accelX: arrays.ax,
                        accelY: arrays.ay,
                        accelZ: arrays.az,
                        resetState: false
                    )

                    let ts = Date()
                    let tfi = result.tfiPercent
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        let spo2Percent = self.spO2 > 0 ? Double(self.spO2) : nil
                        self.temporalisFatigueIndexPercent = tfi
                        self.sessionHistoryStore?.recordTFI(percent: tfi, at: ts)
                        self.sessionHistoryStore?.recordSpO2Sample(percent: spo2Percent, at: ts)
                    }
                }
            }
            .store(in: &cancellables)

        $isConnected
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] connected in
                guard let self = self else { return }
                if !connected {
                    self.sessionHistoryStore?.resetForDisconnect()
                    self.temporalisFatigueIndexPercent = 50
                    self.emgSessionPeak = 1
                    self.emgActivityPercent = 0
                    ANRMuscleClinicalDeviceAdapter.dashboardEmgActivityPercent = 0
                    Task { await self.unifiedBiometricProcessor.reset() }
                }
            }
            .store(in: &cancellables)

        Logger.shared.info("[DeviceManagerAdapter] Bindings configured - throttled UI, 100ms batch history + biometrics")
    }

    /// Batched `localSensorDataHistory` + `SensorDataProcessor` history (ring buffer updated alongside in batch sink).
    private func applyStreamingHistoryRows(oral oralRows: [SensorData], anr anrRows: [SensorData]) {
        let allNewRows = oralRows + anrRows
        guard !allNewRows.isEmpty else { return }

        localSensorDataHistory.append(contentsOf: allNewRows)
        if localSensorDataHistory.count > maxLocalHistoryCount {
            localSensorDataHistory.removeFirst(localSensorDataHistory.count - maxLocalHistoryCount)
        }

        sensorDataProcessor.appendBatchToHistory(allNewRows)
    }

    /// Apply latest-per-type readings from one batch window (main actor only).
    private func ingestLiveMetricsFromLatestReadings(_ readings: [SensorType: SensorReading]) {
        if let reading = readings[.heartRate] {
            heartRate = Int(reading.value)
        }
        if let reading = readings[.spo2] {
            spO2 = Int(reading.value)
        }
        if let reading = readings[.temperature] {
            temperature = reading.value
        }
        if let reading = readings[.battery] {
            batteryLevel = reading.value
        }
        if let reading = readings[.emg] {
            emgValue = reading.value
        }
        if let reading = readings[.muscleActivity] {
            emgValue = reading.value
        }
        if readings[.emg] != nil || readings[.muscleActivity] != nil, emgValue > 0 {
            emgSessionPeak = max(emgSessionPeak, emgValue)
            emgActivityPercent = min(100, (emgValue / emgSessionPeak) * 100)
            ANRMuscleClinicalDeviceAdapter.dashboardEmgActivityPercent = emgActivityPercent
        }
        if let reading = readings[.ppgRed] {
            ppgRedValue = reading.value
        }
        if let reading = readings[.ppgInfrared] {
            ppgIRValue = reading.value
            if ppgIRValue > 100 {
                if let calculatedHR = heartRateCalculator.process(irValue: ppgIRValue) {
                    if calculatedHR > 30 && calculatedHR < 200 {
                        heartRate = calculatedHR
                        heartRateQuality = 0.8
                    }
                }
            }
        }
        if let reading = readings[.ppgGreen] {
            ppgGreenValue = reading.value
        }
        if let reading = readings[.accelerometerX] {
            accelX = reading.value
        }
        if let reading = readings[.accelerometerY] {
            accelY = reading.value
        }
        if let reading = readings[.accelerometerZ] {
            accelZ = reading.value
        }
    }

    // MARK: - Heart Rate Calculation

    /// Calculate heart rate from the accumulated PPG IR buffer
    /// Note: This method has been disabled because the required buffer management
    /// methods don't exist in the current SensorDataProcessor implementation.
    /// Heart rate calculation is now handled directly by BioMetricCalculator.
    private func calculateHeartRateFromBuffer() async {
        // Disabled - see note above
        Logger.shared.debug("[DeviceManagerAdapter] calculateHeartRateFromBuffer called but disabled")
    }

    // MARK: - BLEManagerProtocol Methods

    func startScanning() {
        Task {
            await deviceManager.startScanning()
        }
    }

    func stopScanning() {
        deviceManager.stopScanning()
    }

    func connect(to peripheral: CBPeripheral) {
        // Find the DeviceInfo for this peripheral
        guard let deviceInfo = deviceManager.discoveredDevices.first(where: {
            $0.peripheralIdentifier == peripheral.identifier
        }) else {
            Logger.shared.error("[DeviceManagerAdapter] Cannot find DeviceInfo for peripheral: \(peripheral.identifier)")
            return
        }

        Task {
            do {
                try await deviceManager.connect(to: deviceInfo)
                Logger.shared.info("[DeviceManagerAdapter] Connected to device: \(deviceInfo.name)")
            } catch {
                Logger.shared.error("[DeviceManagerAdapter] Connection failed: \(error.localizedDescription)")
            }
        }
    }

    func disconnect() {
        Task {
            if let primaryDevice = deviceManager.primaryDevice {
                await deviceManager.disconnect(from: primaryDevice)
            } else {
                deviceManager.disconnectAll()
            }
        }
    }

    func startRecording() {
        isRecording = true
        Logger.shared.info("[DeviceManagerAdapter] Recording started")
    }

    func stopRecording() {
        isRecording = false
        Logger.shared.info("[DeviceManagerAdapter] Recording stopped")
    }

    func clearHistory() {
        deviceManager.clearReadings()
        sensorDataProcessor.clearHistory()
        sensorDataBuffer.removeAll()
        localSensorDataHistory.removeAll()
        deviceStateDetector.reset()
    }
    
    // MARK: - Data Access
    
    /// Access to the local sensor data history
    var sensorDataHistory: [SensorData] {
        return localSensorDataHistory
    }

    // MARK: - Publishers for Reactive UI

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
    var emgValuePublisher: Published<Double>.Publisher { $emgValue }  // EMG publisher for ANR M40
    var emgActivityPercentPublisher: Published<Double>.Publisher { $emgActivityPercent }
    var accelXPublisher: Published<Double>.Publisher { $accelX }
    var accelYPublisher: Published<Double>.Publisher { $accelY }
    var accelZPublisher: Published<Double>.Publisher { $accelZ }
    var isRecordingPublisher: Published<Bool>.Publisher { $isRecording }
    var deviceStatePublisher: Published<DeviceStateResult?>.Publisher { $deviceState }

    // MARK: - Device State Detection

    /// Updates device state by converting sensor readings to SensorData and analyzing via DeviceStateDetector
    private func updateDeviceState(from readings: [SensorReading]) {
        guard let sensorData = convertToSensorData(from: readings) else { return }

        // Add to buffer
        sensorDataBuffer.append(sensorData)

        // Trim buffer to limit
        if sensorDataBuffer.count > sensorDataBufferLimit {
            sensorDataBuffer.removeFirst(sensorDataBuffer.count - sensorDataBufferLimit)
        }

        // Analyze device state
        if let result = deviceStateDetector.analyzeDeviceState(sensorData: sensorDataBuffer) {
            self.deviceState = result
        }
    }

    /// Newest `SensorReading` per `SensorType` within a BLE batch (for live UI without `$latestReadings`).
    nonisolated private static func latestBySensorType(from flat: [SensorReading]) -> [SensorType: SensorReading] {
        var best: [SensorType: SensorReading] = [:]
        for r in flat {
            if let existing = best[r.sensorType] {
                if r.timestamp >= existing.timestamp { best[r.sensorType] = r }
            } else {
                best[r.sensorType] = r
            }
        }
        return best
    }

    /// Aligns PPG triplets to tight per-sample time-buckets; carries last known accel sample per PPG row.
    nonisolated static func biometricSampleArrays(from readings: [SensorReading]) -> (
        ir: [Double], red: [Double], green: [Double], ax: [Double], ay: [Double], az: [Double]
    ) {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        var lastAx = 0.0, lastAy = 0.0, lastAz = 16384.0
        var ir: [Double] = []
        var red: [Double] = []
        var green: [Double] = []
        var ax: [Double] = []
        var ay: [Double] = []
        var az: [Double] = []

        var bucket: [SensorType: Double] = [:]
        var bucketKey: Int64?

        func flushBucket() {
            guard let irv = bucket[.ppgInfrared],
                  let redv = bucket[.ppgRed],
                  let greenv = bucket[.ppgGreen] else {
                bucket.removeAll(keepingCapacity: true)
                return
            }
            ir.append(irv)
            red.append(redv)
            green.append(greenv)
            ax.append(lastAx)
            ay.append(lastAy)
            az.append(lastAz)
            bucket.removeAll(keepingCapacity: true)
        }

        for r in sorted {
            switch r.sensorType {
            case .accelerometerX:
                lastAx = r.value
            case .accelerometerY:
                lastAy = r.value
            case .accelerometerZ:
                lastAz = r.value
            case .ppgRed, .ppgInfrared, .ppgGreen:
                let key = ppgSampleBucketKey(for: r)
                if bucketKey != key {
                    flushBucket()
                    bucketKey = key
                }
                bucket[r.sensorType] = r.value
            default:
                break
            }
        }
        flushBucket()

        return (ir, red, green, ax, ay, az)
    }

    /// One `SensorData` row per aligned PPG triplet in the batch (same bucketing as biometrics).
    nonisolated static func oralableSensorDataRows(
        from readings: [SensorReading],
        heartRate: Int,
        heartRateQuality: Double,
        temperature: Double,
        batteryLevel: Double
    ) -> [SensorData] {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        var lastAx = 0.0, lastAy = 0.0, lastAz = 16384.0
        var out: [SensorData] = []
        out.reserveCapacity(sorted.count / 3)

        var bucket: [SensorType: Double] = [:]
        var bucketKey: Int64?
        var bucketTime: Date?

        func flushBucket() {
            defer {
                bucket.removeAll(keepingCapacity: true)
                bucketTime = nil
            }
            guard let irv = bucket[.ppgInfrared],
                  let redv = bucket[.ppgRed],
                  let greenv = bucket[.ppgGreen],
                  let ts = bucketTime,
                  irv > 100 else { return }

            let hrData: HeartRateData? = heartRate > 0
                ? HeartRateData(bpm: Double(heartRate), quality: heartRateQuality, timestamp: ts)
                : nil

            let row = SensorData(
                timestamp: ts,
                ppg: PPGData(red: Int32(redv), ir: Int32(irv), green: Int32(greenv), timestamp: ts),
                accelerometer: AccelerometerData(
                    x: Int16(clamping: Int(lastAx)),
                    y: Int16(clamping: Int(lastAy)),
                    z: Int16(clamping: Int(lastAz)),
                    timestamp: ts
                ),
                temperature: TemperatureData(celsius: temperature, timestamp: ts),
                battery: BatteryData(percentage: Int(batteryLevel), timestamp: ts),
                heartRate: hrData,
                spo2: nil,
                deviceType: .oralable
            )
            out.append(row)
        }

        for r in sorted {
            switch r.sensorType {
            case .accelerometerX:
                lastAx = r.value
            case .accelerometerY:
                lastAy = r.value
            case .accelerometerZ:
                lastAz = r.value
            case .ppgRed, .ppgInfrared, .ppgGreen:
                let key = ppgSampleBucketKey(for: r)
                if bucketKey != key {
                    flushBucket()
                    bucketKey = key
                }
                bucket[r.sensorType] = r.value
                bucketTime = r.timestamp
            default:
                break
            }
        }
        flushBucket()
        return out
    }

    /// Packet frame numbers identify BLE packets, not individual samples within a multi-sample packet.
    nonisolated static func ppgSampleBucketKey(for reading: SensorReading) -> Int64 {
        Int64((reading.timestamp.timeIntervalSinceReferenceDate * 10_000.0).rounded())
    }

    nonisolated private static func anrSensorDataRows(from readings: [SensorReading]) -> [SensorData] {
        let emgReadings = readings.filter { $0.sensorType == .emg || $0.sensorType == .muscleActivity }
        guard let last = emgReadings.last, last.value > 0 else { return [] }
        let ts = last.timestamp
        let row = SensorData(
            timestamp: ts,
            ppg: PPGData(red: 0, ir: Int32(last.value), green: 0, timestamp: ts),
            accelerometer: AccelerometerData(x: 0, y: 0, z: 0, timestamp: ts),
            temperature: TemperatureData(celsius: 0, timestamp: ts),
            battery: BatteryData(percentage: 0, timestamp: ts),
            heartRate: nil,
            spo2: nil,
            deviceType: .anr
        )
        return [row]
    }

    /// Converts an array of SensorReading to a single SensorData object
    private func convertToSensorData(from readings: [SensorReading]) -> SensorData? {
        let now = Date()

        // Extract PPG values
        let ppgRed = readings.first { $0.sensorType == .ppgRed }?.value ?? 0
        let ppgIR = readings.first { $0.sensorType == .ppgInfrared }?.value ?? 0
        let ppgGreen = readings.first { $0.sensorType == .ppgGreen }?.value ?? 0

        // Extract accelerometer values - convert from g to raw units if needed
        // If abs(value) > 100, use as-is (already raw units); otherwise multiply by 16384.0
        let accelXRaw = readings.first { $0.sensorType == .accelerometerX }?.value ?? 0
        let accelYRaw = readings.first { $0.sensorType == .accelerometerY }?.value ?? 0
        let accelZRaw = readings.first { $0.sensorType == .accelerometerZ }?.value ?? 0

        let accelX: Int16 = Int16(clamping: Int(abs(accelXRaw) > 100 ? accelXRaw : accelXRaw * 16384.0))
        let accelY: Int16 = Int16(clamping: Int(abs(accelYRaw) > 100 ? accelYRaw : accelYRaw * 16384.0))
        let accelZ: Int16 = Int16(clamping: Int(abs(accelZRaw) > 100 ? accelZRaw : accelZRaw * 16384.0))

        // Extract temperature
        let temp = readings.first { $0.sensorType == .temperature }?.value ?? 0

        // Extract battery
        let battery = readings.first { $0.sensorType == .battery }?.value ?? 0

        // Extract heart rate if available
        let hrReading = readings.first { $0.sensorType == .heartRate }
        var heartRateData: HeartRateData? = nil
        if let hr = hrReading {
            heartRateData = HeartRateData(
                bpm: hr.value,
                quality: hr.quality ?? 0.5,
                timestamp: hr.timestamp
            )
        }

        // Create SensorData
        let ppgData = PPGData(
            red: Int32(ppgRed),
            ir: Int32(ppgIR),
            green: Int32(ppgGreen),
            timestamp: now
        )

        let accelerometerData = AccelerometerData(
            x: accelX,
            y: accelY,
            z: accelZ,
            timestamp: now
        )

        let temperatureData = TemperatureData(
            celsius: temp,
            timestamp: now
        )

        let batteryData = BatteryData(
            percentage: Int(battery),
            timestamp: now
        )

        return SensorData(
            timestamp: now,
            ppg: ppgData,
            accelerometer: accelerometerData,
            temperature: temperatureData,
            battery: batteryData,
            heartRate: heartRateData
        )
    }
}
