//
//  LoggingService.swift
//  OralableApp
//
//  Created by John A Cogan on 04/11/2025.
//

import Foundation
import Combine

// MARK: - Logging Service Protocol

/// Protocol for application logging service
protocol LoggingService: AnyObject {
    
    /// Publisher for log entries
    var logPublisher: AnyPublisher<LogEntry, Never> { get }
    
    /// Recent log entries (up to configured limit)
    var recentLogs: [LogEntry] { get }
    
    /// Log a debug message
    func debug(_ message: String, source: String?)
    
    /// Log an info message
    func info(_ message: String, source: String?)
    
    /// Log a warning message
    func warning(_ message: String, source: String?)
    
    /// Log an error message
    func error(_ message: String, source: String?)
    
    /// Log a message with specific level
    func log(level: LogLevel, message: String, source: String?)
    
    /// Clear all logs
    func clearLogs()
    
    /// Get logs within date range
    func logs(from startDate: Date, to endDate: Date) -> [LogEntry]
    
    /// Get logs filtered by level
    func logs(withLevel level: LogLevel) -> [LogEntry]
    
    /// Export logs to file
    func exportLogs() async throws -> URL
}

// MARK: - Application Logging Service

/// Concrete implementation of logging service
class AppLoggingService: LoggingService, ObservableObject {
    
    // MARK: - Properties
    
    private let logSubject = PassthroughSubject<LogEntry, Never>()
    var logPublisher: AnyPublisher<LogEntry, Never> {
        logSubject.eraseToAnyPublisher()
    }
    
    @Published private(set) var recentLogs: [LogEntry] = []
    
    private let maxLogEntries: Int
    private let queue = DispatchQueue(label: "app.logging", qos: .background)
    private let fileLogger: FileLogger?
    
    // MARK: - Initialization
    
    init(maxLogEntries: Int = 1000, enableFileLogging: Bool = false) {
        self.maxLogEntries = maxLogEntries
        self.fileLogger = enableFileLogging ? FileLogger() : nil
        
        setupLogPublisher()
    }
    
    private func setupLogPublisher() {
        logSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logEntry in
                self?.addToRecentLogs(logEntry)
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Logging Methods
    
    func debug(_ message: String, source: String? = nil) {
        log(level: .debug, message: message, source: source)
    }
    
    func info(_ message: String, source: String? = nil) {
        log(level: .info, message: message, source: source)
    }
    
    func warning(_ message: String, source: String? = nil) {
        log(level: .warning, message: message, source: source)
    }
    
    func error(_ message: String, source: String? = nil) {
        log(level: .error, message: message, source: source)
    }
    
    func log(level: LogLevel, message: String, source: String?) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message,
            category: source ?? "App"
        )
        
        // Console logging
        print("[\(level.icon) \(formatTimestamp(entry.timestamp))] \(source ?? "App"): \(message)")
        
        // File logging (if enabled)
        fileLogger?.log(entry)
        
        // Publish to subscribers
        logSubject.send(entry)
    }
    
    // MARK: - Log Management
    
    func clearLogs() {
        DispatchQueue.main.async {
            self.recentLogs.removeAll()
        }
        fileLogger?.clearLogs()
    }
    
    func logs(from startDate: Date, to endDate: Date) -> [LogEntry] {
        return recentLogs.filter { entry in
            entry.timestamp >= startDate && entry.timestamp <= endDate
        }
    }
    
    func logs(withLevel level: LogLevel) -> [LogEntry] {
        return recentLogs.filter { $0.level == level }
    }
    
    func exportLogs() async throws -> URL {
        let logs = recentLogs
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        var logContent = "Timestamp,Level,Category,Message\n"
        
        for entry in logs.sorted(by: { $0.timestamp < $1.timestamp }) {
            let timestamp = dateFormatter.string(from: entry.timestamp)
            let level = entry.level.rawValue
            let category = entry.category
            let message = entry.message.replacingOccurrences(of: "\"", with: "\"\"")
            
            logContent += "\"\(timestamp)\",\"\(level)\",\"\(category)\",\"\(message)\"\n"
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "mam_logs_\(formatDateForFilename(Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try logContent.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    }
    
    // MARK: - Private Methods
    
    private func addToRecentLogs(_ entry: LogEntry) {
        recentLogs.append(entry)
        
        // Maintain log limit
        if recentLogs.count > maxLogEntries {
            recentLogs.removeFirst(recentLogs.count - maxLogEntries)
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }
}

// MARK: - File Logger

/// Internal file logger for persistent logging
private class FileLogger {
    
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "file.logger", qos: .background)
    private let maxFileSize: Int64 = 10 * 1024 * 1024 // 10MB
    
    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logsDirectory = documentsPath.appendingPathComponent("Logs")
        
        // Create logs directory if it doesn't exist
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        
        self.logFileURL = logsDirectory.appendingPathComponent("oralable.log")
        
        // Create log file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
    }
    
    func log(_ entry: LogEntry) {
        queue.async { [weak self] in
            self?.writeToFile(entry)
        }
    }
    
    func clearLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }
            try? "".write(to: self.logFileURL, atomically: true, encoding: .utf8)
        }
    }
    
    private func writeToFile(_ entry: LogEntry) {
        let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
        let logLine = "[\(timestamp)] [\(entry.level.rawValue.uppercased())] \(entry.category): \(entry.message)\n"
        
        // Check file size and rotate if needed
        if let fileAttributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
           let fileSize = fileAttributes[.size] as? Int64,
           fileSize > maxFileSize {
            rotateLogFile()
        }
        
        // Append to file
        if let data = logLine.data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        }
    }
    
    private func rotateLogFile() {
        let backupURL = logFileURL.appendingPathExtension("old")
        
        // Remove old backup
        try? FileManager.default.removeItem(at: backupURL)
        
        // Move current log to backup
        try? FileManager.default.moveItem(at: logFileURL, to: backupURL)
        
        // Create new empty log file
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }
}

