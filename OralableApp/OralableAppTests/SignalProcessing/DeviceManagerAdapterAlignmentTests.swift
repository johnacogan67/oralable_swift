//
//  DeviceManagerAdapterAlignmentTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp
import OralableCore

final class DeviceManagerAdapterAlignmentTests: XCTestCase {

    func testPPGBucketingPreservesSamplesWhenPacketFrameNumberRepeats() {
        let base = Date(timeIntervalSinceReferenceDate: 10_000)
        let readings = (0..<3).flatMap { index in
            ppgTriplet(
                timestamp: base.addingTimeInterval(Double(index) * 0.02),
                frameNumber: 42,
                red: 1_000 + Double(index),
                ir: 2_000 + Double(index),
                green: 3_000 + Double(index)
            )
        }

        let arrays = DeviceManagerAdapter.biometricSampleArrays(from: readings)

        XCTAssertEqual(arrays.red, [1_000, 1_001, 1_002])
        XCTAssertEqual(arrays.ir, [2_000, 2_001, 2_002])
        XCTAssertEqual(arrays.green, [3_000, 3_001, 3_002])

        let rows = DeviceManagerAdapter.oralableSensorDataRows(
            from: readings,
            heartRate: 0,
            heartRateQuality: 0,
            temperature: 36.5,
            batteryLevel: 87
        )

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map { $0.ppg.red }, [1_000, 1_001, 1_002])
        XCTAssertEqual(rows.map { $0.ppg.ir }, [2_000, 2_001, 2_002])
        XCTAssertEqual(rows.map { $0.ppg.green }, [3_000, 3_001, 3_002])
    }

    private func ppgTriplet(
        timestamp: Date,
        frameNumber: UInt32,
        red: Double,
        ir: Double,
        green: Double
    ) -> [SensorReading] {
        [
            SensorReading(sensorType: .ppgRed, value: red, timestamp: timestamp, frameNumber: frameNumber),
            SensorReading(sensorType: .ppgInfrared, value: ir, timestamp: timestamp, frameNumber: frameNumber),
            SensorReading(sensorType: .ppgGreen, value: green, timestamp: timestamp, frameNumber: frameNumber)
        ]
    }
}
