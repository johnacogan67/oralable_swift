//
//  PilotDataManagerTests.swift
//  OralableAppTests
//
//  Created: December 15, 2025
//  Purpose: Unit tests for PilotDataManager
//  Tests aggregation, batch export, and error handling
//

import XCTest
@testable import MAMDiagnostics

@MainActor
final class PilotDataManagerTests: XCTestCase {

    // MARK: - Properties

    var dataManager: PilotDataManager!
    var logger: PilotLogger!
    var anonymizer: Anonymizer!
    var settings: PilotStudySettings!

    // MARK: - Test Lifecycle

    override func setUp() async throws {
        try await super.setUp()

        logger = PilotLogger(maxEvents: 100, deviceIdentifier: "TEST-DEVICE")
        anonymizer = Anonymizer(config: .default)
        settings = PilotStudySettings.shared

        // Grant consent for tests
        settings.grantConsent()

        dataManager = PilotDataManager(
            logger: logger,
            anonymizer: anonymizer,
            settings: settings
        )

        // Clear any previous data
        logger.clearEvents()
        dataManager.clearAggregatedData()
        anonymizer.clearMappings()
    }

    override func tearDown() async throws {
        dataManager.clearAggregatedData()
        logger.clearEvents()
        settings.revokeConsent()

        dataManager = nil
        logger = nil
        anonymizer = nil
        settings = nil

        try await super.tearDown()
    }

    // MARK: - Consent Tests

    func testCanCollectDataWithConsent() {
        settings.grantConsent()
        XCTAssertTrue(dataManager.canCollectData)
    }

    func testCannotCollectDataWithoutConsent() {
        settings.revokeConsent()
        XCTAssertFalse(dataManager.canCollectData)
    }

    func testVerifyConsentThrowsWithoutConsent() {
        settings.revokeConsent()

        XCTAssertThrowsError(try dataManager.verifyConsent()) { error in
            XCTAssertEqual(error as? PilotDataError, .consentNotGranted)
        }
    }

    func testVerifyConsentSucceedsWithConsent() {
        settings.grantConsent()

        XCTAssertNoThrow(try dataManager.verifyConsent())
    }

    // MARK: - Aggregation Tests

