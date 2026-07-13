import XCTest
@testable import OralableApp
import OralableCore

final class SharedDataManagerMergeTests: XCTestCase {
    func testMergedSensorReadingsPreservesExistingSameDaySamples() {
        let base = Date(timeIntervalSince1970: 1_704_067_200)
        let existingFirst = makeReading(at: base, red: 10_001)
        let existingSecond = makeReading(at: base.addingTimeInterval(60), red: 10_002)
        let incomingDuplicate = existingSecond
        let incomingNew = makeReading(at: base.addingTimeInterval(120), red: 10_003)

        let merged = SharedDataManager.mergedSensorReadings(
            existing: [existingFirst, existingSecond],
            incoming: [incomingDuplicate, incomingNew]
        )

        XCTAssertEqual(merged.map { $0.ppgRed }, [10_001, 10_002, 10_003])
        XCTAssertEqual(merged.count, 3)
    }

    func testMergedSensorReadingsKeepsDistinctSamplesWithSameTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 1_704_067_200)
        let existing = makeReading(at: timestamp, red: 10_001)
        let incoming = makeReading(at: timestamp, red: 10_002)

        let merged = SharedDataManager.mergedSensorReadings(existing: [existing], incoming: [incoming])

        XCTAssertEqual(merged.map { $0.ppgRed }, [10_001, 10_002])
        XCTAssertEqual(merged.map { $0.timestamp }, [timestamp, timestamp])
    }

    private func makeReading(at timestamp: Date, red: Int32) -> SerializableSensorData {
        let sensorData = SensorData(
            timestamp: timestamp,
            ppg: PPGData(red: red, ir: red + 1_000, green: red + 2_000, timestamp: timestamp),
            accelerometer: AccelerometerData(x: 10, y: 20, z: 30, timestamp: timestamp),
            temperature: TemperatureData(celsius: 36.5, timestamp: timestamp),
            battery: BatteryData(percentage: 88, timestamp: timestamp),
            heartRate: nil,
            spo2: nil,
            deviceType: .oralable
        )

        return SerializableSensorData(from: sensorData)
    }
}
