//
//  CSVExportManager.swift
//  OralableApp
//
//  Manages CSV export operations for sensor data.
//
//  Features:
//  - Dynamic column selection based on FeatureFlags
//  - Uses OralableCore.CSVExporter for generation
//  - Handles file creation and cleanup
//  - Event-based export for muscle activity events
//
//  Export Types:
//  - Continuous data export: All sensor samples
//  - Event-based export: Threshold-triggered events only
//
//  File Location:
//  - Cache/Exports directory for sharing
//  - Documents directory for History view access
//
//  Filename Format:
//  oralable_data_{userID}_{timestamp}.csv
//

import Foundation
import OralableCore

// MARK: - CSV Export Manager

/// Manager for exporting sensor data and logs to CSV format
/// Only exports columns for metrics that have visible dashboard cards
/// Uses OralableCore.CSVExporter for core CSV generation
class CSVExportManager: ObservableObject {
    static let shared = CSVExportManager()
    private let featureFlags = FeatureFlags.shared

    init() {}

    /// Build export configuration based on current feature flags
    private func buildConfiguration() -> CSVExportConfiguration {
        var columns: [CSVColumn] = [.timestamp, .ppgIR, .ppgRed, .ppgGreen]

        if featureFlags.showMovementCard {
            columns.append(contentsOf: [.accelX, .accelY, .accelZ])
        }
        if featureFlags.showTemperatureCard {
            columns.append(.temperature)
        }
        if featureFlags.showBatteryCard {
            columns.append(.battery)
        }
        if featureFlags.showHeartRateCard {
            columns.append(contentsOf: [.heartRateBPM, .heartRateQuality])
        }
        if featureFlags.showSpO2Card {
            columns.append(contentsOf: [.spo2Percentage, .spo2Quality])
        }
        columns.append(.message)

        return CSVExportConfiguration(columns: columns)
    }
    
    /// Export sensor data and logs to CSV file
    /// - Parameters:
    ///   - sensorData: Array of sensor data points
    ///   - logs: Array of log messages
    /// - Returns: URL of the exported CSV file, or nil if export fails
    func exportData(sensorData: [SensorData], logs: [String]) -> URL? {
        // Use OralableCore's CSVExporter with dynamic configuration
        let configuration = buildConfiguration()
        let exporter = CSVExporter(configuration: configuration)
        let csvContent = exporter.generateCSV(from: sensorData, logs: logs)
        
        // Create filename with current timestamp and user identifier
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        // Get user identifier (first 8 chars of Apple ID for brevity)
        // User ID is persisted in UserDefaults by AuthenticationManager
        let userIdentifier: String
        if let userID = UserDefaults.standard.string(forKey: "userID"), !userID.isEmpty {
            // Use first 8 characters of the Apple ID user identifier
            userIdentifier = String(userID.prefix(8))
        } else {
            // Fallback for guest users or unauthenticated state
            userIdentifier = "guest"
        }

        let filename = "oralable_data_\(userIdentifier)_\(timestamp).csv"
        
        // Use the cache directory for temporary files that need to be shared
        // This is accessible by the share sheet and gets cleaned up automatically
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let exportDirectory = cacheDirectory.appendingPathComponent("Exports", isDirectory: true)
        
        // Create exports directory if it doesn't exist
        if !fileManager.fileExists(atPath: exportDirectory.path) {
            try? fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        }
        
        let fileURL = exportDirectory.appendingPathComponent(filename)
        
        do {
            // Remove existing file if present
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            
            // Write the CSV content
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            Logger.shared.info("[CSVExportManager] Successfully exported CSV to: \(fileURL.path)")
            return fileURL
        } catch {
            Logger.shared.error("[to write CSV file: \(error)")
            return nil
        }
    }
    
    // CSV generation is now handled by OralableCore.CSVExporter

    // MARK: - Event-Based Export

