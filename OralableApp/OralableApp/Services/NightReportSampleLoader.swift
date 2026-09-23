//
//  NightReportSampleLoader.swift
//  OralableApp
//
//  Rebuilds a session sample stream from memory-flush CSVs + RAM history + session file
//  for overnight night-report classification (SensorDataProcessor keeps only ~10k RAM rows).
//

import Foundation
import OralableCore

enum NightReportSampleLoader {

    /// Extra wall-clock margin around the session window when using file mtimes.
    /// Hourly flushes are named/written at spill time (end of their ring window).
    static let flushFileTimeSlack: TimeInterval = 3600

    /// Load samples overlapping `[sessionStart, sessionEnd]` from flush CSVs, live history, and optional session CSV.
    static func load(
        sessionStart: Date,
        sessionEnd: Date,
        liveHistory: [SensorData],
        sessionFileURL: URL? = nil,
        flushDirectory: URL = ApplicationSupportPaths.memoryFlushDirectory
    ) -> [NightReportSample] {
        var samples: [NightReportSample] = []

        // 1) Memory flush CSVs (ResearchRawDataExport format)
        // Skip files by mtime outside the session window. The directory is never pruned, so
        // multi-night wear accumulates ~150–200MB+/night; String(contentsOf:) of every CSV
        // before time-filtering jetsams the process when Dashboard/Share builds the morning report.
        if let urls = try? FileManager.default.contentsOfDirectory(
            at: flushDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in urls where url.pathExtension.lowercased() == "csv" {
                guard flushFileMayOverlapSession(
                    url: url,
                    sessionStart: sessionStart,
                    sessionEnd: sessionEnd
                ) else {
                    continue
                }
                samples.append(contentsOf: parseResearchCSV(at: url, start: sessionStart, end: sessionEnd))
            }
        }

        // 2) Live RAM history
        for s in liveHistory where s.timestamp >= sessionStart && s.timestamp <= sessionEnd {
            samples.append(NightReportSample(sensor: s))
        }

        // 3) Session data file fallback
        if let sessionFileURL {
            samples.append(contentsOf: parseResearchCSV(at: sessionFileURL, start: sessionStart, end: sessionEnd))
            // Also try ShareView-style session CSVs with looser column names
            if samples.isEmpty {
                samples.append(contentsOf: parseLooseSessionCSV(at: sessionFileURL, start: sessionStart, end: sessionEnd))
            }
        }

        samples.sort { $0.timestamp < $1.timestamp }
        return dedupe(samples)
    }

