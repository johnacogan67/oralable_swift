import Foundation

/// Manager for importing sensor data and logs from CSV format
class CSVImportManager: ObservableObject {
    // MARK: - Dependency Injection (Phase 4: Singleton Removed)
    // Note: Use AppDependencies.shared.csvImportManager instead

    init() {}
    
    /// Import sensor data and logs from CSV file
    /// - Parameter url: URL of the CSV file to import
    /// - Returns: Tuple containing imported sensor data and logs, or nil if import fails
    func importData(from url: URL) -> (sensorData: [SensorData], logs: [String])? {
        do {
            let csvContent = try String(contentsOf: url, encoding: .utf8)
            return parseCSVContent(csvContent)
        } catch {
            Logger.shared.error("[CSVImportManager] Failed to read CSV file: \(error)")
            return nil
        }
    }
    
    /// Parse CSV content and extract sensor data and logs
    private func parseCSVContent(_ csvContent: String) -> (sensorData: [SensorData], logs: [String])? {
        let lines = csvContent.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard !lines.isEmpty else {
            Logger.shared.warning("[CSVImportManager] CSV file is empty")
            return nil
        }
        
        // Skip header line
        let dataLines = Array(lines.dropFirst())
        
        var sensorDataArray: [SensorData] = []
        var logs: [String] = []
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        for line in dataLines {
            let fields = parseCSVLine(line)

            guard fields.count >= 14 else {
                Logger.shared.warning("[CSVImportManager] Invalid CSV line format: \(line)")
                continue
            }

            // Parse timestamp
            guard let timestamp = dateFormatter.date(from: fields[0]) else {
                Logger.shared.warning("[CSVImportManager] Invalid timestamp format: \(fields[0])")
                continue
            }
            
            // Check if this is a log-only entry (all sensor fields are empty)
            let sensorFieldsEmpty = fields[1...12].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            
            if sensorFieldsEmpty {
                // This is a log entry
                let message = unescapeCSVField(fields[13])
                if !message.isEmpty {
                    logs.append(message)
                }
            } else {
                // This is a sensor data entry
                if let sensorData = parseSensorData(from: fields, timestamp: timestamp) {
                    sensorDataArray.append(sensorData)
                    
                    // Add associated log message if present
                    let message = unescapeCSVField(fields[13])
                    if !message.isEmpty {
                        logs.append(message)
                    }
                }
            }
        }
        
        return (sensorData: sensorDataArray, logs: logs)
    }
    
    /// Parse a single CSV line, handling quoted fields
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false
        var i = line.startIndex
        
        while i < line.endIndex {
            let char = line[i]
            
            if char == "\"" {
                if insideQuotes && i < line.index(before: line.endIndex) && line[line.index(after: i)] == "\"" {
                    // Double quote - add single quote to field
                    currentField += "\""
                    i = line.index(i, offsetBy: 2)
                } else {
                    // Toggle quote state
                    insideQuotes.toggle()
                    i = line.index(after: i)
                }
            } else if char == "," && !insideQuotes {
                // Field separator
                fields.append(currentField)
                currentField = ""
                i = line.index(after: i)
            } else {
                // Regular character
                currentField += String(char)
                i = line.index(after: i)
            }
        }
        
        // Add the last field
        fields.append(currentField)
        
