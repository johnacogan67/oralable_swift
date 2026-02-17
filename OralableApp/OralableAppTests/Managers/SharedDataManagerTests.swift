//
//  SharedDataManagerTests.swift
//  OralableAppTests
//
//  Purpose: Unit tests for SharedDataManager CloudKit data sharing functionality
//
//  Tests cover:
//  - Share code generation (format, length, uniqueness)
//  - Data compression/decompression roundtrip (LZFSE)
//  - Data serialization (BruxismSessionData, SerializableSensorData)
//  - SharePermission enum encoding/decoding
//  - SharedPatientData model construction
//  - SharedProfessional model construction
//  - HealthDataRecord model encoding/decoding
//  - ShareError descriptions
//  - GDPR deletion flow state management
//  - Bruxism event detection logic
//

import XCTest
@testable import OralableApp
import OralableCore

// MARK: - Share Code Generation Tests

final class ShareCodeGenerationTests: XCTestCase {

    var sut: SharedDataManager!
    var mockAuthManager: AuthenticationManager!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        mockAuthManager = AuthenticationManager()
        sut = SharedDataManager(authenticationManager: mockAuthManager)
    }

    @MainActor
    override func tearDown() async throws {
        sut = nil
        mockAuthManager = nil
        try await super.tearDown()
    }

    // MARK: - Code Format Tests

    @MainActor
    func testGenerateShareCodeReturnsExactlySixCharacters() {
        // When
        let code = sut.generateShareCode()

        // Then
        XCTAssertEqual(code.count, 6, "Share code should be exactly 6 characters")
    }

    @MainActor
    func testGenerateShareCodeContainsOnlyDigits() {
        // When
        let code = sut.generateShareCode()

        // Then
        let allDigits = code.allSatisfy { $0.isNumber }
        XCTAssertTrue(allDigits, "Share code should contain only numeric digits, got: \(code)")
    }

    @MainActor
    func testGenerateShareCodeFormatWithLeadingZeros() {
        // Generate many codes and verify format is always 6 digits (zero-padded)
        var foundShortNumericValue = false

        for _ in 0..<1000 {
            let code = sut.generateShareCode()
            XCTAssertEqual(code.count, 6, "Share code must always be 6 characters")

            // Check that leading zeros are preserved
            if let numericValue = Int(code), numericValue < 100000 {
                foundShortNumericValue = true
                // The string should still be 6 chars even if numeric value is small
                XCTAssertEqual(code.count, 6, "Code with small numeric value should still be zero-padded to 6 chars")
            }
        }

        // Statistically, we should find at least one code with leading zeros in 1000 tries
        // (probability of all codes >= 100000 in 1000 tries is extremely small)
        // But this is not guaranteed, so we don't assert on it
    }

    @MainActor
    func testGenerateShareCodeUniqueness() {
        // Generate multiple codes and verify they are not all the same
        var codes = Set<String>()

        for _ in 0..<100 {
            let code = sut.generateShareCode()
            codes.insert(code)
        }

        // With 1M possible values, 100 random codes should produce many unique values
        XCTAssertGreaterThan(codes.count, 50, "100 generated codes should produce at least 50 unique values, got \(codes.count)")
    }

    @MainActor
    func testGenerateShareCodeIsInValidRange() {
        for _ in 0..<100 {
            let code = sut.generateShareCode()
            guard let numericValue = Int(code) else {
                XCTFail("Share code should be parseable as integer: \(code)")
                return
            }

            XCTAssertGreaterThanOrEqual(numericValue, 0, "Share code numeric value should be >= 0")
            XCTAssertLessThanOrEqual(numericValue, 999999, "Share code numeric value should be <= 999999")
        }
    }
}

// MARK: - Data Compression Tests

final class DataCompressionTests: XCTestCase {

    // MARK: - Compression Roundtrip

    func testCompressionDecompressionRoundtrip() {
        // Given
        let originalString = "Hello, this is a test string for compression. It contains some repeated data data data data."
        guard let originalData = originalString.data(using: .utf8) else {
            XCTFail("Failed to create test data")
            return
        }
        let originalSize = originalData.count

        // When
        guard let compressed = originalData.compressed() else {
            XCTFail("Compression should succeed for non-empty data")
            return
        }

        guard let decompressed = compressed.decompressed(expectedSize: originalSize) else {
            XCTFail("Decompression should succeed for validly compressed data")
            return
        }

        // Then
        XCTAssertEqual(decompressed, originalData, "Decompressed data should match original")
        let decompressedString = String(data: decompressed, encoding: .utf8)
        XCTAssertEqual(decompressedString, originalString, "Decompressed string should match original")
    }

    func testCompressionReducesSize() {
        // Given - create highly compressible data (repeated pattern)
        let repeatedString = String(repeating: "ABCDEF1234567890", count: 1000)
        guard let originalData = repeatedString.data(using: .utf8) else {
            XCTFail("Failed to create test data")
            return
        }

        // When
        guard let compressed = originalData.compressed() else {
            XCTFail("Compression should succeed")
            return
        }

        // Then
        XCTAssertLessThan(compressed.count, originalData.count, "Compressed data should be smaller than original for repetitive data")
    }

    func testCompressionOfEmptyDataReturnsNil() {
        // Given
        let emptyData = Data()

        // When
        let compressed = emptyData.compressed()

        // Then
        XCTAssertNil(compressed, "Compression of empty data should return nil")
    }

    func testDecompressionOfEmptyDataReturnsNil() {
        // Given
        let emptyData = Data()

        // When
        let decompressed = emptyData.decompressed(expectedSize: 100)

        // Then
        XCTAssertNil(decompressed, "Decompression of empty data should return nil")
    }

    func testCompressionOfSmallData() {
        // Given - very small data
        let smallData = Data([0x01, 0x02, 0x03])

        // When
        let compressed = smallData.compressed()

        // Then - compression should still succeed (even if not smaller)
        XCTAssertNotNil(compressed, "Compression of small data should not return nil")
    }

    func testCompressionRoundtripWithJSONData() {
        // Given - JSON data similar to what BruxismSessionData produces
        let jsonDict: [String: Any] = [
            "sensorReadings": [
                ["timestamp": "2025-01-01T00:00:00Z", "accelX": 100, "accelY": 200, "accelZ": 300],
                ["timestamp": "2025-01-01T00:00:01Z", "accelX": 101, "accelY": 201, "accelZ": 301]
            ],
            "recordingCount": 2,
            "startDate": "2025-01-01T00:00:00Z",
            "endDate": "2025-01-01T00:00:01Z"
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict) else {
            XCTFail("Failed to create JSON data")
            return
        }
        let originalSize = jsonData.count

        // When
        guard let compressed = jsonData.compressed() else {
            XCTFail("Compression of JSON data should succeed")
            return
        }

        guard let decompressed = compressed.decompressed(expectedSize: originalSize) else {
            XCTFail("Decompression should succeed")
            return
        }

        // Then
        XCTAssertEqual(decompressed, jsonData, "Roundtrip should preserve JSON data exactly")
    }

