//
//  Logger.swift
//  OralableApp
//
//  Centralized logging utility with multiple severity levels.
//
//  Levels:
//  - debug: Detailed debugging information
//  - info: General operational information
//  - warning: Potential issues that don't prevent operation
//  - error: Errors that affect functionality
//
//  Features:
//  - Singleton access: Logger.shared
//  - Recent log history for export
//  - Category-based filtering
//  - Console output in debug builds
//  - File logging configurable per build
//
//  Created: November 11, 2025
//

import Foundation

/// Global logger instance for easy access throughout the application
/// Note: This class is nonisolated to allow logging from any context
final class Logger {

    /// Shared singleton instance
    static let shared = Logger()

    /// Underlying logging service
    private let loggingService: AppLoggingService

    private init() {
        #if DEBUG
        // Enable file logging in debug builds
        self.loggingService = AppLoggingService(maxLogEntries: 1000, enableFileLogging: true)
        #else
        // Disable file logging in release builds for performance
        self.loggingService = AppLoggingService(maxLogEntries: 500, enableFileLogging: false)
        #endif
    }

    // MARK: - Public API

    /// Access to underlying logging service for advanced features
    var service: LoggingService {
        return loggingService
    }

    // MARK: - Logging Methods with Source Detection

    /// Log a debug message (only in DEBUG builds)
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let source = makeSource(file: file, function: function, line: line)
        loggingService.log(level: .debug, message: message, source: source)
        #endif
    }

    /// Log an info message
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let source = makeSource(file: file, function: function, line: line)
        loggingService.log(level: .info, message: message, source: source)
    }

    /// Log a warning message
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let source = makeSource(file: file, function: function, line: line)
        loggingService.log(level: .warning, message: message, source: source)
    }

    /// Log an error message
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let source = makeSource(file: file, function: function, line: line)
        loggingService.log(level: .error, message: message, source: source)
    }

    /// Log a message with custom level
    func log(level: LogLevel, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let source = makeSource(file: file, function: function, line: line)
        loggingService.log(level: level, message: message, source: source)
    }

    // MARK: - Helper Methods

    private func makeSource(file: String, function: String, line: Int) -> String {
        let fileName = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
        // Remove parameter labels from function name for cleaner output
        let cleanFunction = function.components(separatedBy: "(").first ?? function
        return "\(fileName).\(cleanFunction):\(line)"
    }
}

// MARK: - Convenience Functions

/// Log debug message (only in DEBUG builds)
func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.debug(message, file: file, function: function, line: line)
}

/// Log info message
func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.info(message, file: file, function: function, line: line)
}

/// Log warning message
func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.warning(message, file: file, function: function, line: line)
}

/// Log error message
func logError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.error(message, file: file, function: function, line: line)
}

// MARK: - Backward Compatibility with print()

#if DEBUG
/// Debug-only print replacement that uses the logger
/// This allows gradual migration from print() to proper logging
func debugPrint(_ items: Any..., separator: String = " ", file: String = #file, function: String = #function, line: Int = #line) {
    let message = items.map { "\($0)" }.joined(separator: separator)
    Logger.shared.debug(message, file: file, function: function, line: line)
}
#endif

// MARK: - Migration Guide
/*
 MIGRATION GUIDE: From print() to Logger

 OLD CODE:
 ```swift
 print("🔐 Apple ID Sign In:")
 print("  User ID: \(userID)")
 print("❌ Failed to connect: \(error)")
 ```

 NEW CODE:
 ```swift
 logInfo("Apple ID Sign In")
 logInfo("User ID: \(userID)")
 logError("Failed to connect: \(error)")
 ```

 BENEFITS:
 - Automatic source tracking (file, function, line)
 - Log level filtering (debug, info, warning, error)
 - Structured logging with timestamps
 - File logging in debug builds
 - Performance: debug logs are stripped in release builds
 - Searchable and exportable logs

 LOGGING LEVELS:
 - debug: Detailed information for debugging (DEBUG builds only)
 - info: General informational messages
 - warning: Warning messages that don't require immediate action
 - error: Error messages for failures and exceptions

 USAGE EXAMPLES:
 ```swift
 // Simple messages
 logDebug("Starting scan for devices")
 logInfo("Connected to device: \(deviceName)")
 logWarning("Low battery: \(batteryLevel)%")
 logError("Connection failed: \(error.localizedDescription)")

 // Using the singleton directly
 Logger.shared.info("User authenticated successfully")

 // Accessing the service for advanced features
 let logs = Logger.shared.service.logs(withLevel: .error)
 let exportURL = try await Logger.shared.service.exportLogs()
 ```

 PERFORMANCE:
 - Debug logs have zero overhead in release builds (completely stripped)
 - Info/warning/error logs have minimal overhead
 - File logging only enabled in debug builds
 - Asynchronous logging doesn't block main thread
 */
