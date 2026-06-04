//
//  DeviceManagerAdapterSampleAlignmentTests.swift
//  OralableAppTests
//
//  Regression tests for preserving every PPG sample in packetized BLE notifications.
//

import XCTest
@testable import OralableApp
import OralableCore

final class DeviceManagerAdapterSampleAlignmentTests: XCTestCase {

    func testBiometricSampleArraysPreservePacketSamplesWithSameFrameNumber() {
        let readings = makePPGPacketReadings(sampleCount: 20, frameNumber: 42)

        let arrays = DeviceManagerAdapter.biometricSampleArrays(from: readings)

        XCTAssertEqual(arrays.ir.count, 20)
        XCTAssertEqual(arrays.red.count, 20)
        XCTAssertEqual(arrays.green.count, 20)
        XCTAssertEqual(arrays.ir, (0..<20).map { Double(2_000 + $0) })
        XCTAssertEqual(arrays.red, (0..<20).map { Double(1_000 + $0) })
        XCTAssertEqual(arrays.green, (0..<20).map { Double(3_000 + $0) })
    }

    func testOralableSensorRowsPreservePacketSamplesWithSameFrameNumber() {
        let readings = makePPGPacketReadings(sampleCount: 20, frameNumber: 42)

        let rows = DeviceManagerAdapter.oralableSensorDataRows(
            from: readings,
            heartRate: 72,
            heartRateQuality: 0.9,
            temperature: 36.7,
            batteryLevel: 88
        )

        XCTAssertEqual(rows.count, 20)
        XCTAssertEqual(rows.map { $0.ppg.ir }, (0..<20).map { Int32(2_000 + $0) })
        XCTAssertEqual(rows.map { $0.ppg.red }, (0..<20).map { Int32(1_000 + $0) })
        XCTAssertEqual(rows.map { $0.ppg.green }, (0..<20).map { Int32(3_000 + $0) })
    }

    private func makePPGPacketReadings(sampleCount: Int, frameNumber: UInt32) -> [SensorReading] {
        let base = Date(timeIntervalSinceReferenceDate: 10_000)
        var readings: [SensorReading] = []
        readings.reserveCapacity(sampleCount * 3)

        for index in 0..<sampleCount {
            let timestamp = base.addingTimeInterval(Double(index) / 50.0)
            readings.append(SensorReading(
                sensorType: .ppgRed,
                value: Double(1_000 + index),
                timestamp: timestamp,
                frameNumber: frameNumber
            ))
            readings.append(SensorReading(
                sensorType: .ppgInfrared,
                value: Double(2_000 + index),
                timestamp: timestamp,
                frameNumber: frameNumber
            ))
            readings.append(SensorReading(
                sensorType: .ppgGreen,
                value: Double(3_000 + index),
                timestamp: timestamp,
                frameNumber: frameNumber
            ))
        }

        return readings
    }
}
