//
//  CSVServiceProtocols.swift
//  OralableApp
//
//  Created by John A Cogan on 04/11/2025.
//

import Foundation
import OralableCore

// MARK: - CSV Export Protocol

/// Protocol for CSV export services
protocol CSVExporting {
    
    /// Export sensor readings to CSV format
    /// - Parameters:
    ///   - readings: Array of sensor readings to export
    ///   - logs: Array of log entries to include
    ///   - includeHeaders: Whether to include column headers
    /// - Returns: URL of the exported CSV file
    func exportReadings(
        _ readings: [SensorReading],
        logs: [LogEntry],
        includeHeaders: Bool
    ) async throws -> URL
    
    /// Export readings within date range
    /// - Parameters:
    ///   - startDate: Start date for export
    ///   - endDate: End date for export
    ///   - repository: Repository to fetch data from
    ///   - logs: Log entries to include
    /// - Returns: URL of the exported CSV file
    func exportReadings(
        from startDate: Date,
        to endDate: Date,
        repository: SensorRepository,
        logs: [LogEntry]
    ) async throws -> URL
}

// MARK: - CSV Import Protocol

/// Protocol for CSV import services
protocol CSVImporting {
    
    /// Import sensor readings from CSV file
    /// - Parameter url: URL of the CSV file to import
    /// - Returns: Imported readings and any import warnings
    func importReadings(from url: URL) async throws -> CSVImportResult
    
    /// Validate CSV file format without importing
    /// - Parameter url: URL of the CSV file to validate
    /// - Returns: Validation result with any format issues
    func validateCSV(at url: URL) async throws -> CSVValidationResult
}

// MARK: - CSV Import Result

/// Result of CSV import operation
struct CSVImportResult {
    
    /// Successfully imported readings
    let readings: [SensorReading]
    
    /// Import warnings (non-fatal issues)
    let warnings: [CSVImportWarning]
    
    /// Import statistics
    let statistics: CSVImportStatistics
    
    /// Whether import was successful (some warnings are acceptable)
    var isSuccessful: Bool {
        !readings.isEmpty
    }
    
    /// Summary text for UI display
    var summaryText: String {
        if readings.isEmpty {
            return "Import failed - no valid readings found"
        } else if warnings.isEmpty {
            return "Imported \(readings.count) readings successfully"
        } else {
            return "Imported \(readings.count) readings with \(warnings.count) warnings"
        }
    }
}

// MARK: - CSV Import Statistics

/// Statistics from CSV import operation
struct CSVImportStatistics {
    
    /// Total rows processed
    let totalRows: Int
    
    /// Successfully imported rows
    let importedRows: Int
    
    /// Skipped rows (headers, empty, etc.)
    let skippedRows: Int
    
    /// Failed rows (format errors)
    let failedRows: Int
    
    /// Duplicate readings detected
    let duplicateReadings: Int
    
    /// Date range of imported data
    let dateRange: DateInterval?
    
    /// Sensor types found in import
    let sensorTypes: Set<SensorType>
    
    /// Device IDs found in import
    let deviceIds: Set<String>
    
    var successRate: Double {
        guard totalRows > 0 else { return 0.0 }
        return Double(importedRows) / Double(totalRows)
    }
}

// MARK: - CSV Import Warning

/// Warning encountered during CSV import
struct CSVImportWarning {
    
    /// Row number where warning occurred
    let rowNumber: Int
    
    /// Type of warning
    let type: CSVImportWarningType
    
    /// Human-readable warning message
    let message: String
    
    /// Raw row data that caused the warning
    let rowData: String?
}

enum CSVImportWarningType: String, CaseIterable {
    case invalidSensorType = "invalid_sensor_type"
    case invalidValue = "invalid_value"
    case invalidTimestamp = "invalid_timestamp"
    case missingDeviceId = "missing_device_id"
    case invalidQuality = "invalid_quality"
    case duplicateReading = "duplicate_reading"
    case malformedRow = "malformed_row"
    case unknownColumn = "unknown_column"
    
