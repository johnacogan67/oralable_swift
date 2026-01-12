//
//  CSVParser.swift
//  OralableForProfessionals
//
//  Parses CSV files exported from consumer app.
//
//  Purpose:
//  Import patient data from CSV files for analysis.
//
//  Uses: OralableCore.CSVParser for core parsing
//
//  Supported Formats:
//  - Standard Oralable CSV export
//  - Event-based CSV export
//
//  Output:
//  - Array of HistoricalDataPoint for charting
//  - Session metadata (date, duration, record count)
//
//  Created: December 10, 2025
//  Updated: December 31, 2025 - Now uses OralableCore.CSVParser
//

import Foundation
import OralableCore

// MARK: - Imported Sensor Data Model

/// Represents a single row of imported sensor data from CSV
/// This is a view-friendly wrapper around OralableCore.SensorData
struct ImportedSensorData: Identifiable {
    let id = UUID()
    let timestamp: Date
    let deviceType: String
    let emg: Double?
    let ppgIR: Double?
    let ppgRed: Double?
    let ppgGreen: Double?
    let accelX: Double?
    let accelY: Double?
    let accelZ: Double?
    let temperature: Double?
    let battery: Double?
    let heartRate: Double?

    /// Initialize from OralableCore.SensorData
    init(from sensorData: SensorData) {
        self.timestamp = sensorData.timestamp
        self.deviceType = "Oralable"
        self.emg = nil  // EMG not currently supported in SensorData
        self.ppgIR = Double(sensorData.ppg.ir)
        self.ppgRed = Double(sensorData.ppg.red)
        self.ppgGreen = Double(sensorData.ppg.green)
        self.accelX = Double(sensorData.accelerometer.x)
        self.accelY = Double(sensorData.accelerometer.y)
        self.accelZ = Double(sensorData.accelerometer.z)
        self.temperature = sensorData.temperature.celsius
        self.battery = Double(sensorData.battery.percentage)
        self.heartRate = sensorData.heartRate?.bpm
    }

    /// Initialize with explicit values (for legacy compatibility)
    init(
        timestamp: Date,
        deviceType: String,
        emg: Double?,
        ppgIR: Double?,
        ppgRed: Double?,
        ppgGreen: Double?,
        accelX: Double?,
        accelY: Double?,
        accelZ: Double?,
        temperature: Double?,
        battery: Double?,
        heartRate: Double?
    ) {
        self.timestamp = timestamp
        self.deviceType = deviceType
        self.emg = emg
        self.ppgIR = ppgIR
        self.ppgRed = ppgRed
        self.ppgGreen = ppgGreen
        self.accelX = accelX
        self.accelY = accelY
        self.accelZ = accelZ
        self.temperature = temperature
        self.battery = battery
        self.heartRate = heartRate
    }
}

// MARK: - CSV Parser Wrapper

/// Wrapper around OralableCore.CSVParser for Professional app use
/// Converts OralableCore types to view-friendly ImportedSensorData
struct CSVParser {

    /// Parse CSV content into ImportedSensorData array
    /// Uses OralableCore.CSVParser with lenient configuration
    /// - Parameter content: Raw CSV string content
    /// - Returns: Array of parsed sensor data points
    static func parse(_ content: String) -> [ImportedSensorData] {
        // Use OralableCore's CSVParser with lenient configuration
        let coreParser = OralableCore.CSVParser(configuration: .lenient)

        do {
            let result = try coreParser.parse(content)

            Logger.shared.info("[CSVParser] Parsed \(result.statistics.importedRows) of \(result.statistics.totalRows) rows using OralableCore")

            if !result.warnings.isEmpty {
                Logger.shared.info("[CSVParser] Import had \(result.warnings.count) warnings")
                for warning in result.warnings.prefix(5) {
                    Logger.shared.warning("[CSVParser] Row \(warning.row): \(warning.message)")
                }
                if result.warnings.count > 5 {
                    Logger.shared.warning("[CSVParser] ... and \(result.warnings.count - 5) more warnings")
                }
            }

            // Convert OralableCore.SensorData to ImportedSensorData
            return result.sensorData.map { ImportedSensorData(from: $0) }
        } catch {
            Logger.shared.error("[CSVParser] OralableCore parser failed: \(error.localizedDescription)")
            Logger.shared.info("[CSVParser] Falling back to legacy parser")

            // Fallback to legacy parsing for non-standard CSV formats
            return parseLegacy(content)
        }
    }

