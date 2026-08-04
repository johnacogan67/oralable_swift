//
//  ClinicalExportWindowTests.swift
//  OralableAppTests
//
//  After automatic-session pause expiry, overnight hypnogram / clinical PDF export must not
//  collapse the overnight window to RAM history (~200s) or start-of-day.
//

import XCTest
@testable import OralableApp

final class ClinicalExportWindowTests: XCTestCase {

    func testExpandWindowWithLastCompletedAutoSession() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Morning reconnect started a fresh auto session at 08:00.
        let morningStart = now.addingTimeInterval(-2 * 3600)
        // Overnight session ended after pause expiry.
        let nightStart = now.addingTimeInterval(-12 * 3600)
        let nightEnd = now.addingTimeInterval(-3 * 3600)

        let resolved = NightReportSampleLoader.resolveClinicalExportWindow(
            preferredStart: morningStart,
            preferredEnd: now,
            lastCompletedAutoStart: nightStart,
            lastCompletedAutoEnd: nightEnd,
            flushBounds: nil,
            now: now
        )

        XCTAssertEqual(resolved.start, nightStart)
        XCTAssertEqual(resolved.end, now)
    }

    func testExpandWindowWithFlushBoundsAfterPauseExpiry() {
        let now = Date(timeIntervalSince1970: 1_700_010_000)
        // Fallback after sessionStartTime cleared: recent RAM history only (~200s).
        let historyFirst = now.addingTimeInterval(-180)
        let flushStart = now.addingTimeInterval(-10 * 3600)
        let flushEnd = now.addingTimeInterval(-1 * 3600)

        let resolved = NightReportSampleLoader.resolveClinicalExportWindow(
            preferredStart: historyFirst,
            preferredEnd: now,
            lastCompletedAutoStart: nil,
            lastCompletedAutoEnd: nil,
            flushBounds: (flushStart, flushEnd),
            now: now
        )

        XCTAssertEqual(resolved.start, flushStart)
        XCTAssertEqual(resolved.end, now)
    }

    func testStartOfDayFallbackExpandedByPreMidnightFlush() {
        // Fixed noon anchor so Calendar/timezone cannot push flushStart outside lookback.
        let now = Date(timeIntervalSince1970: 1_700_000_000 + 12 * 3600)
        let startOfDay = now.addingTimeInterval(-12 * 3600)
        let flushStart = startOfDay.addingTimeInterval(-2 * 3600) // prior evening
        let flushEnd = startOfDay.addingTimeInterval(7 * 3600)

        let resolved = NightReportSampleLoader.resolveClinicalExportWindow(
            preferredStart: startOfDay,
            preferredEnd: now,
            flushBounds: (flushStart, flushEnd),
            now: now
        )

        XCTAssertEqual(resolved.start, flushStart)
        XCTAssertGreaterThanOrEqual(resolved.end, flushEnd)
    }

    func testTimestampBoundsScansResearchCSV() {
        let t0 = Date(timeIntervalSince1970: 1_700_030_000)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let t1 = t0.addingTimeInterval(3600)
        let csv = """
        device_type,iso8601_timestamp,red,ir,ambient_ir_raw,green,accel_x,accel_y,accel_z,temp_celsius,battery_percent,heart_rate_bpm,spo2_percent,is_manual_override
        oralable,\(fmt.string(from: t0)),1000,200000,200000,800,0,0,16384,36.5,90,72,98,0
        oralable,\(fmt.string(from: t1)),1000,150000,150000,800,200,0,16384,36.5,90,72,91,0
        """
        let bounds = NightReportSampleLoader.timestampBounds(
            inCSV: csv,
            start: t0.addingTimeInterval(-10),
            end: t1.addingTimeInterval(10)
        )
        XCTAssertEqual(bounds?.start, t0)
        XCTAssertEqual(bounds?.end, t1)
    }

    func testSampleTimeBoundsFromFlushDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clinical_export_flush_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let now = Date(timeIntervalSince1970: 1_700_040_000)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let t0 = now.addingTimeInterval(-8 * 3600)
        let t1 = now.addingTimeInterval(-1 * 3600)
        let csv = """
        device_type,iso8601_timestamp,red,ir,ambient_ir_raw,green,accel_x,accel_y,accel_z,temp_celsius,battery_percent,heart_rate_bpm,spo2_percent,is_manual_override
        oralable,\(fmt.string(from: t0)),1000,200000,200000,800,0,0,16384,36.5,90,72,98,0
        oralable,\(fmt.string(from: t1)),1000,150000,150000,800,200,0,16384,36.5,90,72,91,0
        """
        try csv.write(
            to: tmp.appendingPathComponent("oralable_processor_flush_1.csv"),
            atomically: true,
            encoding: .utf8
        )

        let bounds = NightReportSampleLoader.sampleTimeBounds(in: tmp, now: now, lookback: 20 * 3600)
        XCTAssertEqual(bounds?.start.timeIntervalSince1970 ?? 0, t0.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(bounds?.end.timeIntervalSince1970 ?? 0, t1.timeIntervalSince1970, accuracy: 0.001)

        let resolved = NightReportSampleLoader.resolveClinicalExportWindow(
            preferredStart: now.addingTimeInterval(-120),
            preferredEnd: now,
            flushBounds: bounds,
            now: now
        )
        XCTAssertEqual(resolved.start.timeIntervalSince1970, t0.timeIntervalSince1970, accuracy: 0.001)
    }
}
