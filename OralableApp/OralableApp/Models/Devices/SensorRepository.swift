//
//  SensorRepository.swift
//  OralableApp
//
//  Created by John A Cogan on 04/11/2025.
//

import Foundation
import OralableCore

/// Protocol for sensor data repository operations
protocol SensorRepository {
    
    // MARK: - Save Operations
    
    /// Save a single sensor reading
    func save(_ reading: SensorReading) async throws
    
    /// Save multiple sensor readings
    func save(_ readings: [SensorReading]) async throws
    
    // MARK: - Query Operations
    
    /// Get all readings for a specific sensor type
    func readings(for sensorType: SensorType) async throws -> [SensorReading]
    
    /// Get readings within a date range
    func readings(
        for sensorType: SensorType,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [SensorReading]
    
    /// Get readings from a specific device
    func readings(from deviceId: String) async throws -> [SensorReading]
    
    /// Get latest reading for a sensor type
    func latestReading(for sensorType: SensorType) async throws -> SensorReading?
    
    /// Get readings count for a sensor type
    func readingsCount(for sensorType: SensorType) async throws -> Int
    
    /// Get all readings within date range (for export)
    func allReadings(from startDate: Date, to endDate: Date) async throws -> [SensorReading]
    
    // MARK: - Summary Operations
    
    /// Get data summary for dashboard
    func dataSummary() async throws -> DataSummary
    
    /// Get recent readings (last N entries)
    func recentReadings(limit: Int) async throws -> [SensorReading]
    
    // MARK: - Maintenance Operations
    
    /// Clear all sensor data
    func clearAllData() async throws
    
    /// Clear data older than specified date
    func clearData(olderThan date: Date) async throws
    
    /// Get total storage size estimate
    func storageSize() async throws -> Int64
}

// MARK: - Data Summary Model

/// Summary of sensor data for dashboard display
struct DataSummary: Codable {
    
    /// Total number of readings
    let totalReadings: Int
    
    /// Date range of available data
    let dateRange: DateInterval?
    
    /// Readings count by sensor type
    let readingsBySensor: [SensorType: Int]
    
    /// Latest readings by sensor type
    let latestReadings: [SensorType: SensorReading]
    
    /// Connected devices that have contributed data
    let connectedDevices: Set<String>
    
    /// Data quality metrics
    let qualityMetrics: DataQualityMetrics
    
    // MARK: - Computed Properties
    
    var hasData: Bool {
        totalReadings > 0
    }
    
    var dataRangeText: String {
        guard let range = dateRange else {
            return "No data available"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        if Calendar.current.isDate(range.start, inSameDayAs: range.end) {
            formatter.timeStyle = .short
            return "Today: \(formatter.string(from: range.start)) - \(formatter.string(from: range.end))"
        } else {
            formatter.timeStyle = .none
            return "\(formatter.string(from: range.start)) - \(formatter.string(from: range.end))"
        }
    }
}

// MARK: - Data Quality Metrics

/// Metrics for assessing data quality
struct DataQualityMetrics: Codable {
    
    /// Percentage of readings with quality scores
    let readingsWithQuality: Double
    
    /// Average quality score (0.0 - 1.0)
    let averageQuality: Double
    
    /// Number of invalid readings
    let invalidReadings: Int
    
    /// Percentage of valid readings
    let validReadingsPercentage: Double
    
    /// Data gaps (periods longer than expected between readings)
    let dataGaps: [DateInterval]
    
    /// Overall quality rating
    var qualityRating: QualityRating {
        switch averageQuality {
        case 0.8...1.0:
            return .excellent
        case 0.6..<0.8:
            return .good
        case 0.4..<0.6:
            return .fair
        default:
            return .poor
        }
    }
}

enum QualityRating: String, Codable, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    
    var displayName: String {
        switch self {
        case .excellent:
            return "Excellent"
        case .good:
            return "Good"
        case .fair:
            return "Fair"
        case .poor:
            return "Poor"
        }
    }
    
    var color: String {
        switch self {
        case .excellent:
            return "systemGreen"
        case .good:
            return "systemBlue"
        case .fair:
            return "systemOrange"
        case .poor:
            return "systemRed"
        }
    }
}

// MARK: - In-Memory Implementation

/// In-memory implementation of SensorRepository for development and testing
class InMemorySensorRepository: SensorRepository {
    
    private var readings: [SensorReading] = []
    private let queue = DispatchQueue(label: "sensor.repository", attributes: .concurrent)
    
    // MARK: - Save Operations
    
