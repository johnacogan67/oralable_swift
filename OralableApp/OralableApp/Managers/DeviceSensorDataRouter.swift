//
//  DeviceSensorDataRouter.swift
//  OralableApp
//
//  Extracted from DeviceManager.swift - handles sensor data subscription and routing.
//
//  Responsibilities:
//  - Subscribing to device sensor reading publishers
//  - Routing individual sensor readings to storage and publishers
//  - Routing batched sensor readings for efficient downstream processing
//  - Managing reading history trimming
//
//  Data Flow:
//  BLE notification -> OralableDevice.parseSensorData()
//  -> DeviceManager.handleSensorReadingsBatch()
//  -> DeviceManagerAdapter -> DashboardViewModel
//

import Foundation
import CoreBluetooth
import Combine
import OralableCore

// MARK: - Sensor Data Routing

extension DeviceManager {

    // MARK: - Device Subscription

    func subscribeToDevice(_ device: BLEDeviceProtocol) {
        Logger.shared.debug("[DeviceManager] subscribeToDevice")
        Logger.shared.debug("[DeviceManager] Device: \(device.deviceInfo.name)")

        // Subscribe to batch publisher for efficient multi-reading delivery
        device.sensorReadingsBatch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] readings in
                self?.handleSensorReadingsBatch(readings, from: device)
            }
            .store(in: &cancellables)

        Logger.shared.debug("[DeviceManager] Batch subscription created")
    }

    // MARK: - Reading Handlers

    func handleSensorReading(_ reading: SensorReading, from device: BLEDeviceProtocol) {
        // Add to all readings
        allSensorReadings.append(reading)

        // Update latest readings
        latestReadings[reading.sensorType] = reading

        // Emit per-reading for streaming consumers
        readingsSubject.send(reading)

        // Trim history if needed (keep last 1000)
        if allSensorReadings.count > 1000 {
            allSensorReadings.removeFirst(100)
        }
    }

    func handleSensorReadingsBatch(_ readings: [SensorReading], from device: BLEDeviceProtocol) {
        Logger.shared.info("[DeviceManager] 📥 Received batch: \(readings.count) readings from \(device.deviceInfo.name)")

        // Add to all readings
        allSensorReadings.append(contentsOf: readings)

        // PERFORMANCE FIX: Batch update to prevent UI flooding
        // First collect latest per type, then update latestReadings once per type
        var latestByType: [SensorType: SensorReading] = [:]
        for reading in readings {
            latestByType[reading.sensorType] = reading
        }

        // Single batch update (triggers publisher once per type, not per reading)
        for (type, reading) in latestByType {
            latestReadings[type] = reading
        }

        Logger.shared.info("[DeviceManager] 📊 Updated latestReadings: \(latestByType.count) types - \(latestByType.keys.map { $0.rawValue }.joined(separator: ", "))")

        // Emit batch for efficient downstream processing
        readingsBatchSubject.send(readings)

        // Trim history if needed (keep last 1000)
        if allSensorReadings.count > 1000 {
            let removeCount = allSensorReadings.count - 1000
            allSensorReadings.removeFirst(removeCount)
        }
    }
}
