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
    private let bioMetricCalculator = BioMetricCalculator()
    private let heartRateCalculator = HeartRateCalculator(sampleRate: 50.0)
    private var cancellables = Set<AnyCancellable>()
    private let deviceStateDetector = DeviceStateDetector()
    private var sensorDataBuffer: [SensorData] = []
    private let sensorDataBufferLimit = 20
    
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
    @Published var isRecording: Bool = false
    @Published var deviceState: DeviceStateResult?

    // MARK: - Initialization

    init(deviceManager: DeviceManager, sensorDataProcessor: SensorDataProcessor) {
        self.deviceManager = deviceManager
        self.sensorDataProcessor = sensorDataProcessor
        setupBindings()
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

        // Bind latest sensor readings to individual properties (real-time display)
        deviceManager.$latestReadings
            .sink { [weak self] readings in
                self?.updateSensorValues(from: readings)
            }
            .store(in: &cancellables)

        // DISABLED: Batch publisher subscription caused PPG rotation bugs in CSV export
        // The batch grouping by timestamp had floating-point precision issues
        // Now using direct SensorData creation in updateSensorValues() instead
        //
        // deviceManager.readingsBatchPublisher
        //     .collect(.byTime(DispatchQueue.main, .seconds(3)))
        //     .sink { [weak self] batchesOfReadings in
        //         guard let self = self else { return }
        //         let allReadings = batchesOfReadings.flatMap { $0 }
        //         if !allReadings.isEmpty {
        //             Task {
        //                 await self.sensorDataProcessor.updateLegacySensorData(with: allReadings)
        //             }
        //         }
        //     }
        //     .store(in: &cancellables)

        Logger.shared.info("[DeviceManagerAdapter] Bindings configured - direct history storage enabled")
    }

    private func updateSensorValues(from readings: [SensorType: SensorReading]) {
        // DIAGNOSTIC: Log what readings we're receiving
        if !readings.isEmpty {
            let types = readings.keys.map { "\($0)" }.sorted().joined(separator: ", ")
            Logger.shared.info("[DeviceManagerAdapter] 📊 Received \(readings.count) reading types: [\(types)]")
        } else {
            Logger.shared.warning("[DeviceManagerAdapter] ⚠️ Received empty readings dictionary")
        }
        
        // Update heart rate
        if let reading = readings[.heartRate] {
            heartRate = Int(reading.value)
            Logger.shared.info("[DeviceManagerAdapter] ❤️ Heart Rate: \(heartRate) bpm")
        } else {
            Logger.shared.debug("[DeviceManagerAdapter] No heartRate reading in latest")
        }

        // Update SpO2
        if let reading = readings[.spo2] {
            spO2 = Int(reading.value)
            Logger.shared.info("[DeviceManagerAdapter] 🫁 SpO2: \(spO2)%")
        } else {
            Logger.shared.debug("[DeviceManagerAdapter] No spO2 reading in latest")
        }

        // Update temperature
        if let reading = readings[.temperature] {
            temperature = reading.value
            Logger.shared.info("[DeviceManagerAdapter] 🌡️ Temperature: \(String(format: "%.1f", temperature))°C")
        }

        // ✅ FIXED: Battery ONLY comes from Oralable device
        // ANR M40 does NOT have a battery characteristic - it doesn't report battery level
        if let reading = readings[.battery] {
            batteryLevel = reading.value
            
            // Battery readings ONLY come from Oralable hardware
            Logger.shared.info("[DeviceManagerAdapter] 🔋 Oralable Battery: \(Int(batteryLevel))%")
            
            // Note: Battery data is stored in SensorData objects created below,
            // so no need for separate updateBatteryLevel method
        }

        // Update EMG value (ANR M40)
        if let reading = readings[.emg] {
            emgValue = reading.value
            Logger.shared.debug("[DeviceManagerAdapter] ⚡ EMG: \(Int(emgValue)) µV")
        }

        // Also check for muscleActivity sensor type (alternative EMG source)
        if let reading = readings[.muscleActivity] {
            emgValue = reading.value
            Logger.shared.debug("[DeviceManagerAdapter] ⚡ Muscle Activity (EMG): \(Int(emgValue)) µV")
        }

        // Update PPG values
        if let reading = readings[.ppgRed] {
            ppgRedValue = reading.value
            Logger.shared.debug("[DeviceManagerAdapter] 🔴 PPG Red: \(Int(ppgRedValue))")
        }

        if let reading = readings[.ppgInfrared] {
            ppgIRValue = reading.value
            Logger.shared.debug("[DeviceManagerAdapter] 📡 PPG IR: \(Int(ppgIRValue))")

            // Calculate heart rate from IR signal using HeartRateCalculator
            if ppgIRValue > 100 {
                if let calculatedHR = heartRateCalculator.process(irValue: ppgIRValue) {
                    if calculatedHR > 30 && calculatedHR < 200 {
                        heartRate = calculatedHR
                        heartRateQuality = 0.8
                        Logger.shared.info("[DeviceManagerAdapter] ❤️ Calculated HR: \(heartRate) bpm")
                    }
                }
            }
        }

        if let reading = readings[.ppgGreen] {
            ppgGreenValue = reading.value
            Logger.shared.debug("[DeviceManagerAdapter] 🟢 PPG Green: \(Int(ppgGreenValue))")
        }

        // Update accelerometer values
        if let reading = readings[.accelerometerX] {
            accelX = reading.value
            Logger.shared.debug("[DeviceManagerAdapter] 📊 Accel X: \(Int(accelX))")
        }

        if let reading = readings[.accelerometerY] {
            accelY = reading.value
            Logger.shared.debug("[DeviceManagerAdapter] 📊 Accel Y: \(Int(accelY))")
        }

        if let reading = readings[.accelerometerZ] {
            accelZ = reading.value
            Logger.shared.debug("[DeviceManagerAdapter] 📊 Accel Z: \(Int(accelZ))")
        }

        // === Create separate SensorData entries for each device type ===
        // The latestReadings dictionary merges data from ALL connected devices,
        // so we need to create separate entries for Oralable and ANR M40
        let timestamp = Date()

        // Check what we received
        let hasEMG = readings[.emg] != nil || readings[.muscleActivity] != nil
        let hasPPGIR = readings[.ppgInfrared] != nil

        // Create Oralable entry if we have PPG data
        if hasPPGIR && ppgIRValue > 100 {
            let ppgData = PPGData(
                red: Int32(ppgRedValue),
                ir: Int32(ppgIRValue),
                green: Int32(ppgGreenValue),
                timestamp: timestamp
            )

            let accelData = AccelerometerData(
                x: Int16(clamping: Int(accelX)),
                y: Int16(clamping: Int(accelY)),
                z: Int16(clamping: Int(accelZ)),
                timestamp: timestamp
            )

            let tempData = TemperatureData(
                celsius: temperature,
                timestamp: timestamp
            )

            let batteryData = BatteryData(
                percentage: Int(batteryLevel),
                timestamp: timestamp
            )

            let hrData: HeartRateData? = heartRate > 0 ? HeartRateData(
                bpm: Double(heartRate),
                quality: heartRateQuality,
                timestamp: timestamp
            ) : nil

            let oralableSensorData = SensorData(
                timestamp: timestamp,
                ppg: ppgData,
                accelerometer: accelData,
                temperature: tempData,
                battery: batteryData,
                heartRate: hrData,
                spo2: nil,
                deviceType: DeviceType.oralable
            )

            localSensorDataHistory.append(oralableSensorData)

            // CRITICAL: Also store in SensorDataProcessor for ShareView/CSV export
            sensorDataProcessor.appendToHistory(oralableSensorData)

            // Log every 500 samples to verify storage
            if sensorDataProcessor.sensorDataHistory.count % 500 == 0 {
                Logger.shared.info("[DeviceManagerAdapter] 📊 sensorDataHistory count: \(sensorDataProcessor.sensorDataHistory.count)")
                // Log HR storage status
                if let hr = hrData {
                    Logger.shared.info("[DeviceManagerAdapter] 💓 HR in SensorData: \(hr.bpm) bpm")
                } else {
                    Logger.shared.debug("[DeviceManagerAdapter] 💔 HR nil (heartRate=\(heartRate))")
                }
            }
        }

        // Create ANR M40 entry if we have EMG data
        if hasEMG && emgValue > 0 {
            // ANR M40: EMG stored in ppg.ir field, everything else zero
            let emgPPGData = PPGData(
                red: 0,
                ir: Int32(emgValue),
                green: 0,
                timestamp: timestamp
            )

            let zeroAccel = AccelerometerData(x: 0, y: 0, z: 0, timestamp: timestamp)
            let zeroTemp = TemperatureData(celsius: 0, timestamp: timestamp)
            let zeroBattery = BatteryData(percentage: 0, timestamp: timestamp)  // ANR doesn't report battery

            let anrSensorData = SensorData(
                timestamp: timestamp,
                ppg: emgPPGData,
                accelerometer: zeroAccel,
                temperature: zeroTemp,
                battery: zeroBattery,
                heartRate: nil,
                spo2: nil,
                deviceType: DeviceType.anr
            )

            localSensorDataHistory.append(anrSensorData)

            // CRITICAL: Also store in SensorDataProcessor for ShareView/CSV export
            sensorDataProcessor.appendToHistory(anrSensorData)
        }

        // Trim history to cap
        if localSensorDataHistory.count > maxLocalHistoryCount {
            localSensorDataHistory.removeFirst(localSensorDataHistory.count - maxLocalHistoryCount)
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