    var displayName: String {
        switch self {
        case .invalidSensorType:
            return "Invalid Sensor Type"
        case .invalidValue:
            return "Invalid Value"
        case .invalidTimestamp:
            return "Invalid Timestamp"
        case .missingDeviceId:
            return "Missing Device ID"
        case .invalidQuality:
            return "Invalid Quality"
        case .duplicateReading:
            return "Duplicate Reading"
        case .malformedRow:
            return "Malformed Row"
        case .unknownColumn:
            return "Unknown Column"
        }
    }
}

// MARK: - CSV Validation Result

/// Result of CSV file validation
struct CSVValidationResult {
    
    /// Whether file is valid CSV format
    let isValidFormat: Bool
    
    /// Detected column headers
    let headers: [String]
    
    /// Expected vs found columns
    let columnMapping: [String: String?]
    
    /// Format issues found
    let issues: [CSVValidationIssue]
    
    /// Estimated number of data rows
    let estimatedRowCount: Int
    
    /// File size in bytes
    let fileSize: Int64
    
    /// Whether file appears importable
    var isImportable: Bool {
        isValidFormat && !headers.isEmpty && issues.filter { $0.severity == .error }.isEmpty
    }
}

// MARK: - CSV Validation Issue

/// Issue found during CSV validation
struct CSVValidationIssue {
    
    /// Severity of the issue
    let severity: CSVValidationSeverity
    
    /// Issue description
    let description: String
    
    /// Suggested resolution
    let suggestion: String?
}

enum CSVValidationSeverity {
    case error    // Prevents import
    case warning  // Import possible but may have issues
    case info     // Informational only
}

// MARK: - Log Entry Model
// Note: LogEntry and LogLevel are now defined in LogModels.swift
// This file uses those shared definitions to avoid ambiguity

// MARK: - Concrete CSV Service Implementation

/// Concrete implementation of CSV export/import services
class CSVService: CSVExporting, CSVImporting {
    
    // MARK: - Export Implementation
    