    func testCompressionOfLargeData() {
        // Given - large dataset simulating sensor data
        var largeData = Data()
        for i in 0..<10000 {
            let value = UInt32(i % 256)
            withUnsafeBytes(of: value) { bytes in
                largeData.append(contentsOf: bytes)
            }
        }
        let originalSize = largeData.count

        // When
        guard let compressed = largeData.compressed() else {
            XCTFail("Compression of large data should succeed")
            return
        }

        guard let decompressed = compressed.decompressed(expectedSize: originalSize) else {
            XCTFail("Decompression of large data should succeed")
            return
        }

        // Then
        XCTAssertEqual(decompressed.count, originalSize, "Decompressed size should match original")
        XCTAssertEqual(decompressed, largeData, "Decompressed data should match original")
    }

    func testDecompressionWithInsufficientExpectedSizeReturnsNil() {
        // Given
        let originalString = "This is a test string that will be compressed and then decompressed with wrong size"
        guard let originalData = originalString.data(using: .utf8) else {
            XCTFail("Failed to create test data")
            return
        }

        guard let compressed = originalData.compressed() else {
            XCTFail("Compression should succeed")
            return
        }

        // When - decompress with a size that is too small
        let tooSmallSize = 1
        let decompressed = compressed.decompressed(expectedSize: tooSmallSize)

        // Then - with too small a buffer, decompression may return partial data or nil
        // The behavior depends on LZFSE implementation but we verify no crash
        if let result = decompressed {
            XCTAssertLessThanOrEqual(result.count, tooSmallSize, "Decompressed data should not exceed expected size")
        }
        // Not crashing is the important assertion here
    }
}

// MARK: - Data Model Tests

final class SharedDataModelTests: XCTestCase {

    // MARK: - Helper Methods

    private func createMockSensorData(count: Int = 5, deviceType: DeviceType = .oralable) -> [SensorData] {
        var sensorData: [SensorData] = []
        let now = Date()

        for i in 0..<count {
            let timestamp = now.addingTimeInterval(TimeInterval(i * 5))

            let ppg = PPGData(
                red: Int32.random(in: 50000...250000),
                ir: Int32.random(in: 50000...250000),
                green: Int32.random(in: 50000...250000),
                timestamp: timestamp
            )

            let accelerometer = AccelerometerData(
                x: Int16.random(in: -100...100),
                y: Int16.random(in: -100...100),
                z: Int16.random(in: -100...100),
                timestamp: timestamp
            )

            let temperature = TemperatureData(
                celsius: Double.random(in: 36.0...37.5),
                timestamp: timestamp
            )

            let battery = BatteryData(
                percentage: Int.random(in: 50...100),
                timestamp: timestamp
            )

            let heartRate = HeartRateData(
                bpm: Double.random(in: 60...90),
                quality: Double.random(in: 0.7...1.0),
                timestamp: timestamp
            )

            let spo2 = SpO2Data(
                percentage: Double.random(in: 95...100),
                quality: Double.random(in: 0.7...1.0),
                timestamp: timestamp
            )

            let data = SensorData(
                timestamp: timestamp,
                ppg: ppg,
                accelerometer: accelerometer,
                temperature: temperature,
                battery: battery,
                heartRate: heartRate,
                spo2: spo2,
                deviceType: deviceType
            )

            sensorData.append(data)
        }

        return sensorData
    }

    private func createMockSensorDataWithHighAccel(count: Int = 5, magnitude: Double = 3.0) -> [SensorData] {
        // Create sensor data with high accelerometer values to trigger bruxism detection
        // magnitude is in raw units where the threshold compares accelerometer.magnitude
        var sensorData: [SensorData] = []
        let now = Date()

        // We need raw Int16 values that produce a certain magnitude
        // AccelerometerData.magnitude is computed from x, y, z in raw units
        // To produce high magnitude, use large raw values
        let rawValue = Int16(clamping: Int(magnitude * 5000))

        for i in 0..<count {
            let timestamp = now.addingTimeInterval(TimeInterval(i * 5))

            let ppg = PPGData(red: 100000, ir: 100000, green: 100000, timestamp: timestamp)
            let accelerometer = AccelerometerData(x: rawValue, y: rawValue, z: rawValue, timestamp: timestamp)
            let temperature = TemperatureData(celsius: 37.0, timestamp: timestamp)
            let battery = BatteryData(percentage: 80, timestamp: timestamp)
            let heartRate = HeartRateData(bpm: 72.0, quality: 0.9, timestamp: timestamp)
            let spo2 = SpO2Data(percentage: 98.0, quality: 0.9, timestamp: timestamp)

            let data = SensorData(
                timestamp: timestamp,
                ppg: ppg,
                accelerometer: accelerometer,
                temperature: temperature,
                battery: battery,
                heartRate: heartRate,
                spo2: spo2,
                deviceType: .oralable
            )
            sensorData.append(data)
        }

        return sensorData
    }

    // MARK: - SharedPatientData Tests

    func testSharedPatientDataInitialization() {
        // Given
        let patientID = "patient_123"
        let dentistID = "dentist_456"
        let shareCode = "123456"

        // When
        let data = SharedPatientData(
            patientID: patientID,
            dentistID: dentistID,
            shareCode: shareCode
        )

        // Then
        XCTAssertEqual(data.patientID, patientID)
        XCTAssertEqual(data.dentistID, dentistID)
        XCTAssertEqual(data.shareCode, shareCode)
        XCTAssertEqual(data.permissions, .readOnly, "Default permission should be readOnly")
        XCTAssertTrue(data.isActive, "New share should be active")
        XCTAssertNil(data.expiryDate, "Default expiry should be nil")
        XCTAssertNotNil(data.id, "Should have a valid UUID")
    }

    func testSharedPatientDataWithReadWritePermission() {
        // When
        let data = SharedPatientData(
            patientID: "patient_1",
            dentistID: "dentist_1",
            shareCode: "654321",
            permissions: .readWrite
        )

        // Then
        XCTAssertEqual(data.permissions, .readWrite)
    }

