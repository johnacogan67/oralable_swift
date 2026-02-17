//
//  OralableDevice+DataParsing.swift
//  OralableApp
//
//  Created: February 2026
//
//  Data parsing methods for OralableDevice.
//  All parsing delegates to OralableCore.BLEDataParser for byte-level parsing.
//  This extension handles converting parsed results into SensorReadings
//  and emitting them through the Combine pipeline.
//

import Foundation
import CoreBluetooth
import OralableCore

// MARK: - Data Parsing

extension OralableDevice {

    // MARK: - PPG Data Parsing

    /// Parse PPG sensor data using OralableCore.BLEDataParser
    func parseSensorData(_ data: Data) {
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

    // MARK: - Accelerometer Data Parsing

    /// Parse accelerometer data using OralableCore.BLEDataParser
    func parseAccelerometerData(_ data: Data) {
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

    // MARK: - Temperature Data Parsing

    /// Parse temperature data using OralableCore.BLEDataParser
    func parseTemperature(_ data: Data) {
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

    // MARK: - Battery Data Parsing

    /// Parse TGM battery data using OralableCore.BLEDataParser
    func parseBatteryData(_ data: Data) {
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
    func parseStandardBatteryLevel(_ data: Data) {
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
}