    func testAggregateEventsFromLogger() throws {
        // Add events to logger
        logger.logBLEConnect(peripheralId: "P1", peripheralName: "Test Device")
        logger.logBruxismDetected(intensity: 0.8, duration: 5.0, confidence: 0.9)
        logger.logAppForeground()

        // Wait for async logging
        let expectation = XCTestExpectation(description: "Events logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Aggregate events
        try dataManager.aggregateEvents()

        XCTAssertEqual(dataManager.anonymizedEvents.count, 3)
    }

    func testAggregateEventsAnonymizesData() throws {
        logger.logBLEConnect(peripheralId: "SENSITIVE-DEVICE-ID", peripheralName: nil)

        let expectation = XCTestExpectation(description: "Events logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        try dataManager.aggregateEvents()

        let event = dataManager.anonymizedEvents.first
        XCTAssertNotNil(event)
        XCTAssertTrue(event!.participantId.hasPrefix("ORALABLE-"))
        XCTAssertFalse(event!.participantId.contains("SENSITIVE"))
    }

    func testAggregateEventsFromDateRange() throws {
        let now = Date()
        logger.logBLEConnect(peripheralId: "P1", peripheralName: nil)

        let expectation = XCTestExpectation(description: "Events logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Aggregate events from last hour
        let oneHourAgo = now.addingTimeInterval(-3600)
        try dataManager.aggregateEvents(from: oneHourAgo, to: Date())

        XCTAssertGreaterThan(dataManager.anonymizedEvents.count, 0)
    }

    func testAggregateEventsFromDateRangeThrowsForInvalidRange() {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)

        XCTAssertThrowsError(try dataManager.aggregateEvents(from: now, to: oneHourAgo)) { error in
            XCTAssertEqual(error as? PilotDataError, .invalidDateRange)
        }
    }

    func testAggregateEventsRequiresConsent() {
        settings.revokeConsent()

        XCTAssertThrowsError(try dataManager.aggregateEvents()) { error in
            XCTAssertEqual(error as? PilotDataError, .consentNotGranted)
        }
    }

    // MARK: - Sensor Data Aggregation Tests

    func testAggregateSensorData() throws {
        let sensorData = [
            createTestSensorData(),
            createTestSensorData(),
            createTestSensorData()
        ]

        try dataManager.aggregateSensorData(sensorData, deviceId: "DEVICE-001", userId: "USER-001")

        XCTAssertEqual(dataManager.anonymizedSensorData.count, 3)
    }

    func testAggregateSensorDataAnonymizesParticipantId() throws {
        let sensorData = [createTestSensorData()]

        try dataManager.aggregateSensorData(sensorData, deviceId: "SENSITIVE-DEVICE", userId: "SENSITIVE-USER")

        let data = dataManager.anonymizedSensorData.first
        XCTAssertNotNil(data)
        XCTAssertTrue(data!.participantId.hasPrefix("ORALABLE-"))
        XCTAssertFalse(data!.participantId.contains("SENSITIVE"))
    }

    // MARK: - Batch Export Tests

    func testExportBatchJSON() async throws {
        // Add some events
        logger.logBLEConnect(peripheralId: "P1", peripheralName: "Test")
        logger.logAppForeground()

        let expectation = XCTestExpectation(description: "Events logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        try dataManager.aggregateEvents()

        let result = try await dataManager.exportBatch(format: .json)

        XCTAssertTrue(result.success)
        XCTAssertGreaterThan(result.eventCount, 0)
        XCTAssertFalse(result.fileURLs.isEmpty)
        XCTAssertEqual(result.format, "JSON")

        // Cleanup exported files
        for path in result.fileURLs {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func testExportBatchCSV() async throws {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: "Test")

        let expectation = XCTestExpectation(description: "Events logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        try dataManager.aggregateEvents()

        let result = try await dataManager.exportBatch(format: .csv)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.format, "CSV")

        // Cleanup
        for path in result.fileURLs {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func testExportBatchClearsData() async throws {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: nil)

        let expectation = XCTestExpectation(description: "Events logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        try dataManager.aggregateEvents()
        XCTAssertGreaterThan(dataManager.anonymizedEvents.count, 0)

        let result = try await dataManager.exportBatch()

        // Data should be cleared after successful export
        XCTAssertTrue(result.success)
        XCTAssertEqual(dataManager.anonymizedEvents.count, 0)

        // Cleanup
        for path in result.fileURLs {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func testExportBatchThrowsWhenNoData() async {
        // Clear any data
        dataManager.clearAggregatedData()

        do {
            _ = try await dataManager.exportBatch()
            XCTFail("Should throw error when no data to export")
        } catch {
            XCTAssertEqual(error as? PilotDataError, .noDataToExport)
        }
    }

    func testExportBatchRequiresConsent() async {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: nil)

        let expectation = XCTestExpectation(description: "Events logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        settings.revokeConsent()

        do {
            _ = try await dataManager.exportBatch()
            XCTFail("Should throw error when no consent")
        } catch {
            XCTAssertEqual(error as? PilotDataError, .consentNotGranted)
        }
    }

    func testExportBatchUpdatesLastExportDate() async throws {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: nil)

        let expectation = XCTestExpectation(description: "Events logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        try dataManager.aggregateEvents()

        let beforeExport = settings.lastExportDate
        let result = try await dataManager.exportBatch()

        XCTAssertTrue(result.success)
        XCTAssertNotNil(settings.lastExportDate)
        if let before = beforeExport {
            XCTAssertGreaterThan(settings.lastExportDate!, before)
        }

        // Cleanup
        for path in result.fileURLs {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - Statistics Tests

    func testAggregationStatistics() throws {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: nil)
        logger.logBLEDisconnect(peripheralId: "P1", reason: nil)
        logger.logBruxismDetected(intensity: 0.8, duration: 5.0, confidence: 0.9)
        logger.logAppForeground()
        logger.logBLEError(peripheralId: "P1", errorCode: 1, errorMessage: "Error")

        let expectation = XCTestExpectation(description: "Events logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        try dataManager.aggregateEvents()

        let stats = dataManager.aggregationStatistics

        XCTAssertEqual(stats.totalEvents, 5)

        // Check category breakdown
        XCTAssertEqual(stats.eventsByCategory[.ble], 3)  // connect, disconnect, error
        XCTAssertEqual(stats.eventsByCategory[.sensor], 1)  // bruxism
        XCTAssertEqual(stats.eventsByCategory[.lifecycle], 1)  // foreground

        // Check date range
        XCTAssertNotNil(stats.oldestEvent)
        XCTAssertNotNil(stats.newestEvent)
    }

    func testStatisticsTimeRange() throws {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: nil)

        let expectation = XCTestExpectation(description: "Events logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        try dataManager.aggregateEvents()

        let stats = dataManager.aggregationStatistics

        XCTAssertFalse(stats.timeRange.isEmpty)
        XCTAssertNotEqual(stats.timeRange, "No events")
    }

    // MARK: - Data Management Tests

    func testClearAggregatedData() throws {
        logger.logBLEConnect(peripheralId: "P1", peripheralName: nil)

        let expectation = XCTestExpectation(description: "Events logged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        try dataManager.aggregateEvents()
        XCTAssertGreaterThan(dataManager.anonymizedEvents.count, 0)

        dataManager.clearAggregatedData()

        XCTAssertEqual(dataManager.anonymizedEvents.count, 0)
        XCTAssertEqual(dataManager.anonymizedSensorData.count, 0)
    }

    // MARK: - Export Result Tests

    func testBatchExportResultSummary() {
        let result = BatchExportResult(
            exportId: "EXPORT-001",
            timestamp: Date(),
            eventCount: 100,
            sensorDataCount: 500,
            fileURLs: ["/path/to/file.json"],
            format: "JSON",
            success: true,
            errorMessage: nil
        )

        let summary = result.summary

        XCTAssertTrue(summary.contains("EXPORT-001"))
        XCTAssertTrue(summary.contains("100"))
        XCTAssertTrue(summary.contains("500"))
        XCTAssertTrue(summary.contains("JSON"))
        XCTAssertTrue(summary.contains("true"))
    }

    // MARK: - Error Handling Tests

    func testPilotDataErrorDescriptions() {
        let errors: [PilotDataError] = [
            .noDataToExport,
            .writePermissionDenied,
            .fileWriteFailed(underlying: NSError(domain: "test", code: 1)),
            .encodingFailed(underlying: NSError(domain: "test", code: 2)),
            .aggregationFailed(reason: "Test reason"),
            .consentNotGranted,
            .exportDirectoryUnavailable,
            .batchSizeTooLarge(requested: 20000, maximum: 10000),
            .invalidDateRange,
            .anonymizationFailed
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testBatchSizeTooLargeErrorMessage() {
        let error = PilotDataError.batchSizeTooLarge(requested: 20000, maximum: 10000)

        XCTAssertTrue(error.errorDescription!.contains("20000"))
        XCTAssertTrue(error.errorDescription!.contains("10000"))
    }

    // MARK: - Settings Tests

    func testPilotStudySettingsGrantConsent() {
        let testSettings = PilotStudySettings()
        testSettings.revokeConsent()

        XCTAssertFalse(testSettings.consentGranted)
        XCTAssertNil(testSettings.participantTrialId)

        testSettings.grantConsent()

        XCTAssertTrue(testSettings.consentGranted)
        XCTAssertNotNil(testSettings.consentDate)
        XCTAssertNotNil(testSettings.participantTrialId)
        XCTAssertTrue(testSettings.participantTrialId!.hasPrefix("ORALABLE-"))

        testSettings.revokeConsent()
    }

    func testPilotStudySettingsRevokeConsent() {
        let testSettings = PilotStudySettings()
        testSettings.grantConsent()

        XCTAssertTrue(testSettings.consentGranted)

        testSettings.revokeConsent()

        XCTAssertFalse(testSettings.consentGranted)
        XCTAssertNil(testSettings.consentDate)
        XCTAssertNil(testSettings.participantTrialId)
    }

    func testPilotStudySettingsDefaults() {
        let testSettings = PilotStudySettings()

        // Default export batch size
        XCTAssertEqual(testSettings.exportBatchSize, 1000)
    }

    // MARK: - Helper Methods

    private func createTestSensorData() -> SensorData {
        return SensorData(
            ppg: PPGData(red: 45000, ir: 50000, green: 40000, timestamp: Date()),
            accelerometer: AccelerometerData(x: 100, y: 200, z: 980, timestamp: Date()),
            temperature: TemperatureData(celsius: 36.5, timestamp: Date()),
            battery: BatteryData(percentage: 85, timestamp: Date())
        )
    }
}

// MARK: - AggregationStatistics Tests

extension PilotDataManagerTests {

    func testEmptyStatistics() {
        let stats = dataManager.aggregationStatistics

        XCTAssertEqual(stats.totalEvents, 0)
        XCTAssertEqual(stats.totalSensorDataPoints, 0)
        XCTAssertNil(stats.oldestEvent)
        XCTAssertNil(stats.newestEvent)
        XCTAssertEqual(stats.timeRange, "No events")
    }
}
