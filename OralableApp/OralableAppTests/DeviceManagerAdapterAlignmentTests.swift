//
//  DeviceManagerAdapterAlignmentTests.swift
//  OralableAppTests
//
//  Regression tests for BLE packet-to-sample alignment.
//

import XCTest
@testable import OralableApp

final class DeviceManagerAdapterAlignmentTests: XCTestCase {

    func testRepeatedPacketFrameNumbersDoNotCollapsePPGSamples() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let readings = [
            reading(.ppgRed, 201, start, frame: 42),
            reading(.ppgInfrared, 301, start.addingTimeInterval(0.001), frame: 42),
            reading(.ppgGreen, 401, start.addingTimeInterval(0.002), frame: 42),
            reading(.ppgRed, 202, start.addingTimeInterval(0.020), frame: 42),
            reading(.ppgInfrared, 302, start.addingTimeInterval(0.021), frame: 42),
            reading(.ppgGreen, 402, start.addingTimeInterval(0.022), frame: 42)
        ]

        let arrays = DeviceManagerAdapter.biometricSampleArrays(from: readings)
        XCTAssertEqual(arrays.red, [201, 202])
        XCTAssertEqual(arrays.ir, [301, 302])
        XCTAssertEqual(arrays.green, [401, 402])

        let rows = DeviceManagerAdapter.oralableSensorDataRows(
            from: readings,
            heartRate: 0,
            heartRateQuality: 0,
            temperature: 36.5,
            batteryLevel: 75
        )
        XCTAssertEqual(rows.map { Double($0.ppg.red) }, [201, 202])
        XCTAssertEqual(rows.map { Double($0.ppg.ir) }, [301, 302])
        XCTAssertEqual(rows.map { Double($0.ppg.green) }, [401, 402])
    }

    private func reading(_ type: SensorType, _ value: Double, _ timestamp: Date, frame: UInt32) -> SensorReading {
        SensorReading(
            sensorType: type,
            value: value,
            timestamp: timestamp,
            frameNumber: frame
        )
    }
}