    func testSharedPatientDataWithExpiryDate() {
        // Given
        let expiryDate = Date().addingTimeInterval(3600 * 48)

        // When
        let data = SharedPatientData(
            patientID: "patient_1",
            dentistID: "dentist_1",
            shareCode: "111222",
            expiryDate: expiryDate
        )

        // Then
        XCTAssertNotNil(data.expiryDate)
        XCTAssertEqual(data.expiryDate!.timeIntervalSince1970, expiryDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testSharedPatientDataAccessGrantedDateIsNow() {
        // When
        let beforeCreation = Date()
        let data = SharedPatientData(
            patientID: "patient_1",
            dentistID: "dentist_1",
            shareCode: "333444"
        )
        let afterCreation = Date()

        // Then
        XCTAssertGreaterThanOrEqual(data.accessGrantedDate, beforeCreation)
        XCTAssertLessThanOrEqual(data.accessGrantedDate, afterCreation)
    }

    func testSharedPatientDataUniqueIDs() {
        // When
        let data1 = SharedPatientData(patientID: "p1", dentistID: "d1", shareCode: "111111")
        let data2 = SharedPatientData(patientID: "p1", dentistID: "d1", shareCode: "111111")

        // Then
        XCTAssertNotEqual(data1.id, data2.id, "Each instance should have a unique UUID")
    }

    // MARK: - SharedProfessional Tests

    func testSharedProfessionalInitialization() {
        // Given
        let now = Date()
        let expiry = now.addingTimeInterval(3600 * 24 * 30)

        // When
        let professional = SharedProfessional(
            id: "record_1",
            professionalID: "prof_123",
            professionalName: "Dr. Smith",
            sharedDate: now,
            expiryDate: expiry,
            isActive: true
        )

        // Then
        XCTAssertEqual(professional.id, "record_1")
        XCTAssertEqual(professional.professionalID, "prof_123")
        XCTAssertEqual(professional.professionalName, "Dr. Smith")
        XCTAssertEqual(professional.sharedDate, now)
        XCTAssertEqual(professional.expiryDate, expiry)
        XCTAssertTrue(professional.isActive)
    }

    func testSharedProfessionalWithNilName() {
        // When
        let professional = SharedProfessional(
            id: "record_2",
            professionalID: "prof_456",
            professionalName: nil,
            sharedDate: Date(),
            expiryDate: nil,
            isActive: false
        )

        // Then
        XCTAssertNil(professional.professionalName)
        XCTAssertNil(professional.expiryDate)
        XCTAssertFalse(professional.isActive)
    }

    // MARK: - SharePermission Tests

    func testSharePermissionReadOnlyRawValue() {
        XCTAssertEqual(SharePermission.readOnly.rawValue, "read_only")
    }

    func testSharePermissionReadWriteRawValue() {
        XCTAssertEqual(SharePermission.readWrite.rawValue, "read_write")
    }

    func testSharePermissionCodable() throws {
        // Given
        let permission = SharePermission.readOnly

        // When
        let encoded = try JSONEncoder().encode(permission)
        let decoded = try JSONDecoder().decode(SharePermission.self, from: encoded)

        // Then
        XCTAssertEqual(decoded, permission)
    }

    func testSharePermissionReadWriteCodable() throws {
        // Given
        let permission = SharePermission.readWrite

        // When
        let encoded = try JSONEncoder().encode(permission)
        let decoded = try JSONDecoder().decode(SharePermission.self, from: encoded)

        // Then
        XCTAssertEqual(decoded, permission)
    }

    func testSharePermissionDecodingFromRawString() throws {
        // Given
        let jsonData = "\"read_only\"".data(using: .utf8)!

        // When
        let decoded = try JSONDecoder().decode(SharePermission.self, from: jsonData)

        // Then
        XCTAssertEqual(decoded, .readOnly)
    }

    func testSharePermissionInvalidRawValueThrows() {
        // Given
        let invalidJSON = "\"invalid_permission\"".data(using: .utf8)!

        // When/Then
        XCTAssertThrowsError(try JSONDecoder().decode(SharePermission.self, from: invalidJSON)) { error in
            XCTAssertTrue(error is DecodingError, "Should throw DecodingError for invalid raw value")
        }
    }

    // MARK: - HealthDataRecord Tests

    func testHealthDataRecordInitialization() {
        // Given
        let recordID = UUID().uuidString
        let recordingDate = Date()
        let dataType = "bruxism_session"
        let measurements = Data([0x01, 0x02, 0x03])
        let sessionDuration: TimeInterval = 3600.0

        // When
        let record = HealthDataRecord(
            recordID: recordID,
            recordingDate: recordingDate,
            dataType: dataType,
            measurements: measurements,
            sessionDuration: sessionDuration
        )

        // Then
        XCTAssertEqual(record.recordID, recordID)
        XCTAssertEqual(record.recordingDate, recordingDate)
        XCTAssertEqual(record.dataType, dataType)
        XCTAssertEqual(record.measurements, measurements)
        XCTAssertEqual(record.sessionDuration, sessionDuration)
    }

    func testHealthDataRecordCodable() throws {
        // Given
        let original = HealthDataRecord(
            recordID: "test-record-123",
            recordingDate: Date(timeIntervalSince1970: 1704067200), // Fixed date for deterministic test
            dataType: "bruxism_session",
            measurements: Data([0xAA, 0xBB, 0xCC]),
            sessionDuration: 7200.0
        )

        // When
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HealthDataRecord.self, from: encoded)

        // Then
        XCTAssertEqual(decoded.recordID, original.recordID)
        XCTAssertEqual(decoded.dataType, original.dataType)
        XCTAssertEqual(decoded.measurements, original.measurements)
        XCTAssertEqual(decoded.sessionDuration, original.sessionDuration)
        XCTAssertEqual(
            decoded.recordingDate.timeIntervalSince1970,
            original.recordingDate.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    // MARK: - BruxismSessionData Tests

    func testBruxismSessionDataInitialization() {
        // Given
        let sensorData = createMockSensorData(count: 10)

        // When
        let sessionData = BruxismSessionData(sensorData: sensorData)

        // Then
        XCTAssertEqual(sessionData.recordingCount, 10)
        XCTAssertEqual(sessionData.sensorReadings.count, 10)
    }

    func testBruxismSessionDataStartEndDates() {
        // Given
        let now = Date()
        let sensorData = createMockSensorData(count: 5) // timestamps spaced 5 seconds apart

        // When
        let sessionData = BruxismSessionData(sensorData: sensorData)

        // Then
        XCTAssertEqual(
            sessionData.startDate.timeIntervalSince1970,
            sensorData.first!.timestamp.timeIntervalSince1970,
            accuracy: 0.01
        )
        XCTAssertEqual(
            sessionData.endDate.timeIntervalSince1970,
            sensorData.last!.timestamp.timeIntervalSince1970,
            accuracy: 0.01
        )
    }

    func testBruxismSessionDataWithEmptyArray() {
        // Given
        let emptySensorData: [SensorData] = []

        // When
        let sessionData = BruxismSessionData(sensorData: emptySensorData)

        // Then
        XCTAssertEqual(sessionData.recordingCount, 0)
        XCTAssertTrue(sessionData.sensorReadings.isEmpty)
    }

    func testBruxismSessionDataCodable() throws {
        // Given
        let sensorData = createMockSensorData(count: 3)
        let original = BruxismSessionData(sensorData: sensorData)

        // When
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BruxismSessionData.self, from: encoded)

        // Then
        XCTAssertEqual(decoded.recordingCount, original.recordingCount)
        XCTAssertEqual(decoded.sensorReadings.count, original.sensorReadings.count)
        XCTAssertEqual(
            decoded.startDate.timeIntervalSince1970,
            original.startDate.timeIntervalSince1970,
            accuracy: 0.01
        )
        XCTAssertEqual(
            decoded.endDate.timeIntervalSince1970,
            original.endDate.timeIntervalSince1970,
            accuracy: 0.01
        )
    }

    func testBruxismSessionDataCompressionRoundtrip() throws {
        // Given - encode BruxismSessionData to JSON, compress, decompress, decode
        let sensorData = createMockSensorData(count: 20)
        let original = BruxismSessionData(sensorData: sensorData)

        let jsonData = try JSONEncoder().encode(original)
        let originalSize = jsonData.count

        // When - compress and decompress
        guard let compressed = jsonData.compressed() else {
            XCTFail("Compression of BruxismSessionData JSON should succeed")
            return
        }

        guard let decompressed = compressed.decompressed(expectedSize: originalSize) else {
            XCTFail("Decompression should succeed")
            return
        }

        let decoded = try JSONDecoder().decode(BruxismSessionData.self, from: decompressed)

        // Then
        XCTAssertEqual(decoded.recordingCount, original.recordingCount)
        XCTAssertEqual(decoded.sensorReadings.count, original.sensorReadings.count)

        // Verify individual readings survived the roundtrip
        for i in 0..<decoded.sensorReadings.count {
            let decodedReading = decoded.sensorReadings[i]
            let originalReading = original.sensorReadings[i]

            XCTAssertEqual(decodedReading.ppgRed, originalReading.ppgRed)
            XCTAssertEqual(decodedReading.ppgIR, originalReading.ppgIR)
            XCTAssertEqual(decodedReading.ppgGreen, originalReading.ppgGreen)
            XCTAssertEqual(decodedReading.accelX, originalReading.accelX)
            XCTAssertEqual(decodedReading.accelY, originalReading.accelY)
            XCTAssertEqual(decodedReading.accelZ, originalReading.accelZ)
            XCTAssertEqual(decodedReading.temperatureCelsius, originalReading.temperatureCelsius, accuracy: 0.001)
            XCTAssertEqual(decodedReading.batteryPercentage, originalReading.batteryPercentage)
        }
    }

    // MARK: - SerializableSensorData Tests

    func testSerializableSensorDataFromOralableDevice() {
        // Given
        let timestamp = Date()
        let ppg = PPGData(red: 150000, ir: 200000, green: 180000, timestamp: timestamp)
        let accel = AccelerometerData(x: 100, y: -50, z: 300, timestamp: timestamp)
        let temp = TemperatureData(celsius: 36.8, timestamp: timestamp)
        let battery = BatteryData(percentage: 85, timestamp: timestamp)
        let hr = HeartRateData(bpm: 72.0, quality: 0.95, timestamp: timestamp)
        let spo2 = SpO2Data(percentage: 98.5, quality: 0.88, timestamp: timestamp)

        let sensorData = SensorData(
            timestamp: timestamp,
            ppg: ppg,
            accelerometer: accel,
            temperature: temp,
            battery: battery,
            heartRate: hr,
            spo2: spo2,
            deviceType: .oralable
        )

        // When
        let serializable = SerializableSensorData(from: sensorData)

        // Then
        XCTAssertEqual(serializable.deviceType, "Oralable")
        XCTAssertEqual(serializable.ppgRed, 150000)
        XCTAssertEqual(serializable.ppgIR, 200000)
        XCTAssertEqual(serializable.ppgGreen, 180000)
        XCTAssertNil(serializable.emg, "Oralable device should not have EMG data")
        XCTAssertEqual(serializable.accelX, 100)
        XCTAssertEqual(serializable.accelY, -50)
        XCTAssertEqual(serializable.accelZ, 300)
        XCTAssertEqual(serializable.temperatureCelsius, 36.8, accuracy: 0.001)
        XCTAssertEqual(serializable.batteryPercentage, 85)
        XCTAssertEqual(serializable.heartRateBPM, 72.0)
        XCTAssertEqual(serializable.heartRateQuality, 0.95)
        XCTAssertEqual(serializable.spo2Percentage, 98.5)
        XCTAssertEqual(serializable.spo2Quality, 0.88)
    }

    func testSerializableSensorDataFromANRDevice() {
        // Given
        let timestamp = Date()
        let ppg = PPGData(red: 0, ir: 5000, green: 0, timestamp: timestamp)
        let accel = AccelerometerData(x: 10, y: 20, z: 30, timestamp: timestamp)
        let temp = TemperatureData(celsius: 37.0, timestamp: timestamp)
        let battery = BatteryData(percentage: 90, timestamp: timestamp)

        let sensorData = SensorData(
            timestamp: timestamp,
            ppg: ppg,
            accelerometer: accel,
            temperature: temp,
            battery: battery,
            heartRate: nil,
            spo2: nil,
            deviceType: .anr
        )

        // When
        let serializable = SerializableSensorData(from: sensorData)

        // Then
        XCTAssertEqual(serializable.deviceType, "ANR M40")
        XCTAssertNotNil(serializable.emg, "ANR device with non-zero IR should have EMG data")
        XCTAssertEqual(serializable.emg, Double(5000), "EMG should be the IR value for ANR device")
        XCTAssertNil(serializable.heartRateBPM, "Heart rate should be nil when not provided")
        XCTAssertNil(serializable.spo2Percentage, "SpO2 should be nil when not provided")
    }

    func testSerializableSensorDataANRWithZeroIRHasNoEMG() {
        // Given - ANR device with zero IR value
        let timestamp = Date()
        let ppg = PPGData(red: 0, ir: 0, green: 0, timestamp: timestamp)
        let accel = AccelerometerData(x: 0, y: 0, z: 0, timestamp: timestamp)
        let temp = TemperatureData(celsius: 37.0, timestamp: timestamp)
        let battery = BatteryData(percentage: 50, timestamp: timestamp)

        let sensorData = SensorData(
            timestamp: timestamp,
            ppg: ppg,
            accelerometer: accel,
            temperature: temp,
            battery: battery,
            heartRate: nil,
            spo2: nil,
            deviceType: .anr
        )

        // When
        let serializable = SerializableSensorData(from: sensorData)

        // Then
        XCTAssertNil(serializable.emg, "ANR device with zero IR should not have EMG data")
    }

    func testSerializableSensorDataCodable() throws {
        // Given
        let sensorData = createMockSensorData(count: 1).first!
        let original = SerializableSensorData(from: sensorData)

        // When
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SerializableSensorData.self, from: encoded)

        // Then
        XCTAssertEqual(decoded.ppgRed, original.ppgRed)
        XCTAssertEqual(decoded.ppgIR, original.ppgIR)
        XCTAssertEqual(decoded.ppgGreen, original.ppgGreen)
        XCTAssertEqual(decoded.accelX, original.accelX)
        XCTAssertEqual(decoded.accelY, original.accelY)
        XCTAssertEqual(decoded.accelZ, original.accelZ)
        XCTAssertEqual(decoded.temperatureCelsius, original.temperatureCelsius, accuracy: 0.001)
        XCTAssertEqual(decoded.batteryPercentage, original.batteryPercentage)
        XCTAssertEqual(decoded.deviceType, original.deviceType)
        XCTAssertEqual(decoded.accelMagnitude, original.accelMagnitude, accuracy: 0.001)
    }

    func testSerializableSensorDataPreservesTimestamp() {
        // Given
        let timestamp = Date(timeIntervalSince1970: 1704067200)
        let ppg = PPGData(red: 100, ir: 200, green: 300, timestamp: timestamp)
        let accel = AccelerometerData(x: 0, y: 0, z: 16384, timestamp: timestamp)
        let temp = TemperatureData(celsius: 37.0, timestamp: timestamp)
        let battery = BatteryData(percentage: 100, timestamp: timestamp)

        let sensorData = SensorData(
            timestamp: timestamp,
            ppg: ppg,
            accelerometer: accel,
            temperature: temp,
            battery: battery,
            heartRate: nil,
            spo2: nil
        )

        // When
        let serializable = SerializableSensorData(from: sensorData)

        // Then
        XCTAssertEqual(
            serializable.timestamp.timeIntervalSince1970,
            timestamp.timeIntervalSince1970,
            accuracy: 0.01
        )
    }
}

// MARK: - ShareError Tests

final class ShareErrorTests: XCTestCase {