    func exportReadings(
        _ readings: [SensorReading],
        logs: [LogEntry],
        includeHeaders: Bool = true
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let url = try await self.performExport(readings: readings, logs: logs, includeHeaders: includeHeaders)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func exportReadings(
        from startDate: Date,
        to endDate: Date,
        repository: SensorRepository,
        logs: [LogEntry]
    ) async throws -> URL {
        let readings = try await repository.allReadings(from: startDate, to: endDate)
        let filteredLogs = logs.filter { log in
            log.timestamp >= startDate && log.timestamp <= endDate
        }
        
        return try await exportReadings(readings, logs: filteredLogs, includeHeaders: true)
    }
    
    // MARK: - Import Implementation
    
    func importReadings(from url: URL) async throws -> CSVImportResult {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let result = try await self.performImport(from: url)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func validateCSV(at url: URL) async throws -> CSVValidationResult {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let result = try await self.performValidation(at: url)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Private Implementation
    
    private func performExport(readings: [SensorReading], logs: [LogEntry], includeHeaders: Bool) async throws -> URL {
        let sortedReadings = readings.sorted { $0.timestamp < $1.timestamp }
        let sortedLogs = logs.sorted { $0.timestamp < $1.timestamp }
        
        var csvContent = ""
        
        // Add headers
        if includeHeaders {
            csvContent += "Timestamp,Sensor Type,Value,Unit,Device ID,Quality,Message\n"
        }
        
        // Create merged timeline of readings and logs
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        var readingIndex = 0
        var logIndex = 0
        
        while readingIndex < sortedReadings.count || logIndex < sortedLogs.count {
            let nextReading = readingIndex < sortedReadings.count ? sortedReadings[readingIndex] : nil
            let nextLog = logIndex < sortedLogs.count ? sortedLogs[logIndex] : nil
            
            let shouldProcessReading: Bool
            if let reading = nextReading, let log = nextLog {
                shouldProcessReading = reading.timestamp <= log.timestamp
            } else if nextReading != nil {
                shouldProcessReading = true
            } else {
                shouldProcessReading = false
            }
            
            if shouldProcessReading, let reading = nextReading {
                // Export reading
                let timestamp = dateFormatter.string(from: reading.timestamp)
                let sensorType = reading.sensorType.rawValue
                let value = String(reading.value)
                let unit = reading.sensorType.unit
                let deviceId = reading.deviceId ?? ""
                let quality = reading.quality.map { String($0) } ?? ""
                
                csvContent += "\"\(timestamp)\",\"\(sensorType)\",\"\(value)\",\"\(unit)\",\"\(deviceId)\",\"\(quality)\",\"\"\n"
                readingIndex += 1
            } else if let log = nextLog {
                // Export log entry
                let timestamp = dateFormatter.string(from: log.timestamp)
                let message = log.message.replacingOccurrences(of: "\"", with: "\"\"")
                
                csvContent += "\"\(timestamp)\",\"log\",\"\(log.level.rawValue)\",\"\",\"\",\"\",\"\(message)\"\n"
                logIndex += 1
            }
        }
        
        // Write to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "oralable_export_\(DateFormatter().string(from: Date())).csv"
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "-")
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    }
    
    private func performImport(from url: URL) async throws -> CSVImportResult {
        let csvContent = try String(contentsOf: url)
        let lines = csvContent.components(separatedBy: .newlines)
        
        var readings: [SensorReading] = []
        var warnings: [CSVImportWarning] = []
        var totalRows = 0
        var skippedRows = 0
        var failedRows = 0
        var duplicateReadings = 0
        var sensorTypes: Set<SensorType> = []
        var deviceIds: Set<String> = []
        var timestamps: [Date] = []
        
        // Parse header row
        guard !lines.isEmpty else {
            throw CSVImportError.emptyFile
        }
        
        let headerLine = lines[0]
        let headers = parseCSVLine(headerLine)
        
        // Map columns
        guard let timestampCol = headers.firstIndex(of: "Timestamp"),
              let sensorTypeCol = headers.firstIndex(of: "Sensor Type"),
              let valueCol = headers.firstIndex(of: "Value") else {
            throw CSVImportError.missingRequiredColumns
        }
        
        let deviceIdCol = headers.firstIndex(of: "Device ID")
        let qualityCol = headers.firstIndex(of: "Quality")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Process data rows
        for (rowIndex, line) in lines.enumerated() {
            guard rowIndex > 0 && !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                if rowIndex > 0 {
                    skippedRows += 1
                }
                continue
            }
            
            totalRows += 1
            let rowNumber = rowIndex + 1
            
            let columns = parseCSVLine(line)
            
            // Check minimum columns
            guard columns.count > max(timestampCol, sensorTypeCol, valueCol) else {
                warnings.append(CSVImportWarning(
                    rowNumber: rowNumber,
                    type: .malformedRow,
                    message: "Row has insufficient columns",
                    rowData: line
                ))
                failedRows += 1
                continue
            }
            
            // Parse timestamp
            guard let timestamp = dateFormatter.date(from: columns[timestampCol]) else {
                warnings.append(CSVImportWarning(
                    rowNumber: rowNumber,
                    type: .invalidTimestamp,
                    message: "Could not parse timestamp: \(columns[timestampCol])",
                    rowData: line
                ))
                failedRows += 1
                continue
            }
            
            // Parse sensor type
            guard let sensorType = SensorType(rawValue: columns[sensorTypeCol]) else {
                // Skip log entries
                if columns[sensorTypeCol] == "log" {
                    skippedRows += 1
                    continue
                }
                
                warnings.append(CSVImportWarning(
                    rowNumber: rowNumber,
                    type: .invalidSensorType,
                    message: "Unknown sensor type: \(columns[sensorTypeCol])",
                    rowData: line
                ))
                failedRows += 1
                continue
            }
            
            // Parse value
            guard let value = Double(columns[valueCol]) else {
                warnings.append(CSVImportWarning(
                    rowNumber: rowNumber,
                    type: .invalidValue,
                    message: "Could not parse value: \(columns[valueCol])",
                    rowData: line
                ))
                failedRows += 1
                continue
            }
            
            // Parse optional fields
            let deviceId = deviceIdCol.map { columns.count > $0 ? columns[$0] : nil } ?? nil
            let quality = qualityCol.flatMap { columns.count > $0 ? Double(columns[$0]) : nil }
            
            // Create reading
            let reading = SensorReading(
                sensorType: sensorType,
                value: value,
                timestamp: timestamp,
                deviceId: deviceId?.isEmpty == true ? nil : deviceId,
                quality: quality
            )
            
            readings.append(reading)
            sensorTypes.insert(sensorType)
            if let deviceId = deviceId, !deviceId.isEmpty {
                deviceIds.insert(deviceId)
            }
            timestamps.append(timestamp)
        }
        
        // Calculate date range
        let dateRange: DateInterval? = {
            guard !timestamps.isEmpty else { return nil }
            let earliest = timestamps.min()!
            let latest = timestamps.max()!
            return DateInterval(start: earliest, end: latest)
        }()
        
        let statistics = CSVImportStatistics(
            totalRows: totalRows + skippedRows + 1, // +1 for header
            importedRows: readings.count,
            skippedRows: skippedRows + 1, // +1 for header
            failedRows: failedRows,
            duplicateReadings: duplicateReadings,
            dateRange: dateRange,
            sensorTypes: sensorTypes,
            deviceIds: deviceIds
        )
        
        return CSVImportResult(
            readings: readings,
            warnings: warnings,
            statistics: statistics
        )
    }
    
    private func performValidation(at url: URL) async throws -> CSVValidationResult {
        let csvContent = try String(contentsOf: url)
        let lines = csvContent.components(separatedBy: .newlines)
        
        guard !lines.isEmpty else {
            return CSVValidationResult(
                isValidFormat: false,
                headers: [],
                columnMapping: [:],
                issues: [CSVValidationIssue(severity: .error, description: "File is empty", suggestion: nil)],
                estimatedRowCount: 0,
                fileSize: 0
            )
        }
        
        let headers = parseCSVLine(lines[0])
        let estimatedRowCount = max(0, lines.count - 1)
        let fileSize = Int64(csvContent.count)
        
        var issues: [CSVValidationIssue] = []
        
        // Check for required columns
        let requiredColumns = ["Timestamp", "Sensor Type", "Value"]
        var columnMapping: [String: String?] = [:]
        
        for required in requiredColumns {
            if headers.contains(required) {
                columnMapping[required] = required
            } else {
                columnMapping[required] = nil
                issues.append(CSVValidationIssue(
                    severity: .error,
                    description: "Missing required column: \(required)",
                    suggestion: "Ensure the CSV file contains a '\(required)' column"
                ))
            }
        }
        
        // Check for optional columns
        let optionalColumns = ["Device ID", "Quality", "Unit", "Message"]
        for optional in optionalColumns {
            if headers.contains(optional) {
                columnMapping[optional] = optional
            } else {
                columnMapping[optional] = nil
            }
        }
        
        // Validate file size
        if fileSize > 50_000_000 { // 50MB
            issues.append(CSVValidationIssue(
                severity: .warning,
                description: "Large file size (\(fileSize / 1_000_000)MB)",
                suggestion: "Large files may take longer to import"
            ))
        }
        
        return CSVValidationResult(
            isValidFormat: !headers.isEmpty,
            headers: headers,
            columnMapping: columnMapping,
            issues: issues,
            estimatedRowCount: estimatedRowCount,
            fileSize: fileSize
        )
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        // Simple CSV parser that handles quoted fields
        var columns: [String] = []
        var currentColumn = ""
        var insideQuotes = false
        var i = line.startIndex
        
        while i < line.endIndex {
            let char = line[i]
            
            if char == "\"" {
                if insideQuotes {
                    // Check for escaped quote
                    let nextIndex = line.index(after: i)
                    if nextIndex < line.endIndex && line[nextIndex] == "\"" {
                        currentColumn.append("\"")
                        i = nextIndex
                    } else {
                        insideQuotes = false
                    }
                } else {
                    insideQuotes = true
                }
            } else if char == "," && !insideQuotes {
                columns.append(currentColumn)
                currentColumn = ""
            } else {
                currentColumn.append(char)
            }
            
            i = line.index(after: i)
        }
        
        columns.append(currentColumn)
        return columns
    }
}

// MARK: - CSV Import Error

enum CSVImportError: LocalizedError {
    case emptyFile
    case missingRequiredColumns
    case invalidFormat
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The CSV file is empty"
        case .missingRequiredColumns:
            return "The CSV file is missing required columns (Timestamp, Sensor Type, Value)"
        case .invalidFormat:
            return "The file is not in valid CSV format"
        case .fileNotFound:
            return "The specified file could not be found"
        }
    }
}