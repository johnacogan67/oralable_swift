//
//  DeviceManagerAdapterAlignmentTests.swift
//  OralableAppTests
//
//  Regression tests for Oralable PPG triplet alignment.
//

import XCTest
@testable import OralableApp

final class DeviceManagerAdapterAlignmentTests: XCTestCase {

    func testBiometricSampleArraysPreserveSamplesWhenFrameNumberIsPacketLevel() {
        let readings = makePacketReadings(sampleCount: 5)

        let arrays = DeviceManagerAdapter.biometricSampleArrays(from: readings)

        XCTAssertEqual(arrays.ir.count, 5)
        XCTAssertEqual(arrays.red.count, 5)
        XCTAssertEqual(arrays.green.count, 5)
        XCTAssertEqual(arrays.ir, [2000, 2001, 2002, 2003, 2004])
        XCTAssertEqual(arrays.red, [1000, 1001, 1002, 1003, 1004])
        XCTAssertEqual(arrays.green, [3000, 3001, 3002, 3003, 3004])
    }

    func testOralableSensorDataRowsPreserveSamplesWhenFrameNumberIsPacketLevel() {
        let readings = makePacketReadings(sampleCount: 5)

        let rows = DeviceManagerAdapter.oralableSensorDataRows(
            from: readings,
            heartRate: 72,
            heartRateQuality: 0.9,
            temperature: 36.5,
            batteryLevel: 88
        )

        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.map { $0.ppg.ir }, [2000, 2001, 2002, 2003, 2004] as [Int32])
        XCTAssertEqual(rows.map { $0.ppg.red }, [1000, 1001, 1002, 1003, 1004] as [Int32])
        XCTAssertEqual(rows.map { $0.ppg.green }, [3000, 3001, 3002, 3003, 3004] as [Int32])
        XCTAssertEqual(rows.compactMap { $0.heartRate?.bpm }, [72, 72, 72, 72, 72] as [Double])
    }

    private func makePacketReadings(sampleCount: Int) -> [SensorReading] {
        let baseDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let packetFrameNumber: UInt32 = 42

        return (0..<sampleCount).flatMap { index -> [SensorReading] in
            let timestamp = baseDate.addingTimeInterval(Double(index) * 0.02)

            return [
                SensorReading(
                    sensorType: .ppgRed,
                    value: Double(1000 + index),
                    timestamp: timestamp,
                    frameNumber: packetFrameNumber
                ),
                SensorReading(
                    sensorType: .ppgInfrared,
                    value: Double(2000 + index),
                    timestamp: timestamp,
                    frameNumber: packetFrameNumber
                ),
                SensorReading(
                    sensorType: .ppgGreen,
                    value: Double(3000 + index),
                    timestamp: timestamp,
                    frameNumber: packetFrameNumber
                )
            ]
        }
    }
}