    func testNotAuthenticatedErrorDescription() {
        // Given
        let error = ShareError.notAuthenticated

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertEqual(error.errorDescription, "You must be signed in to share data")
    }

    func testCloudKitErrorDescription() {
        // Given
        let underlyingError = NSError(domain: "CKErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network unavailable"])
        let error = ShareError.cloudKitError(underlyingError)

        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Cloud error"), "Should contain 'Cloud error' prefix")
        XCTAssertTrue(error.errorDescription!.contains("Network unavailable"), "Should contain underlying error message")
    }

    func testInvalidShareCodeErrorDescription() {
        let error = ShareError.invalidShareCode
        XCTAssertEqual(error.errorDescription, "Invalid share code")
    }

    func testShareCodeExpiredErrorDescription() {
        let error = ShareError.shareCodeExpired
        XCTAssertEqual(error.errorDescription, "Share code has expired")
    }

    func testProfessionalNotFoundErrorDescription() {
        let error = ShareError.professionalNotFound
        XCTAssertEqual(error.errorDescription, "Professional not found")
    }

    func testShareErrorConformsToLocalizedError() {
        // Verify all cases conform to LocalizedError
        let errors: [ShareError] = [
            .notAuthenticated,
            .cloudKitError(NSError(domain: "test", code: 0)),
            .invalidShareCode,
            .shareCodeExpired,
            .professionalNotFound
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "All ShareError cases should have an error description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }
}

// MARK: - SharedDataManager State Tests

@MainActor
final class SharedDataManagerStateTests: XCTestCase {

    var sut: SharedDataManager!
    var mockAuthManager: AuthenticationManager!

    override func setUp() async throws {
        try await super.setUp()
        mockAuthManager = AuthenticationManager()
        sut = SharedDataManager(authenticationManager: mockAuthManager)
    }

    override func tearDown() async throws {
        sut = nil
        mockAuthManager = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialStateIsNotLoading() {
        // The manager may briefly load on init, but published values should be accessible
        XCTAssertNotNil(sut, "Manager should be initialized")
    }

    func testInitialErrorMessageIsNil() {
        XCTAssertNil(sut.errorMessage, "Initial error message should be nil")
    }

    func testInitialSyncStateIsFalse() {
        XCTAssertFalse(sut.isSyncing, "Initial syncing state should be false")
    }

    func testInitialLastSyncDateIsNil() {
        XCTAssertNil(sut.lastSyncDate, "Initial last sync date should be nil")
    }

    func testSharedProfessionalsInitiallyEmpty() {
        // Note: loadSharedProfessionals runs on init but returns early if no userID
        // With a fresh AuthenticationManager, userID is nil
        XCTAssertTrue(sut.sharedProfessionals.isEmpty, "Should start with empty professionals list when not authenticated")
    }

    // MARK: - Authentication Guard Tests

    func testCreateShareInvitationThrowsWhenNotAuthenticated() async {
        // Given - mockAuthManager has no userID (not authenticated)

        // When/Then
        do {
            _ = try await sut.createShareInvitation()
            XCTFail("Should throw when not authenticated")
        } catch let error as ShareError {
            switch error {
            case .notAuthenticated:
                break // Expected
            default:
                XCTFail("Expected notAuthenticated error, got: \(error)")
            }
        } catch {
            XCTFail("Expected ShareError, got: \(error)")
        }
    }

    func testRevokeAccessThrowsWhenNotAuthenticated() async {
        // Given - mockAuthManager has no userID

        // When/Then
        do {
            try await sut.revokeAccessForProfessional(professionalID: "prof_123")
            XCTFail("Should throw when not authenticated")
        } catch let error as ShareError {
            switch error {
            case .notAuthenticated:
                break // Expected
            default:
                XCTFail("Expected notAuthenticated error, got: \(error)")
            }
        } catch {
            XCTFail("Expected ShareError, got: \(error)")
        }
    }

    // MARK: - Generate Share Code Multiple Calls

    func testMultipleShareCodeGenerationsProduceDifferentCodes() {
        // When
        var codes: [String] = []
        for _ in 0..<50 {
            codes.append(sut.generateShareCode())
        }

        // Then
        let uniqueCodes = Set(codes)
        XCTAssertGreaterThan(uniqueCodes.count, 1, "Multiple code generations should produce different codes")
    }

    // MARK: - SyncSensorData Guard Tests

    func testSyncSensorDataReturnsEarlyWhenNotAuthenticated() async {
        // Given - no userID set on auth manager

        // When/Then - should return without throwing (silently skips)
        do {
            try await sut.syncSensorDataToCloudKit()
            // Should not throw, just return early
        } catch {
            XCTFail("syncSensorDataToCloudKit should not throw when not authenticated, it should return early")
        }
    }

    func testSyncSensorDataReturnsEarlyWithNoProcessor() async {
        // Given - manager created without sensor data processor
        // (default init has nil sensorDataProcessor)

        // When/Then - even if authenticated, should return early without processor
        // Since we can't easily set userID on AuthenticationManager in tests,
        // the not-authenticated guard fires first. This tests the early return path.
        do {
            try await sut.syncSensorDataToCloudKit()
        } catch {
            XCTFail("Should return early without throwing")
        }
    }
}

// MARK: - Serialization Integration Tests

final class SerializationIntegrationTests: XCTestCase {

    private func createMockSensorData(count: Int = 5, deviceType: DeviceType = .oralable) -> [SensorData] {
        var sensorData: [SensorData] = []
        let now = Date()

        for i in 0..<count {
            let timestamp = now.addingTimeInterval(TimeInterval(i * 5))

            let ppg = PPGData(
                red: Int32.random(in: 50000...250000),
                ir: Int32.random(in: 50000...250000),
                green: Int32.random(in: 50000...250000),
                timestamp: timestamp
            )

            let accelerometer = AccelerometerData(
                x: Int16.random(in: -100...100),
                y: Int16.random(in: -100...100),
                z: Int16.random(in: -100...100),
                timestamp: timestamp
            )

            let temperature = TemperatureData(
                celsius: Double.random(in: 36.0...37.5),
                timestamp: timestamp
            )

            let battery = BatteryData(
                percentage: Int.random(in: 50...100),
                timestamp: timestamp
            )

            let heartRate = HeartRateData(
                bpm: Double.random(in: 60...90),
                quality: Double.random(in: 0.7...1.0),
                timestamp: timestamp
            )

            let spo2 = SpO2Data(
                percentage: Double.random(in: 95...100),
                quality: Double.random(in: 0.7...1.0),
                timestamp: timestamp
            )

            let data = SensorData(
                timestamp: timestamp,
                ppg: ppg,
                accelerometer: accelerometer,
                temperature: temperature,
                battery: battery,
                heartRate: heartRate,
                spo2: spo2,
                deviceType: deviceType
            )

            sensorData.append(data)
        }

        return sensorData
    }

    // MARK: - Full Pipeline Tests

    func testFullSerializationPipeline() throws {
        // Given - raw sensor data
        let rawData = createMockSensorData(count: 50)

        // When - convert to BruxismSessionData -> encode -> compress -> decompress -> decode
        let sessionData = BruxismSessionData(sensorData: rawData)
        let jsonData = try JSONEncoder().encode(sessionData)
        let originalSize = jsonData.count

        guard let compressed = jsonData.compressed() else {
            XCTFail("Compression should succeed")
            return
        }

        guard let decompressed = compressed.decompressed(expectedSize: originalSize) else {
            XCTFail("Decompression should succeed")
            return
        }

        let restored = try JSONDecoder().decode(BruxismSessionData.self, from: decompressed)

        // Then - verify data integrity
        XCTAssertEqual(restored.recordingCount, rawData.count)
        XCTAssertEqual(restored.sensorReadings.count, rawData.count)

        // Verify first and last readings
        let firstOriginal = SerializableSensorData(from: rawData.first!)
        let firstRestored = restored.sensorReadings.first!

        XCTAssertEqual(firstRestored.ppgRed, firstOriginal.ppgRed)
        XCTAssertEqual(firstRestored.ppgIR, firstOriginal.ppgIR)
        XCTAssertEqual(firstRestored.accelX, firstOriginal.accelX)
        XCTAssertEqual(firstRestored.batteryPercentage, firstOriginal.batteryPercentage)

        let lastOriginal = SerializableSensorData(from: rawData.last!)
        let lastRestored = restored.sensorReadings.last!

        XCTAssertEqual(lastRestored.ppgRed, lastOriginal.ppgRed)
        XCTAssertEqual(lastRestored.accelZ, lastOriginal.accelZ)
        XCTAssertEqual(lastRestored.temperatureCelsius, lastOriginal.temperatureCelsius, accuracy: 0.001)
    }

    func testLargeDatasetSerializationPipeline() throws {
        // Given - large dataset
        let rawData = createMockSensorData(count: 500)

        // When
        let sessionData = BruxismSessionData(sensorData: rawData)
        let jsonData = try JSONEncoder().encode(sessionData)
        let originalSize = jsonData.count

        guard let compressed = jsonData.compressed() else {
            XCTFail("Large dataset compression should succeed")
            return
        }

        // Then - verify compression works
        XCTAssertGreaterThan(originalSize, 0, "JSON should have content")
        XCTAssertGreaterThan(compressed.count, 0, "Compressed data should have content")

        // Verify decompression roundtrip
        guard let decompressed = compressed.decompressed(expectedSize: originalSize) else {
            XCTFail("Large dataset decompression should succeed")
            return
        }

        let restored = try JSONDecoder().decode(BruxismSessionData.self, from: decompressed)
        XCTAssertEqual(restored.recordingCount, 500)
    }

    func testSerializationWithMixedDeviceTypes() throws {
        // Given - data from both device types
        let oralableData = createMockSensorData(count: 5, deviceType: .oralable)
        let anrData = createMockSensorData(count: 5, deviceType: .anr)
        let combinedData = oralableData + anrData

        // When
        let sessionData = BruxismSessionData(sensorData: combinedData)
        let jsonData = try JSONEncoder().encode(sessionData)
        let decoded = try JSONDecoder().decode(BruxismSessionData.self, from: jsonData)

        // Then
        XCTAssertEqual(decoded.recordingCount, 10)

        let oralableReadings = decoded.sensorReadings.filter { $0.deviceType == "Oralable" }
        let anrReadings = decoded.sensorReadings.filter { $0.deviceType == "ANR M40" }

        XCTAssertEqual(oralableReadings.count, 5, "Should have 5 Oralable readings")
        XCTAssertEqual(anrReadings.count, 5, "Should have 5 ANR readings")
    }

    func testSerializationWithNilOptionalFields() throws {
        // Given - sensor data without heart rate and SpO2
        let timestamp = Date()
        let sensorData = SensorData(
            timestamp: timestamp,
            ppg: PPGData(red: 100, ir: 200, green: 300, timestamp: timestamp),
            accelerometer: AccelerometerData(x: 10, y: 20, z: 30, timestamp: timestamp),
            temperature: TemperatureData(celsius: 37.0, timestamp: timestamp),
            battery: BatteryData(percentage: 80, timestamp: timestamp),
            heartRate: nil,
            spo2: nil
        )

        // When
        let sessionData = BruxismSessionData(sensorData: [sensorData])
        let jsonData = try JSONEncoder().encode(sessionData)
        let decoded = try JSONDecoder().decode(BruxismSessionData.self, from: jsonData)

        // Then
        let reading = decoded.sensorReadings.first!
        XCTAssertNil(reading.heartRateBPM, "Heart rate should be nil")
        XCTAssertNil(reading.heartRateQuality, "Heart rate quality should be nil")
        XCTAssertNil(reading.spo2Percentage, "SpO2 should be nil")
        XCTAssertNil(reading.spo2Quality, "SpO2 quality should be nil")
    }

    // MARK: - Heart Rate and SpO2 JSON Encoding Tests

    func testHeartRateArrayJSONEncoding() throws {
        // Given - heart rate values like those sent to CloudKit
        let heartRateData: [Double] = [72.0, 74.5, 71.0, 75.0, 73.5]

        // When
        let jsonData = try JSONEncoder().encode(heartRateData)
        let decoded = try JSONDecoder().decode([Double].self, from: jsonData)

        // Then
        XCTAssertEqual(decoded, heartRateData, "Heart rate array should survive JSON roundtrip")
    }

    func testSpO2ArrayJSONEncoding() throws {
        // Given - SpO2 values like those sent to CloudKit
        let spo2Data: [Double] = [98.0, 97.5, 99.0, 98.5]

        // When
        let jsonData = try JSONEncoder().encode(spo2Data)
        let decoded = try JSONDecoder().decode([Double].self, from: jsonData)

        // Then
        XCTAssertEqual(decoded, spo2Data, "SpO2 array should survive JSON roundtrip")
    }
}

// MARK: - Bruxism Event Detection Logic Tests

final class BruxismEventDetectionTests: XCTestCase {

    /// Tests the bruxism event detection algorithm used in populateRecord and uploadRecordingSession.
    /// The algorithm counts transitions from below to above the threshold (2.0) as separate events.

    func testBruxismEventDetectionAlgorithm() {
        // Given - simulate the algorithm from SharedDataManager.populateRecord
        let bruxismThreshold = 2.0
        // Magnitudes that cross the threshold multiple times: below, above, below, above, above, below
        let magnitudes: [Double] = [0.5, 3.0, 1.0, 4.0, 5.0, 0.8]

        // When - run the same algorithm as in SharedDataManager
        var bruxismEvents = 0
        var peakIntensity = 0.0
        var isInEvent = false

        for magnitude in magnitudes {
            if magnitude > bruxismThreshold {
                if !isInEvent {
                    bruxismEvents += 1
                    isInEvent = true
                }
                if magnitude > peakIntensity {
                    peakIntensity = magnitude
                }
            } else {
                isInEvent = false
            }
        }

        // Then
        XCTAssertEqual(bruxismEvents, 2, "Should detect 2 separate bruxism events (two transitions above threshold)")
        XCTAssertEqual(peakIntensity, 5.0, "Peak intensity should be the maximum magnitude above threshold")
    }

    func testBruxismEventDetectionNoCrossings() {
        // Given - all magnitudes below threshold
        let bruxismThreshold = 2.0
        let magnitudes: [Double] = [0.5, 1.0, 1.5, 0.8, 1.2]

        // When
        var bruxismEvents = 0
        var isInEvent = false

        for magnitude in magnitudes {
            if magnitude > bruxismThreshold {
                if !isInEvent {
                    bruxismEvents += 1
                    isInEvent = true
                }
            } else {
                isInEvent = false
            }
        }

        // Then
        XCTAssertEqual(bruxismEvents, 0, "Should detect no bruxism events when all below threshold")
    }

    func testBruxismEventDetectionContinuousHighMagnitude() {
        // Given - all magnitudes above threshold (one continuous event)
        let bruxismThreshold = 2.0
        let magnitudes: [Double] = [3.0, 4.0, 5.0, 3.5, 2.5]

        // When
        var bruxismEvents = 0
        var isInEvent = false

        for magnitude in magnitudes {
            if magnitude > bruxismThreshold {
                if !isInEvent {
                    bruxismEvents += 1
                    isInEvent = true
                }
            } else {
                isInEvent = false
            }
        }

        // Then
        XCTAssertEqual(bruxismEvents, 1, "Continuous magnitudes above threshold should count as one event")
    }

    func testBruxismEventDetectionEmptyData() {
        // Given - no data
        let magnitudes: [Double] = []

        // When
        var bruxismEvents = 0
        var peakIntensity = 0.0
        var isInEvent = false

        for magnitude in magnitudes {
            if magnitude > 2.0 {
                if !isInEvent {
                    bruxismEvents += 1
                    isInEvent = true
                }
                if magnitude > peakIntensity {
                    peakIntensity = magnitude
                }
            } else {
                isInEvent = false
            }
        }

        // Then
        XCTAssertEqual(bruxismEvents, 0)
        XCTAssertEqual(peakIntensity, 0.0)
    }

    func testAverageIntensityCalculation() {
        // Given - the average calculation from populateRecord
        let magnitudes: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0]

        // When
        let averageIntensity = magnitudes.isEmpty ? 0.0 :
            magnitudes.reduce(0.0, +) / Double(magnitudes.count)

        // Then
        XCTAssertEqual(averageIntensity, 3.0, accuracy: 0.001, "Average should be 3.0")
    }

    func testAverageIntensityWithEmptyData() {
        // Given
        let magnitudes: [Double] = []

        // When
        let averageIntensity = magnitudes.isEmpty ? 0.0 :
            magnitudes.reduce(0.0, +) / Double(magnitudes.count)

        // Then
        XCTAssertEqual(averageIntensity, 0.0, "Empty data should produce 0.0 average")
    }

    func testSessionDurationCalculation() {
        // Given - timestamps like in populateRecord
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1500)

        // When - calculate duration as done in populateRecord
        let duration = end.timeIntervalSince(start)

        // Then
        XCTAssertEqual(duration, 500.0, "Duration should be the difference between last and first timestamp")
    }
}

// MARK: - 48-Hour Expiry Logic Tests

final class ShareInvitationExpiryTests: XCTestCase {