    func save(_ reading: SensorReading) async throws {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.readings.append(reading)
                continuation.resume()
            }
        }
    }
    
    func save(_ readings: [SensorReading]) async throws {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.readings.append(contentsOf: readings)
                continuation.resume()
            }
        }
    }
    
    // MARK: - Query Operations
    
    func readings(for sensorType: SensorType) async throws -> [SensorReading] {
        return await withCheckedContinuation { continuation in
            queue.async {
                let filtered = self.readings.filter { $0.sensorType == sensorType }
                continuation.resume(returning: filtered)
            }
        }
    }
    
    func readings(
        for sensorType: SensorType,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [SensorReading] {
        return await withCheckedContinuation { continuation in
            queue.async {
                let filtered = self.readings.filter {
                    $0.sensorType == sensorType &&
                    $0.timestamp >= startDate &&
                    $0.timestamp <= endDate
                }
                continuation.resume(returning: filtered)
            }
        }
    }
    
    func readings(from deviceId: String) async throws -> [SensorReading] {
        return await withCheckedContinuation { continuation in
            queue.async {
                let filtered = self.readings.filter { $0.deviceId == deviceId }
                continuation.resume(returning: filtered)
            }
        }
    }
    
    func latestReading(for sensorType: SensorType) async throws -> SensorReading? {
        return await withCheckedContinuation { continuation in
            queue.async {
                let latest = self.readings
                    .filter { $0.sensorType == sensorType }
                    .max { $0.timestamp < $1.timestamp }
                continuation.resume(returning: latest)
            }
        }
    }
    
    func readingsCount(for sensorType: SensorType) async throws -> Int {
        return await withCheckedContinuation { continuation in
            queue.async {
                let count = self.readings.filter { $0.sensorType == sensorType }.count
                continuation.resume(returning: count)
            }
        }
    }
    
    func allReadings(from startDate: Date, to endDate: Date) async throws -> [SensorReading] {
        return await withCheckedContinuation { continuation in
            queue.async {
                let filtered = self.readings.filter {
                    $0.timestamp >= startDate && $0.timestamp <= endDate
                }
                continuation.resume(returning: filtered.sorted { $0.timestamp < $1.timestamp })
            }
        }
    }
    
    // MARK: - Summary Operations
    
    func dataSummary() async throws -> DataSummary {
        return await withCheckedContinuation { continuation in
            queue.async {
                let totalReadings = self.readings.count
                
                let dateRange: DateInterval? = {
                    guard !self.readings.isEmpty else { return nil }
                    let timestamps = self.readings.map { $0.timestamp }
                    let earliest = timestamps.min()!
                    let latest = timestamps.max()!
                    return DateInterval(start: earliest, end: latest)
                }()
                
                let readingsBySensor = Dictionary(grouping: self.readings, by: { $0.sensorType })
                    .mapValues { $0.count }
                
                let latestReadings: [SensorType: SensorReading] = {
                    var latest: [SensorType: SensorReading] = [:]
                    for sensorType in SensorType.allCases {
                        let sensorReadings = self.readings.filter { $0.sensorType == sensorType }
                        if let latestReading = sensorReadings.max(by: { $0.timestamp < $1.timestamp }) {
                            latest[sensorType] = latestReading
                        }
                    }
                    return latest
                }()
                
                let connectedDevices = Set(self.readings.compactMap { $0.deviceId })
                
                let qualityMetrics = self.calculateQualityMetrics()
                
                let summary = DataSummary(
                    totalReadings: totalReadings,
                    dateRange: dateRange,
                    readingsBySensor: readingsBySensor,
                    latestReadings: latestReadings,
                    connectedDevices: connectedDevices,
                    qualityMetrics: qualityMetrics
                )
                
                continuation.resume(returning: summary)
            }
        }
    }
    
    func recentReadings(limit: Int) async throws -> [SensorReading] {
        return await withCheckedContinuation { continuation in
            queue.async {
                let recent = Array(self.readings
                    .sorted { $0.timestamp > $1.timestamp }
                    .prefix(limit))
                continuation.resume(returning: recent)
            }
        }
    }
    
    // MARK: - Maintenance Operations
    
    func clearAllData() async throws {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.readings.removeAll()
                continuation.resume()
            }
        }
    }
    
    func clearData(olderThan date: Date) async throws {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.readings = self.readings.filter { $0.timestamp >= date }
                continuation.resume()
            }
        }
    }
    
    func storageSize() async throws -> Int64 {
        // Rough estimate: each reading is about 200 bytes when serialized
        return Int64(readings.count * 200)
    }
    
    // MARK: - Private Methods
    
    private func calculateQualityMetrics() -> DataQualityMetrics {
        let readingsWithQuality = readings.filter { $0.quality != nil }
        let readingsWithQualityPercentage = readings.isEmpty ? 0.0 : 
            Double(readingsWithQuality.count) / Double(readings.count)
        
        let averageQuality = readingsWithQuality.isEmpty ? 0.0 :
            readingsWithQuality.compactMap { $0.quality }.reduce(0.0, +) / Double(readingsWithQuality.count)
        
        let invalidReadings = readings.filter { !$0.isValid }.count
        let validReadingsPercentage = readings.isEmpty ? 0.0 :
            Double(readings.count - invalidReadings) / Double(readings.count)
        
        // Simple data gap detection (gaps > 1 minute)
        let dataGaps = detectDataGaps()
        
        return DataQualityMetrics(
            readingsWithQuality: readingsWithQualityPercentage,
            averageQuality: averageQuality,
            invalidReadings: invalidReadings,
            validReadingsPercentage: validReadingsPercentage,
            dataGaps: dataGaps
        )
    }
    
    private func detectDataGaps() -> [DateInterval] {
        let sortedReadings = readings.sorted { $0.timestamp < $1.timestamp }
        var gaps: [DateInterval] = []
        let gapThreshold: TimeInterval = 60 // 1 minute
        
        for i in 1..<sortedReadings.count {
            let previous = sortedReadings[i - 1]
            let current = sortedReadings[i]
            let timeDiff = current.timestamp.timeIntervalSince(previous.timestamp)
            
            if timeDiff > gapThreshold {
                gaps.append(DateInterval(start: previous.timestamp, end: current.timestamp))
            }
        }
        
        return gaps
    }
}

// MARK: - Repository Error

enum RepositoryError: LocalizedError {
    case notFound
    case invalidData
    case storageError(String)
    case corruptedData
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Data not found"
        case .invalidData:
            return "Invalid data format"
        case .storageError(let message):
            return "Storage error: \(message)"
        case .corruptedData:
            return "Data is corrupted and cannot be read"
        }
    }
}