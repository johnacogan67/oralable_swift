//
//  SharedDataManagerMergeTests.swift
//  OralableAppTests
//
//  Regression tests for same-day CloudKit sensor data merges.
//

import XCTest
import CloudKit
@testable import OralableApp
import OralableCore

@MainActor
final class SharedDataManagerMergeTests: XCTestCase {

    func testMergedSensorReadingsPreservesExistingDailySamples() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let existing = [
            makeSensorData(at: start, red: 100, accelX: 1),
            makeSensorData(at: start.addingTimeInterval(20), red: 300, accelX: 3)
        ]
        let incoming = [
            existing[1],
            makeSensorData(at: start.addingTimeInterval(10), red: 200, accelX: 2)
        ]
        let record = try makeRecord(with: existing)

        let merged = try SharedDataManager.mergedSensorReadings(from: record, incomingSensorData: incoming)

        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.map(\.timestamp), [
            start,
            start.addingTimeInterval(10),
            start.addingTimeInterval(20)
        ])
        XCTAssertEqual(merged.map(\.ppgRed), [100, 200, 300])
    }

    func testMergedSensorReadingsPreservesDistinctSamplesWithSameTimestamp() throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_100)
        let existing = [makeSensorData(at: timestamp, red: 100, accelX: 1)]
        let incoming = [
            makeSensorData(at: timestamp, red: 200, accelX: 2),
            existing[0]
        ]
        let record = try makeRecord(with: existing)

        let merged = try SharedDataManager.mergedSensorReadings(from: record, incomingSensorData: incoming)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.ppgRed), [100, 200])
    }

    func testMergedSensorReadingsThrowsForCorruptExistingPayload() {
        let record = CKRecord(recordType: "HealthDataRecord")
        record["sensorDataCompressed"] = Data([0x01, 0x02, 0x03]) as CKRecordValue
        record["sensorDataUncompressedSize"] = 128 as CKRecordValue

        XCTAssertThrowsError(
            try SharedDataManager.mergedSensorReadings(
                from: record,
                incomingSensorData: [makeSensorData(at: Date(), red: 100, accelX: 1)]
            )
        )
    }

    func testMergedSensorReadingsAcceptsCloudKitNumericUncompressedSize() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_200)
        let existing = [makeSensorData(at: start, red: 100, accelX: 1)]
        let incoming = [makeSensorData(at: start.addingTimeInterval(1), red: 200, accelX: 2)]
        let record = try makeRecord(with: existing, storeUncompressedSizeAsNSNumber: true)

        let merged = try SharedDataManager.mergedSensorReadings(from: record, incomingSensorData: incoming)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.ppgRed), [100, 200])
    }

    private func makeRecord(
        with sensorData: [SensorData],
        storeUncompressedSizeAsNSNumber: Bool = false
    ) throws -> CKRecord {
        let sessionData = BruxismSessionData(sensorData: sensorData)
        let jsonData = try JSONEncoder().encode(sessionData)
        let record = CKRecord(recordType: "HealthDataRecord")
        record["sensorDataCompressed"] = try XCTUnwrap(jsonData.compressed()) as CKRecordValue
        if storeUncompressedSizeAsNSNumber {
            record["sensorDataUncompressedSize"] = NSNumber(value: jsonData.count) as CKRecordValue
        } else {
            record["sensorDataUncompressedSize"] = jsonData.count as CKRecordValue
        }
        return record
    }

    private func makeSensorData(at timestamp: Date, red: Int32, accelX: Int16) -> SensorData {
        SensorData(
            timestamp: timestamp,
            ppg: PPGData(red: red, ir: red + 1, green: red + 2, timestamp: timestamp),
            accelerometer: AccelerometerData(x: accelX, y: accelX + 1, z: accelX + 2, timestamp: timestamp),
            temperature: TemperatureData(celsius: 37.0, timestamp: timestamp),
            battery: BatteryData(percentage: 90, timestamp: timestamp),
            heartRate: HeartRateData(bpm: 70, quality: 1, timestamp: timestamp),
            spo2: SpO2Data(percentage: 98, quality: 1, timestamp: timestamp),
            deviceType: .oralable
        )
    }
}