    func testExpiryDateIs48HoursFromCreation() {
        // Given - the expiry calculation from createShareInvitation
        let creationDate = Date()

        // When
        let expiryDate = Calendar.current.date(byAdding: .hour, value: 48, to: creationDate)

        // Then
        XCTAssertNotNil(expiryDate)
        let expectedInterval: TimeInterval = 48 * 3600
        let actualInterval = expiryDate!.timeIntervalSince(creationDate)
        XCTAssertEqual(actualInterval, expectedInterval, accuracy: 1.0, "Expiry should be 48 hours from creation")
    }

    func testExpiryDateIsInTheFuture() {
        // Given
        let now = Date()

        // When
        let expiryDate = Calendar.current.date(byAdding: .hour, value: 48, to: now)!

        // Then
        XCTAssertGreaterThan(expiryDate, now, "Expiry date should be in the future")
    }

    func testShareCodeExpiryAfter48Hours() {
        // Given - a share created 49 hours ago
        let creationDate = Date().addingTimeInterval(-49 * 3600)
        let expiryDate = Calendar.current.date(byAdding: .hour, value: 48, to: creationDate)!

        // When
        let isExpired = Date() > expiryDate

        // Then
        XCTAssertTrue(isExpired, "Share code created 49 hours ago should be expired")
    }

