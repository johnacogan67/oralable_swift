import XCTest
@testable import OralableApp

final class DeviceManagerAdapterPPGTests: XCTestCase {
    func testBiometricSampleArraysPreserveSamplesSharingPacketFrameNumber() {
        let readings = makePacketReadings(sampleCount: 3, sameTimestamp: false)

        let arrays = DeviceManagerAdapter.biometricSampleArrays(from: readings)

        XCTAssertEqual(arrays.red, [1_000, 1_001, 1_002])
        XCTAssertEqual(arrays.ir, [2_000, 2_001, 2_002])
        XCTAssertEqual(arrays.green, [3_000, 3_001, 3_002])
    }

    func testOralableRowsPreserveSameTimestampSamplesSharingPacketFrameNumber() {
        let readings = makePacketReadings(sampleCount: 3, sameTimestamp: true)

        let rows = DeviceManagerAdapter.oralableSensorDataRows(
            from: readings,
            heartRate: 72,
            heartRateQuality: 0.9,
            temperature: 36.8,
            batteryLevel: 87
        )

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map { $0.ppg.red }, [Int32(1_000), Int32(1_001), Int32(1_002)])
        XCTAssertEqual(rows.map { $0.ppg.ir }, [Int32(2_000), Int32(2_001), Int32(2_002)])
        XCTAssertEqual(rows.map { $0.ppg.green }, [Int32(3_000), Int32(3_001), Int32(3_002)])
    }

    private func makePacketReadings(sampleCount: Int, sameTimestamp: Bool) -> [SensorReading] {
        let baseTimestamp = Date(timeIntervalSinceReferenceDate: 1_234)
        let frameNumber: UInt32 = 42

        return (0..<sampleCount).flatMap { index in
            let timestamp = sameTimestamp
                ? baseTimestamp
                : baseTimestamp.addingTimeInterval(Double(index) * 0.02)

            return [
                SensorReading(
                    sensorType: .ppgRed,
                    value: Double(1_000 + index),
                    timestamp: timestamp,
                    frameNumber: frameNumber
                ),
                SensorReading(
                    sensorType: .ppgInfrared,
                    value: Double(2_000 + index),
                    timestamp: timestamp,
                    frameNumber: frameNumber
                ),
                SensorReading(
                    sensorType: .ppgGreen,
                    value: Double(3_000 + index),
                    timestamp: timestamp,
                    frameNumber: frameNumber
                )
            ]
        }
    }
}
