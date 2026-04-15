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
    private var temperatureDebugLogInterval: TimeInterval { 15.0 }
    private var temperatureDebugChangeThresholdCelsius: Double { 0.5 }


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
            // 20-sample BLE packets at 50 Hz naturally arrive around 0.40 s.
            // Only flag intervals that are meaningfully late.
            if interval > 0.8 {
                Logger.shared.debug("[OralableDevice] ⚠️ Large packet interval: \(String(format: "%.3f", interval))s")
            }
            #endif
        }
        lastPacketTime = notificationTime

        // Use OralableCore.BLEDataParser for parsing (handles frame counter)
        guard let result = OralableCore.BLEDataParser.parsePPGPacket(data, notificationTime: notificationTime) else {
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

        var latestRed: SensorReading?
        var latestIR: SensorReading?
        var latestGreen: SensorReading?

        for sample in samples {
            let redReading = SensorReading(
                sensorType: .ppgRed,
                value: Double(sample.red),
                timestamp: sample.timestamp,
                deviceId: deviceId,
                frameNumber: frameCounter
            )

            let irReading = SensorReading(
                sensorType: .ppgInfrared,
                value: Double(sample.ir),
                timestamp: sample.timestamp,
                deviceId: deviceId,
                frameNumber: frameCounter
            )

            let greenReading = SensorReading(
                sensorType: .ppgGreen,
                value: Double(sample.green),
                timestamp: sample.timestamp,
                deviceId: deviceId,
                frameNumber: frameCounter
            )

            readings.append(redReading)
            readings.append(irReading)
            readings.append(greenReading)

            latestRed = redReading
            latestIR = irReading
            latestGreen = greenReading
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

        // Single latestReadings update per packet at end of method (minimizes Combine churn)
        if let r = latestRed { latestReadings[.ppgRed] = r }
        if let i = latestIR { latestReadings[.ppgInfrared] = i }
        if let g = latestGreen { latestReadings[.ppgGreen] = g }
    }

    // MARK: - Accelerometer Data Parsing

    /// Parse accelerometer data using OralableCore.BLEDataParser
    func parseAccelerometerData(_ data: Data) {
        let notificationTime = Date()

        // Use OralableCore.BLEDataParser for parsing (handles frame counter)
        guard let result = OralableCore.BLEDataParser.parseAccelerometerPacket(data, notificationTime: notificationTime) else {
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

        var latestX: SensorReading?
        var latestY: SensorReading?
        var latestZ: SensorReading?

        for sample in samples {
            let xReading = SensorReading(
                sensorType: .accelerometerX,
                value: Double(sample.x),
                timestamp: sample.timestamp,
                deviceId: deviceId,
                frameNumber: frameCounter
            )

            let yReading = SensorReading(
                sensorType: .accelerometerY,
                value: Double(sample.y),
                timestamp: sample.timestamp,
                deviceId: deviceId,
                frameNumber: frameCounter
            )

            let zReading = SensorReading(
                sensorType: .accelerometerZ,
                value: Double(sample.z),
                timestamp: sample.timestamp,
                deviceId: deviceId,
                frameNumber: frameCounter
            )

            readings.append(xReading)
            readings.append(yReading)
            readings.append(zReading)

            latestX = xReading
            latestY = yReading
            latestZ = zReading
        }

        if let x = latestX { latestReadings[.accelerometerX] = x }
        if let y = latestY { latestReadings[.accelerometerY] = y }
        if let z = latestZ { latestReadings[.accelerometerZ] = z }

        // Emit batch
        if !readings.isEmpty {
            readingsBatchSubject.send(readings)
        }
    }

    // MARK: - Temperature Data Parsing

    /// Parse temperature data using OralableCore.BLEDataParser
    func parseTemperature(_ data: Data) {
        let notificationTime = Date()

        // Use OralableCore.BLEDataParser for parsing
        guard let result = OralableCore.BLEDataParser.parseTemperaturePacket(data) else {
            Logger.shared.warning("[OralableDevice] ⚠️ Failed to parse temperature packet (\(data.count) bytes)")
            return
        }

        let tempCelsius = result.temperatureCelsius

        if shouldEmitTemperatureDebugLog(tempCelsius) {
            Logger.shared.debug("[OralableDevice] 🌡️ Temperature: \(String(format: "%.2f", tempCelsius))°C")
        }

        let reading = SensorReading(
            sensorType: .temperature,
            value: tempCelsius,
            timestamp: notificationTime,
            deviceId: peripheral?.identifier.uuidString,
            frameNumber: result.frameCounter
        )

        latestReadings[.temperature] = reading
        readingsBatchSubject.send([reading])
    }

    private func shouldEmitTemperatureDebugLog(_ temperatureCelsius: Double) -> Bool {
        let now = Date()
        defer {
            lastTemperatureDebugLogAt = now
            lastTemperatureDebugValue = temperatureCelsius
        }

        guard let lastLoggedAt = lastTemperatureDebugLogAt else { return true }
        if now.timeIntervalSince(lastLoggedAt) >= temperatureDebugLogInterval {
            return true
        }

        if let lastValue = lastTemperatureDebugValue,
           abs(temperatureCelsius - lastValue) >= temperatureDebugChangeThresholdCelsius {
            return true
        }

        return false
    }

    // MARK: - Battery Data Parsing

    /// Parse TGM battery data using OralableCore.BLEDataParser
    func parseBatteryData(_ data: Data) {
        // Prefer OralableCore parsing (expects 4-byte millivolts, validated range).
        var percentage: Int?

        if let batteryData = OralableCore.BLEDataParser.parseTGMBatteryData(data) {
            percentage = batteryData.percentage
        } else if data.count >= 4 {
            // Fallback: handle endianness / relaxed voltage validation.
            // Firmware spec says battery is 4-byte millivolts; if strict validation fails, decode raw and choose plausible value.
            let bytes = [UInt8](data.prefix(4))
            if bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0 {
                // Some firmwares occasionally emit an all-zero placeholder; ignore silently.
                return
            }

            // Observed in logs: 4-byte payloads like [0B 00 00 00] and [16 00 00 00].
            // Treat these as a padded battery percentage when the upper 3 bytes are zero.
            if bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0 {
                let pct = Int(bytes[0])
                if (0...100).contains(pct) {
                    percentage = pct
                    // This is a valid interpretation; don't continue into millivolt heuristics.
                } else {
                    return
                }
            }

            let rawLE = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            let rawBE = UInt32(bytes[3]) | (UInt32(bytes[2]) << 8) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[0]) << 24)

            let candidates = [Int(rawLE), Int(rawBE)]
            if percentage == nil, let mv = candidates.first(where: { $0 >= 2000 && $0 <= 5000 }) {
                // Convert to percentage (simple linear mapping): 3.0V = 0%, 4.2V = 100%
                percentage = Int(min(100, max(0, (mv - 3000) * 100 / 1200)))
            } else if percentage == nil {
                let now = Date()
                if lastBatteryParseFailureLogAt == nil || now.timeIntervalSince(lastBatteryParseFailureLogAt!) > 30 {
                    let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                    Logger.shared.warning("[OralableDevice] ⚠️ Battery packet decode failed (\(data.count) bytes) raw=[\(hex)] le=\(rawLE) be=\(rawBE)")
                    lastBatteryParseFailureLogAt = now
                }
                return
            }
        } else {
            let now = Date()
            if lastBatteryParseFailureLogAt == nil || now.timeIntervalSince(lastBatteryParseFailureLogAt!) > 30 {
                Logger.shared.warning("[OralableDevice] ⚠️ Battery packet too short (\(data.count) bytes)")
                lastBatteryParseFailureLogAt = now
            }
            return
        }

        guard let percentage else { return }

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
        guard let level = OralableCore.BLEDataParser.parseStandardBatteryLevel(data) else {
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
