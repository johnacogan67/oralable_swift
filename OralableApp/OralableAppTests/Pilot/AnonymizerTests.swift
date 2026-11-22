//
//  AnonymizerTests.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: Unit tests for Anonymizer
//  Tests identifier stripping, trial ID generation, and timestamp obfuscation
//

import XCTest
@testable import MAMDiagnostics

final class AnonymizerTests: XCTestCase {

    // MARK: - Properties

    var anonymizer: Anonymizer!

    // MARK: - Test Lifecycle

    override func setUp() {
        super.setUp()
        anonymizer = Anonymizer(config: .default)
        anonymizer.clearMappings()
    }

    override func tearDown() {
        anonymizer.clearMappings()
        anonymizer = nil
        super.tearDown()
    }

    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let config = AnonymizationConfig.default

        XCTAssertTrue(config.obfuscateTimestamps)
        XCTAssertEqual(config.timestampGranularity, .minute)
        XCTAssertTrue(config.stripDeviceIdentifiers)
        XCTAssertTrue(config.stripUserIdentifiers)
        XCTAssertFalse(config.stripSessionIds)
        XCTAssertEqual(config.studyPrefix, "ORALABLE")
    }

    func testStrictConfiguration() {
        let config = AnonymizationConfig.strict

        XCTAssertTrue(config.obfuscateTimestamps)
        XCTAssertEqual(config.timestampGranularity, .hour)
        XCTAssertTrue(config.stripDeviceIdentifiers)
        XCTAssertTrue(config.stripUserIdentifiers)
        XCTAssertTrue(config.stripSessionIds)
        XCTAssertNotNil(config.trialSalt)
    }

    func testMinimalConfiguration() {
        let config = AnonymizationConfig.minimal

        XCTAssertFalse(config.obfuscateTimestamps)
        XCTAssertEqual(config.timestampGranularity, .second)
        XCTAssertTrue(config.stripDeviceIdentifiers)
        XCTAssertTrue(config.stripUserIdentifiers)
        XCTAssertFalse(config.stripSessionIds)
    }

    func testConfigureAnonymizer() {
        let customConfig = AnonymizationConfig(
            obfuscateTimestamps: false,
            timestampGranularity: .hour,
            stripDeviceIdentifiers: false,
            stripUserIdentifiers: false,
            stripSessionIds: true,
            trialSalt: "CUSTOM-SALT",
            studyPrefix: "CUSTOM"
        )

        anonymizer.configure(with: customConfig)

        XCTAssertEqual(anonymizer.currentConfig.studyPrefix, "CUSTOM")
        XCTAssertFalse(anonymizer.currentConfig.obfuscateTimestamps)
    }

    // MARK: - Trial ID Generation Tests

    func testGenerateTrialIdFromSessionId() {
        let sessionId = "SESSION-1234567890-5678"
        let trialId = anonymizer.generateTrialId(from: sessionId)

        XCTAssertTrue(trialId.hasPrefix("ORALABLE-TRIAL-"))
        XCTAssertFalse(trialId.contains(sessionId))
    }

    func testTrialIdConsistency() {
        let sessionId = "SESSION-1234567890-5678"

        let trialId1 = anonymizer.generateTrialId(from: sessionId)
        let trialId2 = anonymizer.generateTrialId(from: sessionId)

        XCTAssertEqual(trialId1, trialId2, "Same input should produce same trial ID")
    }

    func testDifferentSessionsProduceDifferentTrialIds() {
        let trialId1 = anonymizer.generateTrialId(from: "SESSION-001")
        let trialId2 = anonymizer.generateTrialId(from: "SESSION-002")

        XCTAssertNotEqual(trialId1, trialId2, "Different sessions should produce different trial IDs")
    }

    // MARK: - Participant ID Generation Tests

    func testGenerateParticipantId() {
        let participantId = anonymizer.generateParticipantId(
            deviceId: "DEVICE-UUID-1234",
            userId: "USER-APPLE-ID-5678"
        )

        XCTAssertTrue(participantId.hasPrefix("ORALABLE-P-"))
        XCTAssertFalse(participantId.contains("DEVICE-UUID"))
        XCTAssertFalse(participantId.contains("USER-APPLE"))
    }

    func testParticipantIdConsistency() {
        let participantId1 = anonymizer.generateParticipantId(
            deviceId: "DEVICE-001",
            userId: "USER-001"
        )
        let participantId2 = anonymizer.generateParticipantId(
            deviceId: "DEVICE-001",
            userId: "USER-001"
        )

        XCTAssertEqual(participantId1, participantId2, "Same device/user should produce same participant ID")
    }

    func testParticipantIdWithoutUserId() {
        let participantId = anonymizer.generateParticipantId(
            deviceId: "DEVICE-001",
            userId: nil
        )

        XCTAssertTrue(participantId.hasPrefix("ORALABLE-P-"))
    }

    // MARK: - Event Anonymization Tests

    func testAnonymizeSingleEvent() {
        let event = PilotEvent(
            eventType: .bleConnect,
            sessionId: "SESSION-ORIGINAL",
            deviceIdentifier: "DEVICE-UUID-ORIGINAL",
            userId: "USER-APPLE-ID",
            metadata: ["peripheralId": "PERIPH-001"]
        )

        let anonymized = anonymizer.anonymize(event)

        // Original identifiers should not appear
        XCTAssertNotEqual(anonymized.trialId, "SESSION-ORIGINAL")
        XCTAssertFalse(anonymized.trialId.contains("ORIGINAL"))
        XCTAssertFalse(anonymized.participantId.contains("DEVICE-UUID"))
        XCTAssertFalse(anonymized.participantId.contains("USER-APPLE"))

        // New ID should be assigned
        XCTAssertNotEqual(event.id, anonymized.id)

        // Event type should be preserved
        XCTAssertEqual(anonymized.eventType, .bleConnect)
        XCTAssertEqual(anonymized.category, .ble)
    }

    func testAnonymizeMultipleEvents() {
        let events = [
            PilotEvent(eventType: .bleConnect, sessionId: "S1", deviceIdentifier: "D1"),
            PilotEvent(eventType: .bleDisconnect, sessionId: "S1", deviceIdentifier: "D1"),
            PilotEvent(eventType: .sensorDataReceived, sessionId: "S1", deviceIdentifier: "D1")
        ]

        let anonymized = anonymizer.anonymize(events)

        XCTAssertEqual(anonymized.count, 3)

        // All events from same session should have same trial ID
        let trialIds = Set(anonymized.map { $0.trialId })
        XCTAssertEqual(trialIds.count, 1, "Same session should have same trial ID")

        // All events from same device should have same participant ID
        let participantIds = Set(anonymized.map { $0.participantId })
        XCTAssertEqual(participantIds.count, 1, "Same device should have same participant ID")
    }

    func testAnonymizePreservesEventData() {
        let event = PilotEvent(
            eventType: .sensorBruxismDetected,
            sessionId: "S1",
            deviceIdentifier: "D1",
            metadata: ["key": "value"],
            numericData: ["intensity": 0.85, "duration": 5.5],
            severity: .warning
        )

        let anonymized = anonymizer.anonymize(event)

        XCTAssertEqual(anonymized.eventType, .sensorBruxismDetected)
        XCTAssertEqual(anonymized.category, .sensor)
        XCTAssertEqual(anonymized.severity, .warning)
        XCTAssertEqual(anonymized.numericData?["intensity"], 0.85)
        XCTAssertEqual(anonymized.numericData?["duration"], 5.5)
    }

    // MARK: - Timestamp Obfuscation Tests

    func testTimestampObfuscationMinute() {
        anonymizer.configure(with: AnonymizationConfig(
            obfuscateTimestamps: true,
            timestampGranularity: .minute,
            stripDeviceIdentifiers: true,
            stripUserIdentifiers: true,
            stripSessionIds: false,
            trialSalt: nil,
            studyPrefix: "TEST"
        ))

        // Create a date with specific seconds
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 15
        components.hour = 14
        components.minute = 30
        components.second = 45
        let originalDate = Calendar.current.date(from: components)!

        let event = PilotEvent(
            eventType: .bleConnect,
            timestamp: originalDate,
            sessionId: "S1",
            deviceIdentifier: "D1"
        )

        let anonymized = anonymizer.anonymize(event)

        // Seconds should be stripped
        let anonymizedComponents = Calendar.current.dateComponents([.second], from: anonymized.timestamp)
        XCTAssertEqual(anonymizedComponents.second, 0, "Seconds should be zero when rounding to minute")
    }

    func testTimestampObfuscationHour() {
        anonymizer.configure(with: AnonymizationConfig(
            obfuscateTimestamps: true,
            timestampGranularity: .hour,
            stripDeviceIdentifiers: true,
            stripUserIdentifiers: true,
            stripSessionIds: false,
            trialSalt: nil,
            studyPrefix: "TEST"
        ))

        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 15
        components.hour = 14
        components.minute = 30
        components.second = 45
        let originalDate = Calendar.current.date(from: components)!

        let event = PilotEvent(
            eventType: .bleConnect,
            timestamp: originalDate,
            sessionId: "S1",
            deviceIdentifier: "D1"
        )

        let anonymized = anonymizer.anonymize(event)

        let anonymizedComponents = Calendar.current.dateComponents([.minute, .second], from: anonymized.timestamp)
        XCTAssertEqual(anonymizedComponents.minute, 0, "Minutes should be zero when rounding to hour")
        XCTAssertEqual(anonymizedComponents.second, 0, "Seconds should be zero when rounding to hour")
    }

    func testTimestampObfuscationFiveMinutes() {
        let granularity = TimestampGranularity.fiveMinutes

        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 15
        components.hour = 14
        components.minute = 33
        components.second = 45
        let originalDate = Calendar.current.date(from: components)!

        let rounded = granularity.round(originalDate)
        let roundedComponents = Calendar.current.dateComponents([.minute, .second], from: rounded)

        XCTAssertEqual(roundedComponents.minute, 30, "33 minutes should round to 30")
        XCTAssertEqual(roundedComponents.second, 0)
    }

    func testTimestampObfuscationFifteenMinutes() {
        let granularity = TimestampGranularity.fifteenMinutes

        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 15
        components.hour = 14
        components.minute = 47
        components.second = 30
        let originalDate = Calendar.current.date(from: components)!

        let rounded = granularity.round(originalDate)
        let roundedComponents = Calendar.current.dateComponents([.minute], from: rounded)

        XCTAssertEqual(roundedComponents.minute, 45, "47 minutes should round to 45")
    }

    func testTimestampObfuscationDay() {
        let granularity = TimestampGranularity.day

        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 15
        components.hour = 14
        components.minute = 30
        components.second = 45
        let originalDate = Calendar.current.date(from: components)!

        let rounded = granularity.round(originalDate)
        let roundedComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: rounded)

        XCTAssertEqual(roundedComponents.hour, 0)
        XCTAssertEqual(roundedComponents.minute, 0)
        XCTAssertEqual(roundedComponents.second, 0)
    }

    func testTimestampPreservedWhenNotObfuscating() {
        anonymizer.configure(with: .minimal) // obfuscateTimestamps = false

        let originalDate = Date()
        let event = PilotEvent(
            eventType: .bleConnect,
            timestamp: originalDate,
            sessionId: "S1",
            deviceIdentifier: "D1"
        )

        let anonymized = anonymizer.anonymize(event)

        XCTAssertEqual(anonymized.timestamp, originalDate, "Timestamp should be preserved when not obfuscating")
    }

    // MARK: - Metadata Cleaning Tests

    func testCleanMetadataStripsDeviceId() {
        let metadata = [
            "deviceId": "DEVICE-UUID-1234",
            "message": "Hello"
        ]

        let cleaned = anonymizer.cleanMetadata(metadata)

        XCTAssertEqual(cleaned["deviceId"], "[REDACTED]")
        XCTAssertEqual(cleaned["message"], "Hello")
    }

    func testCleanMetadataStripsUserId() {
        let metadata = [
            "userId": "USER-APPLE-ID-5678",
            "action": "login"
        ]

        let cleaned = anonymizer.cleanMetadata(metadata)

        XCTAssertEqual(cleaned["userId"], "[REDACTED]")
        XCTAssertEqual(cleaned["action"], "login")
    }

    func testCleanMetadataStripsUUIDValues() {
        let metadata = [
            "peripheralId": "12345678-1234-1234-1234-123456789012",
            "status": "connected"
        ]

        let cleaned = anonymizer.cleanMetadata(metadata)

        XCTAssertEqual(cleaned["peripheralId"], "[UUID-REDACTED]")
        XCTAssertEqual(cleaned["status"], "connected")
    }

    func testCleanMetadataStripsEmailValues() {
        let metadata = [
            "contact": "user@example.com",
            "type": "support"
        ]

        let cleaned = anonymizer.cleanMetadata(metadata)

        XCTAssertEqual(cleaned["contact"], "[EMAIL-REDACTED]")
        XCTAssertEqual(cleaned["type"], "support")
    }

    func testCleanMetadataPreservesNonSensitiveData() {
        let metadata = [
            "eventType": "BLE_CONNECT",
            "rssi": "-65",
            "batteryLevel": "85",
            "errorCode": "101"
        ]

        let cleaned = anonymizer.cleanMetadata(metadata)

        XCTAssertEqual(cleaned["eventType"], "BLE_CONNECT")
        XCTAssertEqual(cleaned["rssi"], "-65")
        XCTAssertEqual(cleaned["batteryLevel"], "85")
        XCTAssertEqual(cleaned["errorCode"], "101")
    }

    // MARK: - Validation Tests

    func testValidateAnonymizedEvent() {
        let event = PilotEvent(
            eventType: .bleConnect,
            sessionId: "S1",
            deviceIdentifier: "D1"
        )

        let anonymized = anonymizer.anonymize(event)
        let result = anonymizer.validateAnonymization(anonymized)

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testValidateBatch() {
        let events = [
            PilotEvent(eventType: .bleConnect, sessionId: "S1", deviceIdentifier: "D1"),
            PilotEvent(eventType: .bleDisconnect, sessionId: "S1", deviceIdentifier: "D1"),
            PilotEvent(eventType: .appForeground, sessionId: "S1", deviceIdentifier: "D1")
        ]

        let anonymized = anonymizer.anonymize(events)
        let result = anonymizer.validateBatch(anonymized)

        XCTAssertEqual(result.totalEvents, 3)
        XCTAssertEqual(result.validCount, 3)
        XCTAssertEqual(result.invalidCount, 0)
        XCTAssertEqual(result.passRate, 100.0)
    }

    // MARK: - Mapping Tests

    func testMappingCount() {
        XCTAssertEqual(anonymizer.mappingCount, 0)

        _ = anonymizer.generateTrialId(from: "SESSION-001")
        XCTAssertEqual(anonymizer.mappingCount, 1)

        _ = anonymizer.generateTrialId(from: "SESSION-002")
        XCTAssertEqual(anonymizer.mappingCount, 2)

        // Same input should not create new mapping
        _ = anonymizer.generateTrialId(from: "SESSION-001")
        XCTAssertEqual(anonymizer.mappingCount, 2)
    }

    func testClearMappings() {
        _ = anonymizer.generateTrialId(from: "SESSION-001")
        _ = anonymizer.generateParticipantId(deviceId: "D1", userId: "U1")

        XCTAssertGreaterThan(anonymizer.mappingCount, 0)

        anonymizer.clearMappings()

        XCTAssertEqual(anonymizer.mappingCount, 0)
    }

    func testClearMappingsOnConfigChange() {
        _ = anonymizer.generateTrialId(from: "SESSION-001")
        let firstId = anonymizer.generateTrialId(from: "SESSION-001")

        // Change config
        anonymizer.configure(with: .strict)

        let secondId = anonymizer.generateTrialId(from: "SESSION-001")

        // Should be different due to different salt and cleared mappings
        XCTAssertNotEqual(firstId, secondId)
    }

    // MARK: - Salt Tests

    func testSaltAffectsGeneratedIds() {
        let config1 = AnonymizationConfig(
            obfuscateTimestamps: true,
            timestampGranularity: .minute,
            stripDeviceIdentifiers: true,
            stripUserIdentifiers: true,
            stripSessionIds: false,
            trialSalt: "SALT-A",
            studyPrefix: "TEST"
        )

        let config2 = AnonymizationConfig(
            obfuscateTimestamps: true,
            timestampGranularity: .minute,
            stripDeviceIdentifiers: true,
            stripUserIdentifiers: true,
            stripSessionIds: false,
            trialSalt: "SALT-B",
            studyPrefix: "TEST"
        )

        let anonymizer1 = Anonymizer(config: config1)
        let anonymizer2 = Anonymizer(config: config2)

        let id1 = anonymizer1.generateTrialId(from: "SESSION-001")
        let id2 = anonymizer2.generateTrialId(from: "SESSION-001")

        XCTAssertNotEqual(id1, id2, "Different salts should produce different IDs")
    }

    // MARK: - Anonymized Event Model Tests

    func testAnonymizedEventCSVRow() {
        let event = AnonymizedEvent(
            id: UUID(),
            eventType: .bleConnect,
            category: .ble,
            timestamp: Date(),
            trialId: "TEST-TRIAL-001",
            participantId: "TEST-P-001",
            metadata: ["key": "value"],
            numericData: ["count": 42.0],
            severity: .info
        )

        let csvRow = event.csvRow

        XCTAssertTrue(csvRow.contains("BLE_CONNECT"))
        XCTAssertTrue(csvRow.contains("TEST-TRIAL-001"))
        XCTAssertTrue(csvRow.contains("TEST-P-001"))
        XCTAssertTrue(csvRow.contains("key=value"))
        XCTAssertTrue(csvRow.contains("count=42"))
    }

    func testAnonymizedEventISOTimestamp() {
        let event = AnonymizedEvent(
            id: UUID(),
            eventType: .bleConnect,
            category: .ble,
            timestamp: Date(),
            trialId: "T1",
            participantId: "P1",
            metadata: [:],
            numericData: nil,
            severity: .info
        )

        XCTAssertFalse(event.isoTimestamp.isEmpty)
        XCTAssertTrue(event.isoTimestamp.contains("T")) // ISO 8601 format
    }

    // MARK: - Timestamp Granularity Tests

    func testAllTimestampGranularities() {
        let testDate = Date()

        for granularity in TimestampGranularity.allCases {
            let rounded = granularity.round(testDate)
            XCTAssertNotNil(rounded, "Granularity \(granularity) should round successfully")
        }
    }
}
