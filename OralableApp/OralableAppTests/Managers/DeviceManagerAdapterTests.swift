//
//  DeviceManagerAdapterTests.swift
//  OralableAppTests
//
//  Regression coverage for BLE sample alignment.
//

import XCTest
@testable import OralableApp

final class DeviceManagerAdapterTests: XCTestCase {

    func testMultiSamplePPGPacketDoesNotCollapseWhenFrameAndTimestampRepeat() {
        let packetFrame: UInt32 = 42
        let packetTimestamp = Date(timeIntervalSinceReferenceDate: 1_000)
        let readings = [
            ppgReading(.ppgRed, value: 1_000, timestamp: packetTimestamp, frameNumber: packetFrame),
            ppgReading(.ppgInfrared, value: 2_000, timestamp: packetTimestamp, frameNumber: packetFrame),
            ppgReading(.ppgGreen, value: 3_000, timestamp: packetTimestamp, frameNumber: packetFrame),
            ppgReading(.ppgRed, value: 1_001, timestamp: packetTimestamp, frameNumber: packetFrame),
            ppgReading(.ppgInfrared, value: 2_001, timestamp: packetTimestamp, frameNumber: packetFrame),
            ppgReading(.ppgGreen, value: 3_001, timestamp: packetTimestamp, frameNumber: packetFrame)
        ]

        let arrays = DeviceManagerAdapter.biometricSampleArrays(from: readings)
        XCTAssertEqual(arrays.red, [1_000, 1_001])
        XCTAssertEqual(arrays.ir, [2_000, 2_001])
        XCTAssertEqual(arrays.green, [3_000, 3_001])

        let rows = DeviceManagerAdapter.oralableSensorDataRows(
            from: readings,
            heartRate: 0,
            heartRateQuality: 0,
            temperature: 36.5,
            batteryLevel: 90
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map { $0.ppg.red }, [1_000, 1_001])
        XCTAssertEqual(rows.map { $0.ppg.ir }, [2_000, 2_001])
        XCTAssertEqual(rows.map { $0.ppg.green }, [3_000, 3_001])
    }

    private func ppgReading(
        _ type: SensorType,
        value: Double,
        timestamp: Date,
        frameNumber: UInt32?
    ) -> SensorReading {
        SensorReading(
            sensorType: type,
            value: value,
            timestamp: timestamp,
            frameNumber: frameNumber
        )
    }
}