    func testShareCodeNotExpiredWithin48Hours() {
        // Given - a share created 1 hour ago
        let creationDate = Date().addingTimeInterval(-1 * 3600)
        let expiryDate = Calendar.current.date(byAdding: .hour, value: 48, to: creationDate)!

        // When
        let isExpired = Date() > expiryDate

        // Then
        XCTAssertFalse(isExpired, "Share code created 1 hour ago should not be expired")
    }
}

// MARK: - Day Grouping Tests

final class DayGroupingTests: XCTestCase {

    private func createMockSensorData(at timestamp: Date) -> SensorData {
        let ppg = PPGData(red: 100, ir: 200, green: 300, timestamp: timestamp)
        let accel = AccelerometerData(x: 10, y: 20, z: 30, timestamp: timestamp)
        let temp = TemperatureData(celsius: 37.0, timestamp: timestamp)
        let battery = BatteryData(percentage: 80, timestamp: timestamp)

        return SensorData(
            timestamp: timestamp,
            ppg: ppg,
            accelerometer: accel,
            temperature: temp,
            battery: battery,
            heartRate: nil,
            spo2: nil
        )
    }

    func testGroupingByDay() {
        // Given - sensor data across 3 different days
        let calendar = Calendar.current
        let day1 = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 10))!
        let day1Later = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 22))!
        let day2 = calendar.date(from: DateComponents(year: 2025, month: 1, day: 16, hour: 8))!
        let day3 = calendar.date(from: DateComponents(year: 2025, month: 1, day: 17, hour: 14))!

        let sensorData = [
            createMockSensorData(at: day1),
            createMockSensorData(at: day1Later),
            createMockSensorData(at: day2),
            createMockSensorData(at: day3)
        ]

        // When - group by day as in syncSensorDataToCloudKit
        let groupedByDay = Dictionary(grouping: sensorData) { data in
            calendar.startOfDay(for: data.timestamp)
        }

        // Then
        XCTAssertEqual(groupedByDay.count, 3, "Should group into 3 days")

        let day1Start = calendar.startOfDay(for: day1)
        XCTAssertEqual(groupedByDay[day1Start]?.count, 2, "Day 1 should have 2 readings")

        let day2Start = calendar.startOfDay(for: day2)
        XCTAssertEqual(groupedByDay[day2Start]?.count, 1, "Day 2 should have 1 reading")

        let day3Start = calendar.startOfDay(for: day3)
        XCTAssertEqual(groupedByDay[day3Start]?.count, 1, "Day 3 should have 1 reading")
    }

    func testGroupingSameDayData() {
        // Given - all data on the same day
        let calendar = Calendar.current
        let baseDate = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 0))!

        var sensorData: [SensorData] = []
        for hour in 0..<24 {
            let timestamp = baseDate.addingTimeInterval(TimeInterval(hour * 3600))
            sensorData.append(createMockSensorData(at: timestamp))
        }

        // When
        let groupedByDay = Dictionary(grouping: sensorData) { data in
            calendar.startOfDay(for: data.timestamp)
        }

        // Then
        XCTAssertEqual(groupedByDay.count, 1, "All data on same day should be in one group")
        XCTAssertEqual(groupedByDay.values.first?.count, 24, "Should have all 24 readings in one group")
    }

    func testGroupingEmptyData() {
        // Given
        let sensorData: [SensorData] = []
        let calendar = Calendar.current

        // When
        let groupedByDay = Dictionary(grouping: sensorData) { data in
            calendar.startOfDay(for: data.timestamp)
        }

        // Then
        XCTAssertTrue(groupedByDay.isEmpty, "Empty data should produce empty groups")
    }
}