    /// Export muscle activity events to CSV file
    /// - Parameters:
    ///   - events: Array of muscle activity events to export
    ///   - options: Export options controlling which columns are included
    /// - Returns: URL of the exported CSV file, or nil if export fails
    func exportEvents(_ events: [MuscleActivityEvent], options: EventCSVExporter.ExportOptions? = nil) -> URL? {
        guard !events.isEmpty else {
            Logger.shared.info("[CSVExportManager] No events to export")
            return nil
        }

        // Use provided options or build from feature flags
        let exportOptions = options ?? buildEventExportOptions()

        // Create filename with current timestamp and user identifier
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        // Get user identifier
        let userIdentifier: String
        if let userID = UserDefaults.standard.string(forKey: "userID"), !userID.isEmpty {
            userIdentifier = String(userID.prefix(8))
        } else {
            userIdentifier = "guest"
        }

        let filename = "oralable_events_\(userIdentifier)_\(timestamp).csv"

        // Use the cache directory for temporary files
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let exportDirectory = cacheDirectory.appendingPathComponent("Exports", isDirectory: true)

        // Create exports directory if it doesn't exist
        if !fileManager.fileExists(atPath: exportDirectory.path) {
            try? fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        }

        let fileURL = exportDirectory.appendingPathComponent(filename)

        do {
            // Remove existing file if present
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }

            // Generate and write CSV content
            let csvContent = EventCSVExporter.exportToCSV(events: events, options: exportOptions)
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)

            Logger.shared.info("[CSVExportManager] Successfully exported \(events.count) events to: \(fileURL.path)")
            return fileURL
        } catch {
            Logger.shared.error("[CSVExportManager] Failed to write event CSV file: \(error)")
            return nil
        }
    }

    /// Build event export options based on current feature flags
    private func buildEventExportOptions() -> EventCSVExporter.ExportOptions {
        EventCSVExporter.ExportOptions(
            includeTemperature: featureFlags.showTemperatureCard,
            includeHR: featureFlags.showHeartRateCard,
            includeSpO2: featureFlags.showSpO2Card,
            includeSleep: false // Sleep not currently tracked
        )
    }

    /// Get event export summary
    func getEventExportSummary(events: [MuscleActivityEvent]) -> EventExportSummary {
        let options = buildEventExportOptions()
        return EventCSVExporter.getExportSummary(events: events, options: options)
    }

    /// Get estimated file size for export
    func estimateExportSize(sensorDataCount: Int, logCount: Int) -> String {
        // Rough estimation: each sensor data row is about 150 characters
        // Each log entry is about 100 characters on average
        let estimatedBytes = (sensorDataCount * 150) + (logCount * 100) + 200 // 200 for header
        
        return ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file)
    }
    
    /// Get export summary information
    func getExportSummary(sensorData: [SensorData], logs: [String]) -> ExportSummary {
        let dateRange = getDateRange(from: sensorData)
        let estimatedSize = estimateExportSize(sensorDataCount: sensorData.count, logCount: logs.count)
        
        return ExportSummary(
            sensorDataCount: sensorData.count,
            logCount: logs.count,
            dateRange: dateRange,
            estimatedSize: estimatedSize
        )
    }
    
    /// Get date range from sensor data
    private func getDateRange(from sensorData: [SensorData]) -> String {
        guard !sensorData.isEmpty else { return "No data" }
        
        let sortedData = sensorData.sorted { $0.timestamp < $1.timestamp }
        let startDate = sortedData.first!.timestamp
        let endDate = sortedData.last!.timestamp
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return dateFormatter.string(from: startDate)
        } else {
            return "\(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate))"
        }
    }
    
    /// Clean up old export files from the cache directory
    /// This helps manage disk space by removing temporary export files
    func cleanupOldExports() {
        let fileManager = FileManager.default
        guard let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        
        let exportDirectory = cacheDirectory.appendingPathComponent("Exports", isDirectory: true)
        
        guard fileManager.fileExists(atPath: exportDirectory.path) else {
            return
        }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: exportDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            
            // Remove files older than 24 hours
            let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
            
            for fileURL in fileURLs {
                if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let creationDate = attributes[.creationDate] as? Date,
                   creationDate < dayAgo {
                    try? fileManager.removeItem(at: fileURL)
                    Logger.shared.debug("[CSVExportManager] Cleaned up old export file: \(fileURL.lastPathComponent)")
                }
            }
        } catch {
            Logger.shared.error("[cleaning up exports: \(error)")
        }
    }
}