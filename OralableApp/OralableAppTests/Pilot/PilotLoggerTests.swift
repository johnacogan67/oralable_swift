//
//  PilotLoggerTests.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: Unit tests for PilotLogger
//  Tests BLE, SensorData, and lifecycle event logging
//

import XCTest
@testable import MAMDiagnostics

@MainActor
final class PilotLoggerTests: XCTestCase {

    // MARK: - Properties

    var logger: PilotLogger!

    // MARK: - Test Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        logger = PilotLogger(maxEvents: 100, deviceIdentifier: "TEST-DEVICE-001")
        logger.clearEvents()
    }

    override func tearDown() async throws {
        logger.clearEvents()
        logger = nil
        try await super.tearDown()
    }

    // MARK: - Session Tests

    func testSessionIdGeneration() {
        XCTAssertFalse(logger.currentSessionId.isEmpty, "Session ID should not be empty")
        XCTAssertTrue(logger.currentSessionId.hasPrefix("SESSION-"), "Session ID should have SESSION prefix")
    }

    func testStartSession() {
        logger.startSession()

        XCTAssertTrue(logger.isLogging, "Logger should be logging after startSession")
        XCTAssertEqual(logger.events.count, 1, "Should have one app launch event")
        XCTAssertEqual(logger.events.first?.eventType, .appLaunch)
    }

    func testEndSession() {
        logger.startSession()
        logger.endSession()

        XCTAssertFalse(logger.isLogging, "Logger should not be logging after endSession")

        let terminateEvents = logger.events.filter { $0.eventType == .appTerminate }
        XCTAssertEqual(terminateEvents.count, 1, "Should have one app terminate event")
    }

    func testNewSessionGeneratesNewId() {
        let firstSessionId = logger.currentSessionId
        logger.startSession()
        let secondSessionId = logger.currentSessionId

        XCTAssertNotEqual(firstSessionId, secondSessionId, "Each session should have unique ID")
    }

    // MARK: - BLE Event Logging Tests

    func testLogBLEConnect() {
        logger.logBLEConnect(peripheralId: "PERIPH-001", peripheralName: "Oralable Device", rssi: -65)

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .bleConnect)
        XCTAssertEqual(event.category, .ble)
        XCTAssertEqual(event.metadata["peripheralId"], "PERIPH-001")
        XCTAssertEqual(event.metadata["peripheralName"], "Oralable Device")
        XCTAssertEqual(event.numericData?["rssi"], -65.0)
    }

    func testLogBLEDisconnect() {
        logger.logBLEDisconnect(peripheralId: "PERIPH-001", reason: "User disconnected")

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .bleDisconnect)
        XCTAssertEqual(event.severity, .warning)
        XCTAssertEqual(event.metadata["reason"], "User disconnected")
    }

    func testLogBLEReconnectAttempt() {
        logger.logBLEReconnectAttempt(peripheralId: "PERIPH-001", attemptNumber: 3)

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .bleReconnectAttempt)
        XCTAssertEqual(event.metadata["attemptNumber"], "3")
    }

    func testLogBLEReconnectSuccess() {
        logger.logBLEReconnectSuccess(peripheralId: "PERIPH-001", attemptNumber: 2, durationMs: 1500)

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .bleReconnectSuccess)
        XCTAssertEqual(event.numericData?["attemptNumber"], 2.0)
        XCTAssertEqual(event.numericData?["durationMs"], 1500.0)
    }

    func testLogBLEReconnectFailure() {
        logger.logBLEReconnectFailure(peripheralId: "PERIPH-001", totalAttempts: 5, error: "Timeout")

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .bleReconnectFailure)
        XCTAssertEqual(event.severity, .error)
        XCTAssertEqual(event.metadata["totalAttempts"], "5")
        XCTAssertEqual(event.metadata["error"], "Timeout")
    }

    func testLogBLEDataReceived() {
        logger.logBLEDataReceived(peripheralId: "PERIPH-001", dataSize: 256, characteristicId: "CHAR-001")

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .bleDataReceived)
        XCTAssertEqual(event.severity, .debug)
        XCTAssertEqual(event.numericData?["dataSize"], 256.0)
    }

    func testLogBLEError() {
        logger.logBLEError(peripheralId: "PERIPH-001", errorCode: 101, errorMessage: "Connection timeout")

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .bleError)
        XCTAssertEqual(event.severity, .error)
        XCTAssertEqual(event.metadata["errorCode"], "101")
        XCTAssertEqual(event.metadata["errorMessage"], "Connection timeout")
    }

    // MARK: - Sensor Data Event Logging Tests

    func testLogSensorDataReceived() {
        logger.logSensorDataReceived(
            ppgIR: 50000,
            ppgRed: 45000,
            ppgGreen: 40000,
            temperature: 36.5,
            batteryLevel: 85
        )

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .sensorDataReceived)
        XCTAssertEqual(event.category, .sensor)
        XCTAssertEqual(event.numericData?["ppgIR"], 50000.0)
        XCTAssertEqual(event.numericData?["ppgRed"], 45000.0)
        XCTAssertEqual(event.numericData?["ppgGreen"], 40000.0)
        XCTAssertEqual(event.numericData?["temperature"], 36.5)
        XCTAssertEqual(event.numericData?["batteryLevel"], 85.0)
    }

    func testLogBruxismDetected() {
        logger.logBruxismDetected(intensity: 0.85, duration: 5.5, confidence: 0.92)

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .sensorBruxismDetected)
        XCTAssertEqual(event.numericData?["intensity"], 0.85)
        XCTAssertEqual(event.numericData?["durationSeconds"], 5.5)
        XCTAssertEqual(event.numericData?["confidence"], 0.92)
    }

    func testLogSleepCycleStart() {
        logger.logSleepCycleStart(cycleNumber: 3)

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .sensorSleepCycleStart)
        XCTAssertEqual(event.metadata["cycleNumber"], "3")
    }

    func testLogSleepCycleEnd() {
        logger.logSleepCycleEnd(cycleNumber: 3, durationMinutes: 90.5, stage: "REM")

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .sensorSleepCycleEnd)
        XCTAssertEqual(event.metadata["cycleNumber"], "3")
        XCTAssertEqual(event.metadata["sleepStage"], "REM")
        XCTAssertEqual(event.numericData?["durationMinutes"], 90.5)
    }

    func testLogSensorAnomaly() {
        logger.logSensorAnomaly(sensorType: "PPG_IR", value: 999999, expectedRange: "40000-60000")

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .sensorAnomalyDetected)
        XCTAssertEqual(event.severity, .warning)
        XCTAssertEqual(event.metadata["sensorType"], "PPG_IR")
        XCTAssertEqual(event.numericData?["anomalousValue"], 999999.0)
    }

    func testLogThresholdExceeded() {
        logger.logThresholdExceeded(metric: "heartRate", value: 150, threshold: 120, direction: "above")

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .sensorThresholdExceeded)
        XCTAssertEqual(event.metadata["metric"], "heartRate")
        XCTAssertEqual(event.metadata["direction"], "above")
        XCTAssertEqual(event.numericData?["value"], 150.0)
        XCTAssertEqual(event.numericData?["threshold"], 120.0)
    }

    // MARK: - App Lifecycle Event Logging Tests

    func testLogAppForeground() {
        logger.logAppForeground()

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .appForeground)
        XCTAssertEqual(event.category, .lifecycle)
        XCTAssertNotNil(event.metadata["memoryUsage"])
    }

    func testLogAppBackground() {
        logger.logAppBackground()

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .appBackground)
        XCTAssertNotNil(event.metadata["memoryUsage"])
    }

    func testLogAppSuspend() {
        logger.logAppSuspend()

        XCTAssertEqual(logger.events.count, 1)
        XCTAssertEqual(logger.events.first?.eventType, .appSuspend)
    }

    func testLogAppResume() {
        logger.logAppResume()

        XCTAssertEqual(logger.events.count, 1)
        XCTAssertEqual(logger.events.first?.eventType, .appResume)
    }

    // MARK: - User Interaction Event Tests

    func testLogRecordingStart() {
        logger.logRecordingStart()

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .userRecordingStart)
        XCTAssertEqual(event.category, .userInteraction)
    }

    func testLogRecordingStop() {
        logger.logRecordingStop(durationMinutes: 45.5, dataPointsCollected: 5400)

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .userRecordingStop)
        XCTAssertEqual(event.numericData?["durationMinutes"], 45.5)
        XCTAssertEqual(event.numericData?["dataPointsCollected"], 5400.0)
    }

    func testLogDataExportSuccess() {
        logger.logDataExport(format: "CSV", recordCount: 1000, success: true)

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .userExportData)
        XCTAssertEqual(event.metadata["format"], "CSV")
        XCTAssertEqual(event.metadata["success"], "true")
        XCTAssertEqual(event.severity, .info)
    }

    func testLogDataExportFailure() {
        logger.logDataExport(format: "JSON", recordCount: 0, success: false, error: "Permission denied")

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .userExportData)
        XCTAssertEqual(event.metadata["success"], "false")
        XCTAssertEqual(event.metadata["error"], "Permission denied")
        XCTAssertEqual(event.severity, .error)
    }

    func testLogSettingsChange() {
        logger.logSettingsChange(setting: "notificationsEnabled", oldValue: "true", newValue: "false")

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .userSettingsChange)
        XCTAssertEqual(event.metadata["setting"], "notificationsEnabled")
        XCTAssertEqual(event.metadata["oldValue"], "true")
        XCTAssertEqual(event.metadata["newValue"], "false")
    }

    // MARK: - System Event Tests

    func testLogLowMemory() {
        logger.logLowMemory(availableBytes: 50_000_000)

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .systemLowMemory)
        XCTAssertEqual(event.category, .system)
        XCTAssertEqual(event.severity, .warning)
        XCTAssertEqual(event.numericData?["availableBytes"], 50_000_000.0)
    }

    func testLogLowBattery() {
        logger.logLowBattery(level: 15)

        XCTAssertEqual(logger.events.count, 1)

        let event = logger.events.first!
        XCTAssertEqual(event.eventType, .systemLowBattery)
        XCTAssertEqual(event.numericData?["batteryLevel"], 15.0)
    }

    // MARK: - Event Filtering Tests

    func testFilterEventsByType() {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: nil)
        logger.logBLEDisconnect(peripheralId: "P1", reason: nil)
        logger.logBLEConnect(peripheralId: "P2", peripheralName: nil)

        let connectEvents = logger.events(ofType: .bleConnect)
        XCTAssertEqual(connectEvents.count, 2)

        let disconnectEvents = logger.events(ofType: .bleDisconnect)
        XCTAssertEqual(disconnectEvents.count, 1)
    }

    func testFilterEventsByCategory() {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: nil)
        logger.logBruxismDetected(intensity: 0.5, duration: 1.0, confidence: 0.8)
        logger.logAppForeground()

        let bleEvents = logger.events(inCategory: .ble)
        XCTAssertEqual(bleEvents.count, 1)

        let sensorEvents = logger.events(inCategory: .sensor)
        XCTAssertEqual(sensorEvents.count, 1)

        let lifecycleEvents = logger.events(inCategory: .lifecycle)
        XCTAssertEqual(lifecycleEvents.count, 1)
    }

    func testFilterEventsBySeverity() {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: nil)  // info
        logger.logBLEDisconnect(peripheralId: "P1", reason: nil)       // warning
        logger.logBLEError(peripheralId: "P1", errorCode: 1, errorMessage: "Error")  // error

        let infoEvents = logger.events(withSeverity: .info)
        XCTAssertEqual(infoEvents.count, 1)

        let warningEvents = logger.events(withSeverity: .warning)
        XCTAssertEqual(warningEvents.count, 1)

        let errorEvents = logger.events(withSeverity: .error)
        XCTAssertEqual(errorEvents.count, 1)
    }

    func testFilterEventsByDateRange() {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let twoHoursAgo = now.addingTimeInterval(-7200)

        logger.logBLEConnect(peripheralId: "P1", peripheralName: nil)

        // All events should be within the last hour
        let recentEvents = logger.events(from: oneHourAgo, to: now)
        XCTAssertEqual(recentEvents.count, 1)

        // No events should be from 2 hours ago to 1 hour ago
        let oldEvents = logger.events(from: twoHoursAgo, to: oneHourAgo)
        XCTAssertEqual(oldEvents.count, 0)
    }

    // MARK: - Event Limits Tests

    func testMaxEventsLimit() {
        let smallLogger = PilotLogger(maxEvents: 5, deviceIdentifier: "TEST")

        for i in 0..<10 {
            smallLogger.logBLEConnect(peripheralId: "P\(i)", peripheralName: nil)
        }

        // Allow time for async operations
        let expectation = XCTestExpectation(description: "Events added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertLessThanOrEqual(smallLogger.events.count, 5, "Should not exceed max events")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testClearEvents() {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: nil)
        logger.logBLEConnect(peripheralId: "P2", peripheralName: nil)

        XCTAssertEqual(logger.events.count, 2)

        logger.clearEvents()

        XCTAssertEqual(logger.events.count, 0)
    }

    // MARK: - Export Tests

    func testExportToJSON() {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: "Test Device")
        logger.logBruxismDetected(intensity: 0.7, duration: 3.0, confidence: 0.85)

        let jsonData = logger.exportToJSON()

        XCTAssertNotNil(jsonData, "JSON export should produce data")

        // Verify it's valid JSON
        if let data = jsonData {
            do {
                let decoded = try JSONDecoder().decode([PilotEvent].self, from: data)
                XCTAssertEqual(decoded.count, 2, "Should decode 2 events")
            } catch {
                XCTFail("JSON decoding failed: \(error)")
            }
        }
    }

    func testExportToCSV() {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: "Test Device")
        logger.logBruxismDetected(intensity: 0.7, duration: 3.0, confidence: 0.85)

        let csv = logger.exportToCSV()

        XCTAssertTrue(csv.contains("ID,EventType,Category"), "CSV should have headers")
        XCTAssertTrue(csv.contains("BLE_CONNECT"), "CSV should contain BLE connect event")
        XCTAssertTrue(csv.contains("SENSOR_BRUXISM_DETECTED"), "CSV should contain bruxism event")
    }

    func testExportToFile() {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: "Test Device")

        let jsonURL = logger.exportToFile(format: .json)
        XCTAssertNotNil(jsonURL, "Should export to JSON file")

        if let url = jsonURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertTrue(url.pathExtension == "json")
            try? FileManager.default.removeItem(at: url)
        }

        let csvURL = logger.exportToFile(format: .csv)
        XCTAssertNotNil(csvURL, "Should export to CSV file")

        if let url = csvURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertTrue(url.pathExtension == "csv")
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - PilotEvent Model Tests

    func testPilotEventCreation() {
        let event = PilotEvent(
            eventType: .bleConnect,
            sessionId: "TEST-SESSION",
            deviceIdentifier: "TEST-DEVICE",
            userId: "USER-001",
            metadata: ["key": "value"],
            numericData: ["count": 42.0],
            severity: .info,
            source: "TestSource"
        )

        XCTAssertEqual(event.eventType, .bleConnect)
        XCTAssertEqual(event.category, .ble)
        XCTAssertEqual(event.sessionId, "TEST-SESSION")
        XCTAssertEqual(event.deviceIdentifier, "TEST-DEVICE")
        XCTAssertEqual(event.userId, "USER-001")
        XCTAssertEqual(event.metadata["key"], "value")
        XCTAssertEqual(event.numericData?["count"], 42.0)
        XCTAssertEqual(event.severity, .info)
        XCTAssertEqual(event.source, "TestSource")
    }

    func testPilotEventISOTimestamp() {
        let event = PilotEvent(
            eventType: .bleConnect,
            sessionId: "TEST",
            deviceIdentifier: "TEST"
        )

        XCTAssertFalse(event.isoTimestamp.isEmpty)
        XCTAssertTrue(event.isoTimestamp.contains("T"))  // ISO 8601 format includes T separator
    }

    func testPilotEventCSVRow() {
        let event = PilotEvent(
            eventType: .bleConnect,
            sessionId: "SESSION-001",
            deviceIdentifier: "DEVICE-001",
            metadata: ["key": "value"]
        )

        let csvRow = event.csvRow
        XCTAssertTrue(csvRow.contains("BLE_CONNECT"))
        XCTAssertTrue(csvRow.contains("SESSION-001"))
        XCTAssertTrue(csvRow.contains("DEVICE-001"))
        XCTAssertTrue(csvRow.contains("key=value"))
    }

    // MARK: - Event Type Category Tests

    func testBLEEventCategories() {
        XCTAssertEqual(PilotEventType.bleConnect.category, .ble)
        XCTAssertEqual(PilotEventType.bleDisconnect.category, .ble)
        XCTAssertEqual(PilotEventType.bleReconnectAttempt.category, .ble)
        XCTAssertEqual(PilotEventType.bleError.category, .ble)
    }

    func testSensorEventCategories() {
        XCTAssertEqual(PilotEventType.sensorDataReceived.category, .sensor)
        XCTAssertEqual(PilotEventType.sensorBruxismDetected.category, .sensor)
        XCTAssertEqual(PilotEventType.sensorSleepCycleStart.category, .sensor)
    }

    func testLifecycleEventCategories() {
        XCTAssertEqual(PilotEventType.appForeground.category, .lifecycle)
        XCTAssertEqual(PilotEventType.appBackground.category, .lifecycle)
        XCTAssertEqual(PilotEventType.appSuspend.category, .lifecycle)
    }

    func testUserInteractionEventCategories() {
        XCTAssertEqual(PilotEventType.userRecordingStart.category, .userInteraction)
        XCTAssertEqual(PilotEventType.userExportData.category, .userInteraction)
    }

    func testSystemEventCategories() {
        XCTAssertEqual(PilotEventType.systemLowMemory.category, .system)
        XCTAssertEqual(PilotEventType.systemLowBattery.category, .system)
    }
}