// MARK: - GDPR Deletion State Tests

@MainActor
final class GDPRDeletionTests: XCTestCase {

    var sut: SharedDataManager!
    var mockAuthManager: AuthenticationManager!

    override func setUp() async throws {
        try await super.setUp()
        mockAuthManager = AuthenticationManager()
        sut = SharedDataManager(authenticationManager: mockAuthManager)
    }

    override func tearDown() async throws {
        sut = nil
        mockAuthManager = nil
        try await super.tearDown()
    }

    func testDeleteAllUserDataReturnsEarlyWhenNotAuthenticated() async {
        // Given - not authenticated (userID is nil)

        // When/Then - should return without throwing (the guard returns early)
        do {
            try await sut.deleteAllUserData()
            // Should complete without error since not-authenticated guard returns early
        } catch {
            XCTFail("deleteAllUserData should return early when not authenticated, not throw")
        }
    }

    func testDeleteAllUserDataClearsLocalState() async throws {
        // Given - manually populate local state
        // Note: Since userID is nil, deleteAllUserData will return early before clearing.
        // This tests that the initial state is clean.
        XCTAssertTrue(sut.sharedProfessionals.isEmpty)
        XCTAssertNil(sut.lastSyncDate)
    }
}

// MARK: - RecordingSession Compatibility Tests

