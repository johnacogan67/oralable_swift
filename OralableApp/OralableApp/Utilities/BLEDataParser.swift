//
//  BLEDataParser.swift
//  OralableApp
//
//  Created: January 29, 2026
//  Updated: Frame counter handling and multi-sample parsing
//  Reference: cursor_oralable/src/parser/log_parser.py
//

import Foundation

/// Framework-agnostic utilities for parsing raw BLE data packets
/// Converts raw byte data from Oralable devices into typed model objects
public struct BLEDataParser {

    // MARK: - Frame Counter

    /// Size of frame counter prefix in bytes
    public static let frameCounterSize: Int = AlgorithmSpec.frameCounterBytes

    /// Extract frame counter from packet (first 4 bytes)
    /// - Parameter data: Raw packet data
    /// - Returns: Frame counter value, or nil if insufficient data
    public static func extractFrameCounter(_ data: Data) -> UInt32? {
        guard data.count >= frameCounterSize else { return nil }
        return data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 0, as: UInt32.self)
        }
    }

    // MARK: - PPG Data Parsing (with frame counter)

    /// Parse PPG sensor data from raw BLE packet
    /// Handles the 4-byte frame counter prefix per firmware spec
    /// - Parameter data: Raw data packet (4-byte header + N×12 bytes)
    /// - Returns: Tuple of (frameCounter, PPGData array), or nil if invalid
    public static func parsePPGPacket(_ data: Data) -> (frameCounter: UInt32, samples: [PPGData])? {
        let headerSize = frameCounterSize
        let bytesPerSample = AlgorithmSpec.bytesPerPPGSample  // 12 bytes

        // Need header + at least one sample
        guard data.count >= headerSize + bytesPerSample else { return nil }

        // Extract frame counter
        guard let frameCounter = extractFrameCounter(data) else { return nil }

        // Parse samples starting after header
        let payloadData = data.subdata(in: headerSize..<data.count)
        guard let samples = parsePPGSamples(payloadData) else { return nil }

        return (frameCounter, samples)
    }

    /// Parse PPG samples from payload data (without frame counter)
    /// - Parameter data: Payload data containing N×12 bytes of samples
    /// - Returns: Array of PPGData readings
    public static func parsePPGSamples(_ data: Data) -> [PPGData]? {
        let bytesPerSample = AlgorithmSpec.bytesPerPPGSample

        guard data.count >= bytesPerSample else { return nil }

        let sampleCount = data.count / bytesPerSample
        var readings: [PPGData] = []
        readings.reserveCapacity(sampleCount)

        let timestamp = Date()

        for i in 0..<sampleCount {
            let offset = i * bytesPerSample

            guard offset + bytesPerSample <= data.count else { break }

            // Channel order: Red (0), IR (4), Green (8)
            let values = data.withUnsafeBytes { ptr -> (red: UInt32, ir: UInt32, green: UInt32) in
                let red = ptr.load(fromByteOffset: offset + 0, as: UInt32.self)
                let ir = ptr.load(fromByteOffset: offset + 4, as: UInt32.self)
                let green = ptr.load(fromByteOffset: offset + 8, as: UInt32.self)
                return (red, ir, green)
            }

            let reading = PPGData(
                red: Int32(bitPattern: values.red),
                ir: Int32(bitPattern: values.ir),
                green: Int32(bitPattern: values.green),
                timestamp: timestamp
            )

            readings.append(reading)
        }

        return readings.isEmpty ? nil : readings
    }

    /// Legacy method for backward compatibility
    /// Note: This assumes data has NO frame counter prefix
    @available(*, deprecated, message: "Use parsePPGPacket() for full packets with frame counter")
    public static func parsePPGData(_ data: Data) -> [PPGData]? {
        return parsePPGSamples(data)
    }

    // MARK: - Accelerometer Data Parsing (with frame counter)

    /// Parse accelerometer data from raw BLE packet
    /// Handles the 4-byte frame counter prefix per firmware spec
    /// - Parameter data: Raw data packet (4-byte header + N×6 bytes)
    /// - Returns: Tuple of (frameCounter, AccelerometerData array), or nil if invalid
    public static func parseAccelerometerPacket(_ data: Data) -> (frameCounter: UInt32, samples: [AccelerometerData])? {
        let headerSize = frameCounterSize
        let bytesPerSample = AlgorithmSpec.bytesPerAccelSample  // 6 bytes

        // Need header + at least one sample
        guard data.count >= headerSize + bytesPerSample else { return nil }

        // Extract frame counter
        guard let frameCounter = extractFrameCounter(data) else { return nil }

        // Parse samples starting after header
        let payloadData = data.subdata(in: headerSize..<data.count)
        guard let samples = parseAccelerometerSamples(payloadData) else { return nil }

        return (frameCounter, samples)
    }

    /// Parse accelerometer samples from payload data (without frame counter)
    /// - Parameter data: Payload data containing N×6 bytes of samples
    /// - Returns: Array of AccelerometerData readings
    public static func parseAccelerometerSamples(_ data: Data) -> [AccelerometerData]? {
        let bytesPerSample = AlgorithmSpec.bytesPerAccelSample

        guard data.count >= bytesPerSample else { return nil }

        let sampleCount = data.count / bytesPerSample
        var readings: [AccelerometerData] = []
        readings.reserveCapacity(sampleCount)

        let timestamp = Date()

        for i in 0..<sampleCount {
            let offset = i * bytesPerSample

            guard offset + bytesPerSample <= data.count else { break }

            let values = data.withUnsafeBytes { ptr -> (x: Int16, y: Int16, z: Int16) in
                let x = ptr.load(fromByteOffset: offset + 0, as: Int16.self)
                let y = ptr.load(fromByteOffset: offset + 2, as: Int16.self)
                let z = ptr.load(fromByteOffset: offset + 4, as: Int16.self)
                return (x, y, z)
            }

            let reading = AccelerometerData(
                x: values.x,
                y: values.y,
                z: values.z,
                timestamp: timestamp
            )

            readings.append(reading)
        }

        return readings.isEmpty ? nil : readings
    }

    /// Legacy method for backward compatibility
    @available(*, deprecated, message: "Use parseAccelerometerPacket() for full packets with frame counter")
    public static func parseAccelerometerData(_ data: Data) -> [AccelerometerData]? {
        return parseAccelerometerSamples(data)
    }

    // MARK: - Temperature Data Parsing (with frame counter)

    /// Parse temperature data from raw BLE packet
    /// - Parameter data: Raw data packet (4-byte frame counter + 2-byte temp)
    /// - Returns: Tuple of (frameCounter, temperature in Celsius), or nil if invalid
    public static func parseTemperaturePacket(_ data: Data) -> (frameCounter: UInt32, tempCelsius: Double)? {
        let headerSize = frameCounterSize
        let tempSize = 2  // Int16

        guard data.count >= headerSize + tempSize else { return nil }

        guard let frameCounter = extractFrameCounter(data) else { return nil }

        // Temperature is centidegrees Celsius (Int16)
        let tempRaw = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: headerSize, as: Int16.self)
        }

        let tempCelsius = Double(tempRaw) / 100.0

        return (frameCounter, tempCelsius)
    }

    // MARK: - Battery Data Parsing

    /// Parse battery data from raw BLE packet
    /// - Parameter data: Raw data packet (4 bytes millivolts)
    /// - Returns: BatteryData, or nil if invalid
    public static func parseBatteryData(_ data: Data) -> BatteryData? {
        guard data.count >= 4 else { return nil }

        let millivolts = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 0, as: Int32.self)
        }

        // Validate range (2500-4500 mV typical for LiPo)
        guard millivolts >= 2500 && millivolts <= 4500 else { return nil }

        // Convert to percentage (simple linear mapping)
        // 3.0V = 0%, 4.2V = 100%
        let percentage = Int(min(100, max(0, (millivolts - 3000) * 100 / 1200)))

        return BatteryData(
            percentage: percentage,
            timestamp: Date()
        )
    }

    /// Parse battery data returning millivolts
    /// - Parameter data: Raw data packet
    /// - Returns: Battery voltage in millivolts, or nil if invalid
    public static func parseBatteryMillivolts(_ data: Data) -> Int32? {
        guard data.count >= 4 else { return nil }

        let millivolts = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 0, as: Int32.self)
        }

        // Validate range
        guard millivolts >= 2500 && millivolts <= 4500 else { return nil }

        return millivolts
    }

    // MARK: - Combined Parsing

    /// Parse combined PPG and accelerometer sample
    /// For use when both are packed together (18 bytes)
    public static func parseCombinedSample(_ data: Data) -> (ppg: PPGData, accel: AccelerometerData)? {
        guard data.count >= 18 else { return nil }

        let values = data.withUnsafeBytes { ptr -> (red: UInt32, ir: UInt32, green: UInt32, x: Int16, y: Int16, z: Int16) in
            let red = ptr.load(fromByteOffset: 0, as: UInt32.self)
            let ir = ptr.load(fromByteOffset: 4, as: UInt32.self)
            let green = ptr.load(fromByteOffset: 8, as: UInt32.self)
            let x = ptr.load(fromByteOffset: 12, as: Int16.self)
            let y = ptr.load(fromByteOffset: 14, as: Int16.self)
            let z = ptr.load(fromByteOffset: 16, as: Int16.self)
            return (red, ir, green, x, y, z)
        }

        let timestamp = Date()

        let ppg = PPGData(
            red: Int32(bitPattern: values.red),
            ir: Int32(bitPattern: values.ir),
            green: Int32(bitPattern: values.green),
            timestamp: timestamp
        )

        let accelerometer = AccelerometerData(
            x: values.x,
            y: values.y,
            z: values.z,
            timestamp: timestamp
        )

        return (ppg, accelerometer)
    }
}
