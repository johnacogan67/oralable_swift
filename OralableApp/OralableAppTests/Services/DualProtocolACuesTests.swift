//
//  DualProtocolACuesTests.swift
//  OralableAppTests
//
//  Cue table timing parity vs Mac PROTOCOL_A_CUES (run_protocol_a_session.py).
//

import XCTest
import OralableCore
@testable import MAMDiagnostics

final class DualProtocolACuesTests: XCTestCase {

    func testSessionDurationIs360() {
        XCTAssertEqual(DualProtocolACues.sessionDurationSeconds, 360)
    }

    func testCueTableMatchesMacTimings() {
        let expected: [(TimeInterval, TimeInterval, String)] = [
            (0, 60, "REST quiet — stay still, jaw relaxed"),
            (60, 70, "FIVE sync taps — firm, rhythmic taps on housing"),
            (70, 120, "REST — settle after taps"),
            (120, 130, "MAX TONIC clench — hold hard 10 s"),
            (130, 180, "REST recovery — release, stay still"),
            (180, 200, "PHASIC grind — rhythmic jaw motion 20 s"),
            (200, 240, "REST — accel baseline"),
            (240, 260, "BREATH HOLD (simulated apnea) — hold breath 20 s"),
            (260, 270, "TONIC RESCUE clench — clench hard 10 s (still holding or just after)"),
            (270, 360, "FINAL recovery — stillness 90 s")
        ]
        XCTAssertEqual(DualProtocolACues.protocolA.count, expected.count)
        for (i, cue) in DualProtocolACues.protocolA.enumerated() {
            XCTAssertEqual(cue.startSeconds, expected[i].0, "cue[\(i)] start")
            XCTAssertEqual(cue.endSeconds, expected[i].1, "cue[\(i)] end")
            XCTAssertEqual(cue.text, expected[i].2, "cue[\(i)] text")
        }
    }

    func testCueLookupAtBoundaries() {
        XCTAssertEqual(DualProtocolACues.cue(at: 0).text, DualProtocolACues.protocolA[0].text)
        XCTAssertEqual(DualProtocolACues.cue(at: 60).text, DualProtocolACues.protocolA[1].text)
        XCTAssertEqual(DualProtocolACues.cue(at: 269.9).text, DualProtocolACues.protocolA[8].text)
        XCTAssertEqual(DualProtocolACues.cue(at: 270).text, DualProtocolACues.protocolA[9].text)
        XCTAssertEqual(DualProtocolACues.cue(at: 359.9).text, DualProtocolACues.protocolA[9].text)
    }

    func testFormatMMSS() {
        XCTAssertEqual(DualProtocolACues.formatMMSS(0), "0:00")
        XCTAssertEqual(DualProtocolACues.formatMMSS(70), "1:10")
        XCTAssertEqual(DualProtocolACues.formatMMSS(360), "6:00")
    }

    func testLinkDropMessageMentionsSenseStop() {
        XCTAssertTrue(DualProtocolASessionController.linkDropMessage.contains("1.0.71"))
        XCTAssertTrue(DualProtocolASessionController.linkDropMessage.contains("stops MAM sensors"))
    }

    func testPreflightDurationsAndGate() {
        XCTAssertEqual(DualProtocolACues.preflightRestSeconds, 10)
        XCTAssertEqual(DualProtocolACues.preflightClenchSeconds, 10)
        XCTAssertEqual(DualProtocolACues.defaultEmgGate, 70)
    }

    func testExportPairFileContainsMacKeys() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DualATest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let pair = dir.appendingPathComponent("DUAL_PAIR_test.txt")
        let stats = DualProtocolAPreflightStats(
            passed: true,
            emgGate: 70,
            clenchMax: 250,
            clenchMean: 180,
            restMax: 12
        )
        try DualProtocolAExport.writePairFile(
            to: pair,
            sessionTimestamp: "20260808_120000",
            temporalisName: "TEMPORALIS_RAW_20260808_120000.txt",
            anrName: "ANR_EMG_20260808_120000.csv",
            oralableID: "oral-id",
            anrID: "anr-id",
            cueStartUnix: 1_700_000_000.5,
            preflight: stats,
            couple: SingleProtocolACoupleStats(
                passed: true,
                coupleRaw: 2,
                allowCouple1: false,
                pulseLatched: true,
                hrBPM: 62,
                snippet: "couple=ok pulse=1 hr=62 still=1"
            ),
            skinTempMeanC: 34.5,
            onSkinFraction: 1.0
        )
        let body = try String(contentsOf: pair, encoding: .utf8)
        XCTAssertTrue(body.contains("cue_start_unix=1700000000.500000"))
        XCTAssertTrue(body.contains("emg_preflight_passed=1"))
        XCTAssertTrue(body.contains("emg_preflight_gate=70.0") || body.contains("emg_preflight_gate=70"))
        XCTAssertTrue(body.contains("mam_seat_qc=couple"))
        XCTAssertTrue(body.contains("couple_preflight_passed=1"))
        XCTAssertTrue(body.contains("couple=2"))
        XCTAssertTrue(body.contains("source=ios_dual_protocol_a"))
        XCTAssertTrue(body.contains("skin_temp_mean_c=34.50"))
        XCTAssertTrue(body.contains("on_skin_fraction=1.000"))
    }

    func testDualCoupleSeatQCTimeoutMatchesSingle() {
        XCTAssertEqual(
            DualProtocolASessionController.couplePreflightTimeoutS,
            SingleProtocolASessionController.couplePreflightTimeoutS,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DualProtocolASessionController.coupleDeskAbortGraceS,
            SingleProtocolASessionController.coupleDeskAbortGraceS,
            accuracy: 0.001
        )
    }

    func testWriteANRCSVHeader() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ANR_EMG_test_\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        try DualProtocolAExport.writeANRCSV(rows: [(t0, 42)], to: url)
        let body = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(body.hasPrefix("iso_utc,unix_s,emg_raw\n"))
        XCTAssertTrue(body.contains(",42\n") || body.contains(",42"))
    }

    func testEDFSessionGridIncludesEMGWhenANRPresent() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let n = 200
        var oral: [EDFSessionGrid.Point] = []
        var emg: [(Date, Double)] = []
        for i in 0..<n {
            let t = t0.addingTimeInterval(Double(i) / 50.0)
            oral.append(.init(time: t, ir: 1_000_000, spo2: 96))
            emg.append((t, 150 + Double(i % 40)))
        }
        let built = try EDFSessionGrid.buildChannels(oralable: oral, emg: emg, requireEMG: true)
        XCTAssertTrue(built.channels.contains { $0.label == EDFExportSpec.channelEMG })
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dual_a_\(UUID().uuidString).edf")
        defer { try? FileManager.default.removeItem(at: url) }
        try EDFWriter.write(
            channels: built.channels,
            annotations: built.annotations,
            to: url,
            startDate: built.start,
            requireEMG: true
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
