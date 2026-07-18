//
//  NRFConnectBLELogger.swift
//  OralableApp
//
//  Captures nRF Connect-style BLE session logs for developer diagnostics.
//

import Foundation

enum NRFConnectBLELogSource: String {
    case scanner = "Scanner"
    case central = "Central"
    case connectedDevice = "Connected Device"
}

enum NRFConnectBLELogLevel: String {
    case application = "Application"
    case info = "Info"
    case debug = "Debug"
}

final class NRFConnectBLELogger {
    static let shared = NRFConnectBLELogger()

    private struct Entry {
        let timestamp: Date
        let source: NRFConnectBLELogSource
        let level: NRFConnectBLELogLevel
        let line: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var lastValueLogByCharacteristic: [String: Date] = [:]
    private var highRateNotificationsAreThrottled = true

    /// Keep the diagnostic buffer bounded even if firmware emits verbose logs for a long session.
    private let maxEntries = 50_000
    private let throttledValueLogInterval: TimeInterval = 1

    private lazy var timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var throttleHighRateNotifications: Bool {
        get {
            lock.withLock { highRateNotificationsAreThrottled }
        }
        set {
            lock.withLock { highRateNotificationsAreThrottled = newValue }
        }
    }

    private init() {}

    func clear() {
        lock.withLock {
            entries.removeAll(keepingCapacity: true)
            lastValueLogByCharacteristic.removeAll(keepingCapacity: true)
        }
    }

    func lineCount() -> Int {
        lock.withLock { entries.count }
    }

    func scannerOn() {
        log(source: .scanner, level: .application, line: "Scanner On")
    }

    func scannerOff() {
        log(source: .scanner, level: .application, line: "Scanner Off")
    }

    func deviceScanned() {
        log(source: .scanner, level: .application, line: "Device Scanned")
    }

    func connected() {
        log(source: .central, level: .application, line: "Connected")
    }

    func disconnected() {
        log(source: .central, level: .application, line: "Disconnected")
    }

    func discoveredServices(_ serviceUUIDs: [String]) {
        log(
            source: .connectedDevice,
            level: .application,
            line: "Services discovered: \(serviceUUIDs.joined(separator: ", "))"
        )
    }

    func serviceDiscoveryReturnedNil() {
        log(source: .connectedDevice, level: .debug, line: "Discovering characteristics for TGM service")
    }

    func discoveredCharacteristics(_ characteristicUUIDs: [String], forService serviceUUID: String) {
        log(
            source: .connectedDevice,
            level: .application,
            line: "Characteristics discovered for \(serviceUUID): \(characteristicUUIDs.joined(separator: ", "))"
        )
    }

    func discoveredCCC(for characteristicUUID: String) {
        log(
            source: .connectedDevice,
            level: .application,
            line: "Client Characteristic Configuration found for \(characteristicUUID)"
        )
    }

    func characteristicHasNoDescriptors(_ characteristicUUID: String) {
        log(
            source: .connectedDevice,
            level: .debug,
            line: "No descriptors found for \(characteristicUUID)"
        )
    }

    func settingNotify(_ enabled: Bool, for characteristicUUID: String) {
        log(
            source: .connectedDevice,
            level: .application,
            line: "Setting notify \(enabled ? "enabled" : "disabled") for \(characteristicUUID)"
        )
    }

    func updatedValue(of characteristicUUID: String, data: Data) {
        let now = Date()
        let shouldLog = lock.withLock {
            guard highRateNotificationsAreThrottled else {
                lastValueLogByCharacteristic[characteristicUUID] = now
                return true
            }

            if let last = lastValueLogByCharacteristic[characteristicUUID],
               now.timeIntervalSince(last) < throttledValueLogInterval {
                return false
            }

            lastValueLogByCharacteristic[characteristicUUID] = now
            return true
        }

        guard shouldLog else { return }

        log(
            source: .connectedDevice,
            level: .application,
            line: "Value updated for \(characteristicUUID): \(data.hexString)"
        )
    }

    func log(source: NRFConnectBLELogSource, level: NRFConnectBLELogLevel, line: String) {
        let entry = Entry(timestamp: Date(), source: source, level: level, line: line)
        lock.withLock {
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
        }
    }

    func csvContent() -> String {
        let snapshot = lock.withLock { entries }
        var csv = "Timestamp,Source,Level,Line\n"
        for entry in snapshot {
            csv += [
                timestampFormatter.string(from: entry.timestamp),
                entry.source.rawValue,
                entry.level.rawValue,
                entry.line
            ]
            .map(csvEscape)
            .joined(separator: ",")
            csv += "\n"
        }
        return csv
    }

    func exportToFile() throws -> URL {
        let fileName = "nrf_connect_ble_log_\(fileTimestamp()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csvContent().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
