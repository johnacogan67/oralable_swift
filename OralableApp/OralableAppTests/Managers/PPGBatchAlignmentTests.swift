//
//  PPGBatchAlignmentTests.swift
//  OralableAppTests
//
//  A PPG notify carries one frame counter and many samples (often 20 at 50 Hz).
//  Those samples must stay separate in history and in the heart-rate batch.
//

import XCTest
@testable import OralableApp

final class PPGBatchAlignmentTests: XCTestCase {

    func testPacketFrameCounterDoesNotCollapseSamples() {
        let readings = packetReadings(sampleCount: 20, frame: 41)
        let rows = DeviceManagerAdapter.oralableSensorDataRows(
            from: readings,
            heartRate: 0,
            heartRateQuality: 0,
            temperature: 36.5,
            batteryLevel: 80
        )
        let arrays = DeviceManagerAdapter.biometricSampleArrays(from: readings)

        XCTAssertEqual(rows.count, 20)
        XCTAssertEqual(arrays.ir.count, 20)
        XCTAssertEqual(rows.map { $0.ppg.ir }, (0..<20).map { Int32(1_000 + $0) })
        XCTAssertEqual(arrays.ir, (0..<20).map { Double(1_000 + $0) })
        XCTAssertEqual(rows.map { $0.ppg.red }, (0..<20).map { Int32(500 + $0) })
        XCTAssertEqual(rows.map { $0.accelerometer.x }, (0..<20).map { Int16($0) })
    }

    func testChannelsOfOneSampleStayOneRow() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let frame: UInt32 = 7
        let readings = [
            SensorReading(sensorType: .ppgRed, value: 400, timestamp: t, frameNumber: frame),
            SensorReading(sensorType: .ppgInfrared, value: 2_000, timestamp: t, frameNumber: frame),
            SensorReading(sensorType: .ppgGreen, value: 300, timestamp: t, frameNumber: frame)
        ]
        let rows = DeviceManagerAdapter.oralableSensorDataRows(
            from: readings,
            heartRate: 0,
            heartRateQuality: 0,
            temperature: 36.5,
            batteryLevel: 80
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].ppg.ir, 2_000)
        XCTAssertEqual(rows[0].ppg.red, 400)
        XCTAssertEqual(rows[0].ppg.green, 300)
    }

    /// One notify: shared packet frame, sample times 20 ms apart, RGB plus accel.
    private func packetReadings(sampleCount: Int, frame: UInt32) -> [SensorReading] {
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        var readings: [SensorReading] = []
        readings.reserveCapacity(sampleCount * 4)
        for i in 0..<sampleCount {
            let t = end.addingTimeInterval(-Double(sampleCount - 1 - i) * 0.02)
            let n = Double(i)
            readings.append(SensorReading(sensorType: .ppgRed, value: 500 + n, timestamp: t, frameNumber: frame))
            readings.append(SensorReading(sensorType: .ppgInfrared, value: 1_000 + n, timestamp: t, frameNumber: frame))
            readings.append(SensorReading(sensorType: .ppgGreen, value: 200 + n, timestamp: t, frameNumber: frame))
            readings.append(SensorReading(sensorType: .accelerometerX, value: n, timestamp: t, frameNumber: frame))
            readings.append(SensorReading(sensorType: .accelerometerY, value: 0, timestamp: t, frameNumber: frame))
            readings.append(SensorReading(sensorType: .accelerometerZ, value: 16_384, timestamp: t, frameNumber: frame))
        }
        return readings
    }
}