// MARK: - Mock Logging Service

#if DEBUG
/// Mock logging service for testing and previews
class MockLoggingService: LoggingService, ObservableObject {
    
    private let logSubject = PassthroughSubject<LogEntry, Never>()
    var logPublisher: AnyPublisher<LogEntry, Never> {
        logSubject.eraseToAnyPublisher()
    }
    
    @Published private(set) var recentLogs: [LogEntry] = []
    
    init() {
        // Add some sample logs for preview
        recentLogs = [
            LogEntry(timestamp: Date().addingTimeInterval(-300), level: .info, message: "App started", category: "App"),
            LogEntry(timestamp: Date().addingTimeInterval(-250), level: .debug, message: "Scanning for devices", category: "DeviceManager"),
            LogEntry(timestamp: Date().addingTimeInterval(-200), level: .info, message: "Found MAM", category: "BLE"),
            LogEntry(timestamp: Date().addingTimeInterval(-150), level: .info, message: "Connected successfully", category: "OralableDevice"),
            LogEntry(timestamp: Date().addingTimeInterval(-100), level: .debug, message: "Received PPG data: 20 samples", category: "OralableDevice"),
            LogEntry(timestamp: Date().addingTimeInterval(-50), level: .warning, message: "Low battery: 15%", category: "BatteryMonitor"),
            LogEntry(timestamp: Date().addingTimeInterval(-10), level: .info, message: "Heart rate calculated: 72 bpm", category: "HeartRateCalculator")
        ]
    }
    
    func debug(_ message: String, source: String?) {
        log(level: .debug, message: message, source: source)
    }
    
    func info(_ message: String, source: String?) {
        log(level: .info, message: message, source: source)
    }
    
    func warning(_ message: String, source: String?) {
        log(level: .warning, message: message, source: source)
    }
    
    func error(_ message: String, source: String?) {
        log(level: .error, message: message, source: source)
    }
    
    func log(level: LogLevel, message: String, source: String?) {
        let entry = LogEntry(level: level, message: message, category: source ?? "App")
        recentLogs.append(entry)
        logSubject.send(entry)
        
        // Keep only recent logs
        if recentLogs.count > 100 {
            recentLogs.removeFirst(recentLogs.count - 100)
        }
    }
    
    func clearLogs() {
        recentLogs.removeAll()
    }
    
    func logs(from startDate: Date, to endDate: Date) -> [LogEntry] {
        return recentLogs.filter { entry in
            entry.timestamp >= startDate && entry.timestamp <= endDate
        }
    }
    
    func logs(withLevel level: LogLevel) -> [LogEntry] {
        return recentLogs.filter { $0.level == level }
    }
    
    func exportLogs() async throws -> URL {
        // Mock implementation
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("mock_logs.csv")
        try "Mock log export".write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
#endif

// MARK: - Logging Extensions

extension LoggingService {
    
    /// Log with automatic source detection (uses calling function)
    func log(_ level: LogLevel, _ message: String, file: String = #file, function: String = #function) {
        let fileName = (file as NSString).lastPathComponent
        let source = "\(fileName).\(function)"
        log(level: level, message: message, source: source)
    }
    
    /// Convenience methods with automatic source detection
    func debug(_ message: String, file: String = #file, function: String = #function) {
        log(.debug, message, file: file, function: function)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function) {
        log(.info, message, file: file, function: function)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function) {
        log(.warning, message, file: file, function: function)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function) {
        log(.error, message, file: file, function: function)
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

struct LoggingEnvironmentKey: EnvironmentKey {
    static let defaultValue: LoggingService = AppLoggingService()
}

extension EnvironmentValues {
    var logger: LoggingService {
        get { self[LoggingEnvironmentKey.self] }
        set { self[LoggingEnvironmentKey.self] = newValue }
    }
}