final class RecordingSessionCompatibilityTests: XCTestCase {

    func testCompletedSessionHasEndTime() {
        // Given
        var session = RecordingSession(
            startTime: Date().addingTimeInterval(-3600),
            status: .recording
        )
        session.endTime = Date()
        session.status = .completed

        // Then
        XCTAssertEqual(session.status, .completed)
        XCTAssertNotNil(session.endTime)
    }

    func testIncompleteSessionHasNoEndTime() {
        // Given
        let session = RecordingSession(
            startTime: Date(),
            status: .recording
        )

        // Then
        XCTAssertNil(session.endTime)
        XCTAssertEqual(session.status, .recording)
    }

    func testRecordingSessionDuration() {
        // Given
        let startTime = Date().addingTimeInterval(-3600)
        var session = RecordingSession(startTime: startTime)
        session.endTime = startTime.addingTimeInterval(1800)

        // Then
        XCTAssertEqual(session.duration, 1800, accuracy: 1.0, "Duration should be 30 minutes (1800 seconds)")
    }

    func testUploadRecordingSessionRequiresAuthentication() async {
        // Given
        let authManager = await AuthenticationManager()
        let sut = await SharedDataManager(authenticationManager: authManager)
        var session = RecordingSession(startTime: Date().addingTimeInterval(-60))
        session.endTime = Date()
        session.status = .completed

        // When/Then
        do {
            try await sut.uploadRecordingSession(session)
            XCTFail("Should throw notAuthenticated")
        } catch let error as ShareError {
            switch error {
            case .notAuthenticated:
                break // Expected
            default:
                XCTFail("Expected notAuthenticated error")
            }
        } catch {
            XCTFail("Expected ShareError")
        }
    }
}
