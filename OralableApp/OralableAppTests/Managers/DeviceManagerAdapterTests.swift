//
//  DeviceManagerAdapterTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp
import OralableCore

final class DeviceManagerAdapterPPGAlignmentTests: XCTestCase {
    func testPPGAlignmentPreservesAllSamplesWhenPacketFrameNumberRepeats() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let repeatedPacketFrame: UInt32 = 42
        var readings: [SensorReading] = []

        for index in 0..<3 {
            let timestamp = start.addingTimeInterval(Double(index) * 0.02)
            readings.append(SensorReading(
                sensorType: .ppgRed,
                value: Double(1_000 + index),
                timestamp: timestamp,
                frameNumber: repeatedPacketFrame
            ))
            readings.append(SensorReading(
                sensorType: .ppgInfrared,
                value: Double(2_000 + index),
                timestamp: timestamp,
                frameNumber: repeatedPacketFrame
            ))
            readings.append(SensorReading(
                sensorType: .ppgGreen,
                value: Double(3_000 + index),
                timestamp: timestamp,
                frameNumber: repeatedPacketFrame
            ))
        }

        let arrays = DeviceManagerAdapter.biometricSampleArrays(from: readings)
        XCTAssertEqual(arrays.red, [1_000.0, 1_001.0, 1_002.0])
        XCTAssertEqual(arrays.ir, [2_000.0, 2_001.0, 2_002.0])
        XCTAssertEqual(arrays.green, [3_000.0, 3_001.0, 3_002.0])

        let rows = DeviceManagerAdapter.oralableSensorDataRows(
            from: readings,
            heartRate: 72,
            heartRateQuality: 0.9,
            temperature: 36.8,
            batteryLevel: 88
        )
        XCTAssertEqual(rows.map(\.ppg.red), [1_000 as Int32, 1_001, 1_002])
        XCTAssertEqual(rows.map(\.ppg.ir), [2_000 as Int32, 2_001, 2_002])
        XCTAssertEqual(rows.map(\.ppg.green), [3_000 as Int32, 3_001, 3_002])
    }
}
