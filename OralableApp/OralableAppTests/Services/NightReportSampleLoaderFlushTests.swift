//
//  NightReportSampleLoaderFlushTests.swift
//  OralableAppTests
//
//  Guards MemoryFlush CSV selection so overnight morning reports do not parse every
//  historical flush file in Application Support (jetsam / watchdog risk).
//

import XCTest
@testable import OralableApp
import OralableCore

final class NightReportSampleLoaderFlushTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("night_flush_loader_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try super.tearDownWithError()
    }

    func testFlushFileMayOverlapSessionUsesModificationDate() throws {
        let sessionStart = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionEnd = sessionStart.addingTimeInterval(8 * 3600)

        let inWindow = tempDir.appendingPathComponent("oralable_unified_flush_in.csv")
        try "device_type,iso8601_timestamp,ir\n".write(to: inWindow, atomically: true, encoding: .utf8)
        try setModificationDate(sessionStart.addingTimeInterval(2 * 3600), for: inWindow)

        let oldNight = tempDir.appendingPathComponent("oralable_unified_flush_old.csv")
        try "device_type,iso8601_timestamp,ir\n".write(to: oldNight, atomically: true, encoding: .utf8)
        try setModificationDate(sessionStart.addingTimeInterval(-48 * 3600), for: oldNight)

        XCTAssertTrue(
            NightReportSampleLoader.flushFileMayOverlapSession(
                url: inWindow,
                sessionStart: sessionStart,
                sessionEnd: sessionEnd
            )
        )
        XCTAssertFalse(
            NightReportSampleLoader.flushFileMayOverlapSession(
                url: oldNight,
                sessionStart: sessionStart,
                sessionEnd: sessionEnd
            )
        )
    }

    func testLoadSkipsStaleFlushFilesByMtime() throws {
        let sessionStart = Date(timeIntervalSince1970: 1_700_100_000)
        let sessionEnd = sessionStart.addingTimeInterval(3600)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Stale prior-night file with rows that would match the session window if parsed.
        // mtime gate must skip it so multi-night Application Support dirs cannot explode memory.
        let stale = tempDir.appendingPathComponent("oralable_unified_flush_stale.csv")
        let staleTS = fmt.string(from: sessionStart.addingTimeInterval(30))
        let staleCSV = """
        device_type,iso8601_timestamp,red,ir,ambient_ir_raw,green,accel_x,accel_y,accel_z,temp_celsius,battery_percent,heart_rate_bpm,spo2_percent,is_manual_override
        oralable,\(staleTS),1000,111111,111111,800,0,0,16384,36.5,90,,98,0
        """
        try staleCSV.write(to: stale, atomically: true, encoding: .utf8)
        try setModificationDate(sessionStart.addingTimeInterval(-72 * 3600), for: stale)

        let fresh = tempDir.appendingPathComponent("oralable_unified_flush_fresh.csv")
        let freshTS = fmt.string(from: sessionStart.addingTimeInterval(60))
        let freshCSV = """
        device_type,iso8601_timestamp,red,ir,ambient_ir_raw,green,accel_x,accel_y,accel_z,temp_celsius,battery_percent,heart_rate_bpm,spo2_percent,is_manual_override
        oralable,\(freshTS),1000,222222,222222,800,0,0,16384,36.5,90,,97,0
        """
        try freshCSV.write(to: fresh, atomically: true, encoding: .utf8)
        try setModificationDate(sessionStart.addingTimeInterval(120), for: fresh)

        let samples = NightReportSampleLoader.load(
            sessionStart: sessionStart,
            sessionEnd: sessionEnd,
            liveHistory: [],
            sessionFileURL: nil,
            flushDirectory: tempDir
        )

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].ir, 222_222, accuracy: 0.1)
    }

    func testParseResearchCSVStopsAfterSessionEnd() {
        let start = Date(timeIntervalSince1970: 1_700_200_000)
        let end = start.addingTimeInterval(1)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let csv = """
        device_type,iso8601_timestamp,red,ir,ambient_ir_raw,green,accel_x,accel_y,accel_z,temp_celsius,battery_percent,heart_rate_bpm,spo2_percent,is_manual_override
        oralable,\(fmt.string(from: start.addingTimeInterval(0.2))),1000,100000,100000,800,0,0,16384,36.5,90,,98,0
        oralable,\(fmt.string(from: start.addingTimeInterval(0.5))),1000,200000,200000,800,0,0,16384,36.5,90,,97,0
        oralable,\(fmt.string(from: start.addingTimeInterval(5.0))),1000,300000,300000,800,0,0,16384,36.5,90,,96,0
        """

        let samples = NightReportSampleLoader.parseResearchCSV(content: csv, start: start, end: end)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[1].ir, 200_000, accuracy: 0.1)
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