        return fields
    }
    
    /// Parse sensor data from CSV fields
    private func parseSensorData(from fields: [String], timestamp: Date) -> SensorData? {
        guard fields.count >= 13 else { return nil }
        
        // Parse PPG data (convert to Int32)
        guard let ppgIR = Int32(fields[1]),
              let ppgRed = Int32(fields[2]),
              let ppgGreen = Int32(fields[3]) else {
            Logger.shared.warning("[CSVImportManager] Invalid PPG data")
            return nil
        }

        // Parse accelerometer data (convert to Int16)
        guard let accelX = Int16(fields[4]),
              let accelY = Int16(fields[5]),
              let accelZ = Int16(fields[6]) else {
            Logger.shared.warning("[CSVImportManager] Invalid accelerometer data")
            return nil
        }

        // Parse temperature
        guard let tempCelsius = Double(fields[7]) else {
            Logger.shared.warning("[CSVImportManager] Invalid temperature data")
            return nil
        }

        // Parse battery
        guard let batteryPercentage = Int(fields[8]) else {
            Logger.shared.warning("[CSVImportManager] Invalid battery data")
            return nil
        }
        
        // Parse optional heart rate
        var heartRate: HeartRateData?
        if !fields[9].isEmpty && !fields[10].isEmpty,
           let bpm = Double(fields[9]),
           let quality = Double(fields[10]) {
            heartRate = HeartRateData(bpm: bpm, quality: quality, timestamp: timestamp)
        }
        
        // Parse optional SpO2
        var spo2: SpO2Data?
        if !fields[11].isEmpty && !fields[12].isEmpty,
           let percentage = Double(fields[11]),
           let quality = Double(fields[12]) {
            spo2 = SpO2Data(percentage: percentage, quality: quality, timestamp: timestamp)
        }
        
        return SensorData(
            timestamp: timestamp,
            ppg: PPGData(red: ppgRed, ir: ppgIR, green: ppgGreen, timestamp: timestamp),
            accelerometer: AccelerometerData(x: accelX, y: accelY, z: accelZ, timestamp: timestamp),
            temperature: TemperatureData(celsius: tempCelsius, timestamp: timestamp),
            battery: BatteryData(percentage: batteryPercentage, timestamp: timestamp),
            heartRate: heartRate,
            spo2: spo2
        )
    }
    
    /// Unescape CSV field by removing outer quotes and converting double quotes
    private func unescapeCSVField(_ field: String) -> String {
        var result = field
        
        // Remove outer quotes if present
        if result.hasPrefix("\"") && result.hasSuffix("\"") {
            result = String(result.dropFirst().dropLast())
        }
        
        // Convert double quotes to single quotes
        result = result.replacingOccurrences(of: "\"\"", with: "\"")
        
        return result
    }
    
    /// Validate CSV file format before importing
    func validateCSVFile(at url: URL) -> ValidationResult {
        do {
            let csvContent = try String(contentsOf: url, encoding: .utf8)
            let lines = csvContent.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            
            guard !lines.isEmpty else {
                return ValidationResult(isValid: false, errorMessage: "CSV file is empty", estimatedDataPoints: 0)
            }
            
            // Check header
            let headerLine = lines.first!
            let expectedHeaders = [
                "Timestamp", "PPG_IR", "PPG_Red", "PPG_Green",
                "Accel_X", "Accel_Y", "Accel_Z", "Temp_C", "Battery_%",
                "HeartRate_BPM", "HeartRate_Quality", "SpO2_%", "SpO2_Quality", "Message"
            ]
            
            let actualHeaders = parseCSVLine(headerLine)
            
            guard actualHeaders.count >= expectedHeaders.count else {
                let errorMessage = """
                Invalid header format. Expected \(expectedHeaders.count) columns, found \(actualHeaders.count).
                
                Expected headers:
                \(expectedHeaders.joined(separator: ", "))
                
                Found headers:
                \(actualHeaders.joined(separator: ", "))
                """
                return ValidationResult(isValid: false, errorMessage: errorMessage, estimatedDataPoints: 0)
            }
            
            for (index, expectedHeader) in expectedHeaders.enumerated() {
                if index < actualHeaders.count && actualHeaders[index] != expectedHeader {
                    let errorMessage = """
                    Invalid header at column \(index + 1).
                    Expected: '\(expectedHeader)'
                    Found: '\(actualHeaders[index])'
                    
                    Full expected header row:
                    \(expectedHeaders.joined(separator: ","))
                    """
                    return ValidationResult(isValid: false, errorMessage: errorMessage, estimatedDataPoints: 0)
                }
            }
            
            let dataLines = Array(lines.dropFirst())
            return ValidationResult(isValid: true, errorMessage: nil, estimatedDataPoints: dataLines.count)
            
        } catch {
            return ValidationResult(isValid: false, errorMessage: "Failed to read file: \(error.localizedDescription)", estimatedDataPoints: 0)
        }
    }
}

/// Result of CSV file validation
struct ValidationResult {
    let isValid: Bool
    let errorMessage: String?
    let estimatedDataPoints: Int
}

// MARK: - CSV Template Generation

extension CSVImportManager {
    
    /// Generate a sample CSV file with correct format
    /// - Returns: URL of the generated template file
    func generateTemplate() -> URL? {
        let headers = [
            "Timestamp", "PPG_IR", "PPG_Red", "PPG_Green",
            "Accel_X", "Accel_Y", "Accel_Z", "Temp_C", "Battery_%",
            "HeartRate_BPM", "HeartRate_Quality", "SpO2_%", "SpO2_Quality", "Message"
        ]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        var csvContent = headers.joined(separator: ",") + "\n"
        
        // Add sample rows
        let sampleTimestamp = dateFormatter.string(from: Date())
        csvContent += "\(sampleTimestamp),12345,67890,11111,100,200,300,36.5,85,72,0.95,98,0.98,Sample measurement\n"
        csvContent += "\(sampleTimestamp),,,,,,,,,,,,,Log entry without sensor data\n"
        
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let templateURL = tempDir.appendingPathComponent("mam_template.csv")
            try csvContent.write(to: templateURL, atomically: true, encoding: .utf8)
            return templateURL
        } catch {
            Logger.shared.error("[CSVImportManager] Failed to generate template: \(error)")
            return nil
        }
    }
    
    /// Get the expected CSV format as a string for display
    var expectedFormat: String {
        """
        Expected CSV Format:
        
        Header Row (required):
        Timestamp,PPG_IR,PPG_Red,PPG_Green,Accel_X,Accel_Y,Accel_Z,Temp_C,Battery_%,HeartRate_BPM,HeartRate_Quality,SpO2_%,SpO2_Quality,Message
        
        Timestamp Format:
        yyyy-MM-dd HH:mm:ss.SSS (e.g., 2025-11-05 14:30:45.123)
        
        Data Types:
        - Timestamp: Date/time string
        - PPG_IR, PPG_Red, PPG_Green: 32-bit integers
        - Accel_X, Accel_Y, Accel_Z: 16-bit integers
        - Temp_C: Decimal number (temperature in Celsius)
        - Battery_%: Integer (0-100)
        - HeartRate_BPM: Decimal number (optional)
        - HeartRate_Quality: Decimal 0.0-1.0 (optional)
        - SpO2_%: Decimal number (optional)
        - SpO2_Quality: Decimal 0.0-1.0 (optional)
        - Message: Text (optional, use quotes if contains commas)
        
        Notes:
        - Empty sensor fields with a message = log entry only
        - All fields present = sensor data with optional log
        - Use quotes around fields containing commas or newlines
        - Double quotes inside fields should be escaped as ""
        """
    }
}
