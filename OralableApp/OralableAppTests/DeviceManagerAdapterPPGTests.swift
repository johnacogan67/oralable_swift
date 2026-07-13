import XCTest
@testable import OralableApp

final class DeviceManagerAdapterPPGTests: XCTestCase {
    func testPPGTripletsWithSamePacketFrameAreNotCollapsed() {
        let timestamp = Date(timeIntervalSinceReferenceDate: 1_000)
        let readings = [
            SensorReading(sensorType: .accelerometerX, value: 11, timestamp: timestamp, frameNumber: 42),
            SensorReading(sensorType: .accelerometerY, value: 22, timestamp: timestamp, frameNumber: 42),
            SensorReading(sensorType: .accelerometerZ, value: 33, timestamp: timestamp, frameNumber: 42),

            SensorReading(sensorType: .ppgRed, value: 1_001, timestamp: timestamp, frameNumber: 42),
            SensorReading(sensorType: .ppgInfrared, value: 2_001, timestamp: timestamp, frameNumber: 42),
            SensorReading(sensorType: .ppgGreen, value: 3_001, timestamp: timestamp, frameNumber: 42),

            SensorReading(sensorType: .ppgRed, value: 1_002, timestamp: timestamp, frameNumber: 42),
            SensorReading(sensorType: .ppgInfrared, value: 2_002, timestamp: timestamp, frameNumber: 42),
            SensorReading(sensorType: .ppgGreen, value: 3_002, timestamp: timestamp, frameNumber: 42)
        ]

        let arrays = DeviceManagerAdapter.biometricSampleArrays(from: readings)
        XCTAssertEqual(arrays.red, [1_001, 1_002])
        XCTAssertEqual(arrays.ir, [2_001, 2_002])
        XCTAssertEqual(arrays.green, [3_001, 3_002])
        XCTAssertEqual(arrays.ax, [11, 11])
        XCTAssertEqual(arrays.ay, [22, 22])
        XCTAssertEqual(arrays.az, [33, 33])

        let rows = DeviceManagerAdapter.oralableSensorDataRows(
            from: readings,
            heartRate: 72,
            heartRateQuality: 0.95,
            temperature: 36.5,
            batteryLevel: 88
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map { $0.ppg.red }, [1_001, 1_002])
        XCTAssertEqual(rows.map { $0.ppg.ir }, [2_001, 2_002])
        XCTAssertEqual(rows.map { $0.ppg.green }, [3_001, 3_002])
    }
}