    /// True when a flush CSV's modification time could overlap `[sessionStart, sessionEnd]` (with slack).
    /// Public for unit tests.
    static func flushFileMayOverlapSession(
        url: URL,
        sessionStart: Date,
        sessionEnd: Date,
        slack: TimeInterval = flushFileTimeSlack
    ) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modified = values?.contentModificationDate else {
            // Unknown mtime: keep the file and let row timestamps decide.
            return true
        }
        let earliest = sessionStart.addingTimeInterval(-slack)
        let latest = sessionEnd.addingTimeInterval(slack)
        return modified >= earliest && modified <= latest
    }

    // MARK: - Parsers

    static func parseResearchCSV(at url: URL, start: Date, end: Date) -> [NightReportSample] {
        // Prefer mmap so multi-10MB hourly flushes are not fully copied into a contiguous String up front.
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseResearchCSV(content: content, start: start, end: end)
    }

    /// Public for unit tests — ResearchRawDataExport header.
    static func parseResearchCSV(content: String, start: Date, end: Date) -> [NightReportSample] {
        // Keep Substring line views — avoid allocating a String per 50 Hz row before the time filter.
        let lines = content.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }
        let header = lines[0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let map = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        guard let tsIdx = map["iso8601_timestamp"] ?? map["timestamp"],
              let irIdx = map["ir"] ?? map["ambient_ir_raw"] else {
            return []
        }
        let axIdx = map["accel_x"]
        let ayIdx = map["accel_y"]
        let azIdx = map["accel_z"]
        let spo2Idx = map["spo2_percent"]

        let fmtFrac = ISO8601DateFormatter()
        fmtFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]

        var out: [NightReportSample] = []
        out.reserveCapacity(min(lines.count - 1, 4_096))
        for line in lines.dropFirst() {
            let cols = splitCSV(line)
            guard tsIdx < cols.count, irIdx < cols.count else { continue }
            let tsStr = cols[tsIdx]
            guard let ts = fmtFrac.date(from: tsStr) ?? fmt.date(from: tsStr) else { continue }
            // Flush CSVs are chronological; once past the window we can stop.
            if ts < start { continue }
            if ts > end { break }
            let ir = Double(cols[irIdx]) ?? 0
            let ax = axIdx.flatMap { $0 < cols.count ? Double(cols[$0]) : nil } ?? 0
            let ay = ayIdx.flatMap { $0 < cols.count ? Double(cols[$0]) : nil } ?? 0
            let az = azIdx.flatMap { $0 < cols.count ? Double(cols[$0]) : nil } ?? 0
            let spo2 = spo2Idx.flatMap { $0 < cols.count ? Double(cols[$0]) : nil } ?? .nan
            out.append(
                NightReportSample(
                    timestamp: ts,
                    ir: ir,
                    accelX: ax,
                    accelY: ay,
                    accelZ: az,
                    spo2: spo2
                )
            )
        }
        return out
    }

    private static func parseLooseSessionCSV(at url: URL, start: Date, end: Date) -> [NightReportSample] {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        let lines = content.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }
        let header = lines[0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let map = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        let tsKey = ["iso8601_timestamp", "timestamp", "time", "datetime"].first { map[$0] != nil }
        let irKey = ["ir", "ppg_ir", "infrared", "ambient_ir_raw"].first { map[$0] != nil }
        guard let tsKey, let irKey, let tsIdx = map[tsKey], let irIdx = map[irKey] else { return [] }

        let fmtFrac = ISO8601DateFormatter()
        fmtFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]

        var out: [NightReportSample] = []
        for line in lines.dropFirst() {
            let cols = splitCSV(line)
            guard tsIdx < cols.count, irIdx < cols.count else { continue }
            guard let ts = fmtFrac.date(from: cols[tsIdx]) ?? fmt.date(from: cols[tsIdx]) else { continue }
            if ts < start { continue }
            if ts > end { break }
            out.append(
                NightReportSample(
                    timestamp: ts,
                    ir: Double(cols[irIdx]) ?? 0,
                    accelX: map["accel_x"].flatMap { $0 < cols.count ? Double(cols[$0]) : nil } ?? 0,
                    accelY: map["accel_y"].flatMap { $0 < cols.count ? Double(cols[$0]) : nil } ?? 0,
                    accelZ: map["accel_z"].flatMap { $0 < cols.count ? Double(cols[$0]) : nil } ?? 0,
                    spo2: map["spo2_percent"].flatMap { $0 < cols.count ? Double(cols[$0]) : nil }
                        ?? map["spo2"].flatMap { $0 < cols.count ? Double(cols[$0]) : nil }
                        ?? .nan
                )
            )
        }
        return out
    }

    private static func splitCSV(_ line: Substring) -> [String] {
        // Research export is simple CSV without embedded commas in fields.
        line.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func dedupe(_ samples: [NightReportSample]) -> [NightReportSample] {
        guard !samples.isEmpty else { return [] }
        var out: [NightReportSample] = []
        out.reserveCapacity(samples.count)
        var lastT: TimeInterval = -1
        for s in samples {
            let t = s.timestamp.timeIntervalSince1970
            if lastT >= 0, abs(t - lastT) < 0.005 { continue }
            out.append(s)
            lastT = t
        }
        return out
    }
}
