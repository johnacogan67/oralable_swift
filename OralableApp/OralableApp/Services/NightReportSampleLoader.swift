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

    /// Default lookback when recovering an overnight window after auto-session pause expiry.
    static let clinicalExportLookback: TimeInterval = 20 * 3600

    /// Resolve the overnight / clinical sample window.
    ///
    /// After `AutomaticRecordingSession` pause expiry, `sessionStartTime` is cleared while hourly
    /// flush CSVs remain on disk. Preferring only RAM history (~200s) or `startOfDay` silently
    /// drops the overnight stream. Expand the preferred bounds with the last completed auto
    /// session and flush CSV coverage inside `lookback`.
    static func resolveClinicalExportWindow(
        preferredStart: Date,
        preferredEnd: Date,
        lastCompletedAutoStart: Date? = nil,
        lastCompletedAutoEnd: Date? = nil,
        flushBounds: (start: Date, end: Date)? = nil,
        now: Date = Date(),
        lookback: TimeInterval = clinicalExportLookback
    ) -> (start: Date, end: Date) {
        let earliestAllowed = now.addingTimeInterval(-lookback)
        var start = preferredStart
        var end = max(preferredEnd, now)

        if let ls = lastCompletedAutoStart, let le = lastCompletedAutoEnd, le >= earliestAllowed {
            start = min(start, max(ls, earliestAllowed))
            end = max(end, le)
        }
        if let flush = flushBounds {
            start = min(start, max(flush.start, earliestAllowed))
            end = max(end, flush.end)
        }
        if start > end {
            return (earliestAllowed, now)
        }
        return (start, end)
    }

    /// Earliest/latest sample timestamps in flush CSVs within `[now - lookback, now]`.
    static func sampleTimeBounds(
        in flushDirectory: URL = ApplicationSupportPaths.memoryFlushDirectory,
        now: Date = Date(),
        lookback: TimeInterval = clinicalExportLookback
    ) -> (start: Date, end: Date)? {
        let earliestAllowed = now.addingTimeInterval(-lookback)
        let latestAllowed = now.addingTimeInterval(60)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: flushDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var minTs: Date?
        var maxTs: Date?
        for url in urls where url.pathExtension.lowercased() == "csv" {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let bounds = timestampBounds(inCSV: content, start: earliestAllowed, end: latestAllowed)
            if let b = bounds {
                minTs = minTs.map { min($0, b.start) } ?? b.start
                maxTs = maxTs.map { max($0, b.end) } ?? b.end
            }
        }
        guard let start = minTs, let end = maxTs else { return nil }
        return (start, end)
    }

    /// Public for unit tests — timestamp-only scan (avoids allocating full night samples).
    static func timestampBounds(
        inCSV content: String,
        start: Date,
        end: Date
    ) -> (start: Date, end: Date)? {
        let lines = content.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        guard lines.count > 1 else { return nil }
        let header = lines[0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let map = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        guard let tsIdx = map["iso8601_timestamp"] ?? map["timestamp"] else { return nil }

        let fmtFrac = ISO8601DateFormatter()
        fmtFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]

        var minTs: Date?
        var maxTs: Date?
        for line in lines.dropFirst() {
            let cols = splitCSV(line)
            guard tsIdx < cols.count else { continue }
            guard let ts = fmtFrac.date(from: cols[tsIdx]) ?? fmt.date(from: cols[tsIdx]) else { continue }
            if ts < start || ts > end { continue }
            minTs = minTs.map { min($0, ts) } ?? ts
            maxTs = maxTs.map { max($0, ts) } ?? ts
        }
        guard let lo = minTs, let hi = maxTs else { return nil }
        return (lo, hi)
    }

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
        if let urls = try? FileManager.default.contentsOfDirectory(
            at: flushDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in urls where url.pathExtension.lowercased() == "csv" {
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

    // MARK: - Parsers

    static func parseResearchCSV(at url: URL, start: Date, end: Date) -> [NightReportSample] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parseResearchCSV(content: content, start: start, end: end)
    }

    /// Public for unit tests — ResearchRawDataExport header.
    static func parseResearchCSV(content: String, start: Date, end: Date) -> [NightReportSample] {
        let lines = content.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
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
        out.reserveCapacity(lines.count - 1)
        for line in lines.dropFirst() {
            let cols = splitCSV(line)
            guard tsIdx < cols.count, irIdx < cols.count else { continue }
            let tsStr = cols[tsIdx]
            guard let ts = fmtFrac.date(from: tsStr) ?? fmt.date(from: tsStr) else { continue }
            if ts < start || ts > end { continue }
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
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = content.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
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
            if ts < start || ts > end { continue }
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

    private static func splitCSV(_ line: String) -> [String] {
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