    /// Parse CSV content directly to SensorData array (for direct OralableCore use)
    /// - Parameter content: Raw CSV string content
    /// - Returns: Array of OralableCore.SensorData
    static func parseToSensorData(_ content: String) -> [SensorData] {
        let coreParser = OralableCore.CSVParser(configuration: .lenient)
        do {
            let result = try coreParser.parse(content)
            return result.sensorData
        } catch {
            Logger.shared.error("[CSVParser] Failed to parse to SensorData: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Legacy Parser (Fallback)

    /// Legacy parsing for CSV files that don't match OralableCore format
    /// (e.g., files with Device_Type, EMG, or different column names)
    private static func parseLegacy(_ content: String) -> [ImportedSensorData] {
        var result: [ImportedSensorData] = []
        let lines = content.components(separatedBy: .newlines)

        guard lines.count > 1 else { return result }

        // Parse header to find column indices
        let header = parseCSVLine(lines[0])
        let columnMap = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1.trimmingCharacters(in: .whitespaces), $0) })

        Logger.shared.info("[CSVParser] Legacy parser: \(lines.count - 1) rows, columns: \(header.joined(separator: ", "))")

        // Parse data rows
        for i in 1..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let values = parseCSVLine(line)

            let data = ImportedSensorData(
                timestamp: parseTimestamp(values, columnMap),
                deviceType: getString(values, columnMap, "Device_Type") ?? "Oralable",
                emg: getDouble(values, columnMap, "EMG"),
                ppgIR: getDouble(values, columnMap, "PPG_IR"),
                ppgRed: getDouble(values, columnMap, "PPG_Red"),
                ppgGreen: getDouble(values, columnMap, "PPG_Green"),
                accelX: getDouble(values, columnMap, "Accel_X"),
                accelY: getDouble(values, columnMap, "Accel_Y"),
                accelZ: getDouble(values, columnMap, "Accel_Z"),
                temperature: getDouble(values, columnMap, "Temperature") ?? getDouble(values, columnMap, "Temp_C"),
                battery: getDouble(values, columnMap, "Battery") ?? getDouble(values, columnMap, "Battery_%"),
                heartRate: getDouble(values, columnMap, "Heart_Rate") ?? getDouble(values, columnMap, "HeartRate_BPM")
            )

            result.append(data)
        }

        Logger.shared.info("[CSVParser] Legacy parser completed: \(result.count) data points")
        return result
    }

    // MARK: - Legacy Parsing Helpers

    /// Parse a CSV line handling quoted fields
    private static func parseCSVLine(_ line: String) -> [String] {
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
                columns.append(currentColumn.trimmingCharacters(in: .whitespaces))
                currentColumn = ""
            } else {
                currentColumn.append(char)
            }

            i = line.index(after: i)
        }

        columns.append(currentColumn.trimmingCharacters(in: .whitespaces))
        return columns
    }

    /// Parse timestamp from various formats
    private static func parseTimestamp(_ values: [String], _ columnMap: [String: Int]) -> Date {
        guard let index = columnMap["Timestamp"], index < values.count else {
            return Date()
        }

        let timestampString = values[index].trimmingCharacters(in: .whitespaces)

        // Try ISO8601 format first
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: timestampString) {
            return date
        }

        // Try standard date-time format with milliseconds
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        if let date = dateTimeFormatter.date(from: timestampString) {
            return date
        }

        // Try without milliseconds
        dateTimeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = dateTimeFormatter.date(from: timestampString) {
            return date
        }

        // Try time-only format (HH:mm:ss)
        let timeOnlyFormatter = DateFormatter()
        timeOnlyFormatter.dateFormat = "HH:mm:ss"
        if let date = timeOnlyFormatter.date(from: timestampString) {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute, .second], from: date)
            return calendar.date(bySettingHour: components.hour ?? 0,
                                minute: components.minute ?? 0,
                                second: components.second ?? 0,
                                of: Date()) ?? Date()
        }

        return Date()
    }

    private static func getString(_ values: [String], _ columnMap: [String: Int], _ column: String) -> String? {
        guard let index = columnMap[column], index < values.count else { return nil }
        let value = values[index].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func getDouble(_ values: [String], _ columnMap: [String: Int], _ column: String) -> Double? {
        guard let index = columnMap[column], index < values.count else { return nil }
        let value = values[index].trimmingCharacters(in: .whitespaces)
        return Double(value)
    }
}

// MARK: - CSV Import Preview

/// Preview information for CSV import
struct CSVImportPreview {
    let fileName: String
    let dataPoints: [ImportedSensorData]
    let dateRange: String
    let deviceTypes: Set<String>

    var summary: String {
        let types = deviceTypes.isEmpty ? "Unknown" : deviceTypes.joined(separator: ", ")
        return "\(dataPoints.count) readings from \(types) device(s)"
    }

    init(fileName: String, dataPoints: [ImportedSensorData]) {
        self.fileName = fileName
        self.dataPoints = dataPoints

        // Calculate date range
        if let first = dataPoints.first?.timestamp, let last = dataPoints.last?.timestamp {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short

            if Calendar.current.isDate(first, inSameDayAs: last) {
                formatter.timeStyle = .short
                self.dateRange = formatter.string(from: first)
            } else {
                self.dateRange = "\(formatter.string(from: first)) - \(formatter.string(from: last))"
            }
        } else {
            self.dateRange = "Unknown"
        }

        // Collect unique device types
        self.deviceTypes = Set(dataPoints.compactMap { $0.deviceType })
    }
}
