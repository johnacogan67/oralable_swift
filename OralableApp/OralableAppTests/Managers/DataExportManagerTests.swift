//
//  DataExportManagerTests.swift
//  OralableAppTests
//
//  Purpose: Unit tests for CSV data export functionality
//

import XCTest
@testable import MAMDiagnostics

final class DataExportManagerTests: XCTestCase {

    var exportManager: CSVExportManager!
    var fileManager: FileManager!

    override func setUp() {
        super.setUp()
        exportManager = CSVExportManager()
        fileManager = FileManager.default
    }

    override func tearDown() {
        // Clean up test exports
        exportManager.cleanupOldExports()
        exportManager = nil
        fileManager = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createMockSensorData(count: Int = 5) -> [SensorData] {
        var sensorData: [SensorData] = []
        let now = Date()

        for i in 0..<count {
            let timestamp = now.addingTimeInterval(TimeInterval(-i * 5))

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
                deviceType: .oralable
            )

            sensorData.append(data)
        }

        return sensorData
    }

    // MARK: - Export Success Tests

    func testExportDataReturnsURL() {
        // Given
        let sensorData = createMockSensorData(count: 10)
        let logs = ["Test log 1", "Test log 2"]

        // When
        let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs)

        // Then
        XCTAssertNotNil(exportURL, "Export should return a valid URL")
    }

    func testExportCreatesFileOnDisk() {
        // Given
        let sensorData = createMockSensorData(count: 5)
        let logs: [String] = []

        // When
        guard let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs) else {
            XCTFail("Export should return a URL")
            return
        }

        // Then
        XCTAssertTrue(fileManager.fileExists(atPath: exportURL.path), "Export file should exist on disk")
    }

    func testExportFileNameContainsTimestamp() {
        // Given
        let sensorData = createMockSensorData(count: 3)
        let logs: [String] = []

        // When
        guard let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs) else {
            XCTFail("Export should return a URL")
            return
        }

        // Then
        let filename = exportURL.lastPathComponent
        XCTAssertTrue(filename.hasPrefix("mam_data_"), "Filename should start with mam_data_")
        XCTAssertTrue(filename.hasSuffix(".csv"), "Filename should have .csv extension")
    }

    func testExportWithEmptySensorDataSucceeds() {
        // Given
        let sensorData: [SensorData] = []
        let logs = ["Log entry without sensor data"]

        // When
        let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs)

        // Then
        XCTAssertNotNil(exportURL, "Export should succeed even with empty sensor data")
    }

    func testExportWithEmptyLogsSucceeds() {
        // Given
        let sensorData = createMockSensorData(count: 5)
        let logs: [String] = []

        // When
        let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs)

        // Then
        XCTAssertNotNil(exportURL, "Export should succeed even with empty logs")
    }

    // MARK: - CSV Schema Tests

    func testExportContainsCSVHeader() {
        // Given
        let sensorData = createMockSensorData(count: 1)
        let logs: [String] = []

        // When
        guard let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs) else {
            XCTFail("Export should return a URL")
            return
        }

        // Then
        do {
            let content = try String(contentsOf: exportURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")

            XCTAssertGreaterThan(lines.count, 0, "CSV should have at least header line")

            let header = lines[0]
            XCTAssertTrue(header.contains("Timestamp"), "Header should contain Timestamp")
            XCTAssertTrue(header.contains("PPG_IR"), "Header should contain PPG_IR")
            XCTAssertTrue(header.contains("PPG_Red"), "Header should contain PPG_Red")
            XCTAssertTrue(header.contains("PPG_Green"), "Header should contain PPG_Green")
        } catch {
            XCTFail("Failed to read exported file: \(error)")
        }
    }

    func testExportContainsCorrectNumberOfRows() {
        // Given
        let dataCount = 10
        let sensorData = createMockSensorData(count: dataCount)
        let logs: [String] = []

        // When
        guard let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs) else {
            XCTFail("Export should return a URL")
            return
        }

        // Then
        do {
            let content = try String(contentsOf: exportURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

            // Header + data rows
            XCTAssertEqual(lines.count, dataCount + 1, "CSV should have header plus \(dataCount) data rows")
        } catch {
            XCTFail("Failed to read exported file: \(error)")
        }
    }

    func testExportDataRowsHaveCorrectColumnCount() {
        // Given
        let sensorData = createMockSensorData(count: 3)
        let logs: [String] = []

        // When
        guard let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs) else {
            XCTFail("Export should return a URL")
            return
        }

        // Then
        do {
            let content = try String(contentsOf: exportURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

            let headerColumnCount = lines[0].components(separatedBy: ",").count

            // Check each data row has same column count as header
            for i in 1..<lines.count {
                let rowColumnCount = lines[i].components(separatedBy: ",").count
                XCTAssertEqual(rowColumnCount, headerColumnCount, "Row \(i) should have same column count as header")
            }
        } catch {
            XCTFail("Failed to read exported file: \(error)")
        }
    }

    func testExportTimestampFormat() {
        // Given
        let sensorData = createMockSensorData(count: 1)
        let logs: [String] = []

        // When
        guard let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs) else {
            XCTFail("Export should return a URL")
            return
        }

        // Then
        do {
            let content = try String(contentsOf: exportURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

            guard lines.count > 1 else {
                XCTFail("Should have at least one data row")
                return
            }

            let dataRow = lines[1]
            let columns = dataRow.components(separatedBy: ",")
            let timestamp = columns[0]

            // Timestamp format should be: yyyy-MM-dd HH:mm:ss.SSS
            XCTAssertTrue(timestamp.contains("-"), "Timestamp should contain date separators")
            XCTAssertTrue(timestamp.contains(":"), "Timestamp should contain time separators")
        } catch {
            XCTFail("Failed to read exported file: \(error)")
        }
    }

    // MARK: - Export Summary Tests

    func testGetExportSummaryReturnsValidData() {
        // Given
        let sensorData = createMockSensorData(count: 100)
        let logs = ["Log 1", "Log 2", "Log 3"]

        // When
        let summary = exportManager.getExportSummary(sensorData: sensorData, logs: logs)

        // Then
        XCTAssertEqual(summary.sensorDataCount, 100, "Sensor data count should match")
        XCTAssertEqual(summary.logCount, 3, "Log count should match")
        XCTAssertFalse(summary.dateRange.isEmpty, "Date range should not be empty")
        XCTAssertFalse(summary.estimatedSize.isEmpty, "Estimated size should not be empty")
    }

    func testGetExportSummaryWithEmptyData() {
        // Given
        let sensorData: [SensorData] = []
        let logs: [String] = []

        // When
        let summary = exportManager.getExportSummary(sensorData: sensorData, logs: logs)

        // Then
        XCTAssertEqual(summary.sensorDataCount, 0, "Sensor data count should be 0")
        XCTAssertEqual(summary.logCount, 0, "Log count should be 0")
        XCTAssertEqual(summary.dateRange, "No data", "Date range should indicate no data")
    }

    func testEstimateExportSize() {
        // Given
        let sensorDataCount = 1000
        let logCount = 50

        // When
        let sizeString = exportManager.estimateExportSize(sensorDataCount: sensorDataCount, logCount: logCount)

        // Then
        XCTAssertFalse(sizeString.isEmpty, "Size estimate should not be empty")
        // Should contain KB or MB or similar unit
        XCTAssertTrue(sizeString.contains("KB") || sizeString.contains("MB") || sizeString.contains("bytes"),
                      "Size string should contain a unit")
    }

    // MARK: - CSV Escaping Tests

    func testExportEscapesCommasInLogs() {
        // Given
        let sensorData = createMockSensorData(count: 1)
        let logs = ["Log with, comma"]

        // When
        guard let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs) else {
            XCTFail("Export should return a URL")
            return
        }

        // Then
        do {
            let content = try String(contentsOf: exportURL, encoding: .utf8)
            // Logs with commas should be properly escaped (wrapped in quotes)
            XCTAssertTrue(content.contains("\"Log with, comma\""), "Commas should be escaped with quotes")
        } catch {
            XCTFail("Failed to read exported file: \(error)")
        }
    }

    func testExportEscapesQuotesInLogs() {
        // Given
        let sensorData = createMockSensorData(count: 1)
        let logs = ["Log with \"quotes\""]

        // When
        guard let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs) else {
            XCTFail("Export should return a URL")
            return
        }

        // Then
        do {
            let content = try String(contentsOf: exportURL, encoding: .utf8)
            // Quotes should be escaped (doubled)
            XCTAssertTrue(content.contains("\"\""), "Quotes should be escaped by doubling")
        } catch {
            XCTFail("Failed to read exported file: \(error)")
        }
    }

    // MARK: - Cleanup Tests

    func testCleanupOldExportsDoesNotCrash() {
        // Given - some old exports may exist
        _ = exportManager.exportData(sensorData: createMockSensorData(count: 1), logs: [])

        // When - should not throw
        exportManager.cleanupOldExports()

        // Then - no crash means success
        XCTAssertTrue(true, "Cleanup should complete without crashing")
    }

    // MARK: - Large Data Export Tests

    func testExportLargeDataSet() {
        // Given - large dataset
        let sensorData = createMockSensorData(count: 1000)
        let logs = (0..<100).map { "Log entry \($0)" }

        // When
        let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs)

        // Then
        XCTAssertNotNil(exportURL, "Should handle large datasets")

        if let url = exportURL {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int ?? 0
                XCTAssertGreaterThan(fileSize, 0, "Exported file should have content")
            } catch {
                XCTFail("Failed to get file attributes: \(error)")
            }
        }
    }

    // MARK: - Export Directory Tests

    func testExportCreatesDirectoryIfNeeded() {
        // Given
        let sensorData = createMockSensorData(count: 1)
        let logs: [String] = []

        // When
        guard let exportURL = exportManager.exportData(sensorData: sensorData, logs: logs) else {
            XCTFail("Export should return a URL")
            return
        }

        // Then
        let exportDirectory = exportURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: exportDirectory.path, isDirectory: &isDirectory)

        XCTAssertTrue(exists, "Export directory should exist")
        XCTAssertTrue(isDirectory.boolValue, "Export path should be a directory")
    }

    // MARK: - Sequential Export Tests

    func testSequentialExportsCreateDifferentFiles() {
        // Given
        let sensorData1 = createMockSensorData(count: 10)
        let sensorData2 = createMockSensorData(count: 10)

        // When - export sequentially
        let url1 = exportManager.exportData(sensorData: sensorData1, logs: ["Export 1"])

        // Small delay to ensure different timestamp
        Thread.sleep(forTimeInterval: 1.1)

        let url2 = exportManager.exportData(sensorData: sensorData2, logs: ["Export 2"])

        // Then - both should succeed with different files
        XCTAssertNotNil(url1, "First export should succeed")
        XCTAssertNotNil(url2, "Second export should succeed")

        if let u1 = url1, let u2 = url2 {
            XCTAssertNotEqual(u1.path, u2.path, "Sequential exports should create different files")
        }
    }
}
