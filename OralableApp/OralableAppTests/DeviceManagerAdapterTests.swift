//
//  DeviceManagerAdapterTests.swift
//  OralableAppTests
//
//  Regression tests for live Oralable sensor batching.
//

import XCTest
import OralableCore
@testable import OralableApp

final class DeviceManagerAdapterTests: XCTestCase {
    func testPPGBucketingKeepsMultipleSamplesWithSamePacketFrame() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000)
        let readings = makePPGTriplet(timestamp: base, frame: 42, red: 101, ir: 201, green: 301)
            + makePPGTriplet(timestamp: base.addingTimeInterval(0.02), frame: 42, red: 102, ir: 202, green: 302)

        let arrays = DeviceManagerAdapter.biometricSampleArrays(from: readings)
        XCTAssertEqual(arrays.ir, [201, 202])
        XCTAssertEqual(arrays.red, [101, 102])
        XCTAssertEqual(arrays.green, [301, 302])

        let rows = DeviceManagerAdapter.oralableSensorDataRows(
            from: readings,
            heartRate: 72,
            heartRateQuality: 0.9,
            temperature: 36.5,
            batteryLevel: 88
        )
        XCTAssertEqual(rows.count, 2, "Samples in one BLE packet must not collapse to one history row")
        XCTAssertEqual(rows.map { $0.ppg.ir }, [201, 202])
        XCTAssertEqual(rows.map { $0.ppg.red }, [101, 102])
        XCTAssertEqual(rows.map { $0.ppg.green }, [301, 302])
    }

    private func makePPGTriplet(
        timestamp: Date,
        frame: UInt32,
        red: Double,
        ir: Double,
        green: Double
    ) -> [SensorReading] {
        [
            SensorReading(sensorType: .ppgRed, value: red, timestamp: timestamp, frameNumber: frame),
            SensorReading(sensorType: .ppgInfrared, value: ir, timestamp: timestamp, frameNumber: frame),
            SensorReading(sensorType: .ppgGreen, value: green, timestamp: timestamp, frameNumber: frame)
        ]
    }
}
