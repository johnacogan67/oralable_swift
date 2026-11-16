//
//  DualProtocolAExport.swift
//  OralableApp
//
//  Writes TEMPORALIS / ANR_EMG / DUAL_PAIR / session.edf for Mac
//  `align_anr_oralable_concordance.py`. Dual A EDF always includes ANR EMG.
//

import Foundation
import OralableCore

struct DualProtocolAPreflightStats: Equatable, Sendable {
    var passed: Bool
    var emgGate: Double
    var clenchMax: Double
    var clenchMean: Double
    var restMax: Double
}

struct DualProtocolAExportArtifacts: Equatable, Sendable {
    let sessionTimestamp: String
    let temporalisURL: URL
    let anrURL: URL
    let pairURL: URL
    let edfURL: URL?

    var shareURLs: [URL] {
        var urls = [temporalisURL, anrURL, pairURL]
        if let edfURL { urls.append(edfURL) }
        return urls
    }
}

enum DualProtocolAExportError: LocalizedError {
    case emptyOralableLog
    case emptyANRLog
    case edfFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyOralableLog:
            return "No Oralable BLE log captured. Keep the clip streaming during Dual Protocol A."
        case .emptyANRLog:
            return "No ANR EMG samples captured. Re-seat ANR and retry."
        case .edfFailed(let m):
            return "EDF export failed: \(m)"
        }
    }
}

enum DualProtocolAExport {

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let sessionStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()

    static func makeSessionTimestamp(date: Date = Date()) -> String {
        sessionStampFormatter.string(from: date)
    }

    /// Documents/DualProtocolA/<session>/
    static func sessionDirectory(sessionTimestamp: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs
            .appendingPathComponent("DualProtocolA", isDirectory: true)
            .appendingPathComponent(sessionTimestamp, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func writeANRCSV(rows: [(Date, Double)], to url: URL) throws {
        guard !rows.isEmpty else { throw DualProtocolAExportError.emptyANRLog }
        var lines: [String] = ["iso_utc,unix_s,emg_raw"]
        lines.reserveCapacity(rows.count + 1)
        for (date, emg) in rows {
            let iso = isoFormatter.string(from: date)
            let unix = date.timeIntervalSince1970
            lines.append(String(format: "%@,%.6f,%.0f", iso, unix, emg))
        }
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Oralable TEMPORALIS file: nRF Connect CSV (`parse_oralable_log` accepts Updated Value lines).
    static func writeTemporalisLog(from logger: NRFConnectBLELogger = .shared, to url: URL) throws {
        let content = logger.csvContent()
        guard logger.lineCount() > 0, content.contains("\n") else {
            throw DualProtocolAExportError.emptyOralableLog
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func writePairFile(
        to url: URL,
        sessionTimestamp: String,
        temporalisName: String,
        anrName: String,
        oralableID: String,
        anrID: String,
        cueStartUnix: TimeInterval?,
        preflight: DualProtocolAPreflightStats?,
        couple: SingleProtocolACoupleStats? = nil,
        skinTempMeanC: Double? = nil,
        onSkinFraction: Double? = nil,
        edfName: String? = nil
    ) throws {
        var body = """
        session_ts=\(sessionTimestamp)
        oralable=\(temporalisName)
        anr=\(anrName)
        oralable_address=\(oralableID)
        anr_address=\(anrID)
        source=ios_dual_protocol_a
        mam_seat_qc=couple

        """
        if let edfName {
            body += "edf=\(edfName)\n"
        }
        if let cueStartUnix {
            body += String(format: "cue_start_unix=%.6f\n", cueStartUnix)
            body += "# align: default first-sample; use --emg-offset-s if needed\n"
        }
        if let preflight {
            body += """
            emg_preflight_passed=\(preflight.passed ? 1 : 0)
            emg_preflight_gate=\(preflight.emgGate)
            emg_preflight_clench_max=\(preflight.clenchMax)
            emg_preflight_clench_mean=\(preflight.clenchMean)
            emg_preflight_rest_max=\(preflight.restMax)

            """
        }
        if let couple {
            body += """
            couple_preflight_passed=\(couple.passed ? 1 : 0)
            couple=\(couple.coupleRaw.map(String.init) ?? "unknown")
            allow_couple_1=\(couple.allowCouple1 ? 1 : 0)
            couple_pulse=\(couple.pulseLatched ? 1 : 0)

            """
            if let hr = couple.hrBPM {
                body += String(format: "couple_hr=%.1f\n", hr)
            }
            body += "couple_snippet=\(couple.snippet)\n"
        }
        if let skinTempMeanC, skinTempMeanC.isFinite {
            body += String(format: "skin_temp_mean_c=%.2f\n", skinTempMeanC)
        }
        if let onSkinFraction, onSkinFraction.isFinite {
            body += String(format: "on_skin_fraction=%.3f\n", onSkinFraction)
        }
        body += "# EDF+ research Dual A (includes ANR EMG). Not PSG / not AHI.\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Writes Mac-align artifacts + session.edf (with ANR EMG) under Documents/DualProtocolA/<ts>/.
    static func writeSessionPack(
        anrRows: [(Date, Double)],
        oralablePoints: [EDFSessionGrid.Point],
        oralableID: String,
        anrID: String,
        cueStartUnix: TimeInterval?,
        preflight: DualProtocolAPreflightStats?,
        couple: SingleProtocolACoupleStats? = nil,
        sessionTimestamp: String? = nil,
        skinTempSamplesC: [Double] = []
    ) throws -> DualProtocolAExportArtifacts {
        let ts = sessionTimestamp ?? makeSessionTimestamp()
        let dir = try sessionDirectory(sessionTimestamp: ts)
        let temporalisName = "TEMPORALIS_RAW_\(ts).txt"
        let anrName = "ANR_EMG_\(ts).csv"
        let pairName = "DUAL_PAIR_\(ts).txt"
        let edfName = "session.edf"
        let temporalisURL = dir.appendingPathComponent(temporalisName)
        let anrURL = dir.appendingPathComponent(anrName)
        let pairURL = dir.appendingPathComponent(pairName)
        let edfURL = dir.appendingPathComponent(edfName)

        let finiteTemps = skinTempSamplesC.filter(\.isFinite)
        let meanTemp: Double? = finiteTemps.isEmpty
            ? nil
            : finiteTemps.reduce(0, +) / Double(finiteTemps.count)
        let onSkinFrac: Double? = finiteTemps.isEmpty
            ? nil
            : Double(finiteTemps.filter { SensorCorroboration.isLikelyOnSkin(temperatureC: $0) }.count)
                / Double(finiteTemps.count)

        try writeTemporalisLog(to: temporalisURL)
        try writeANRCSV(rows: anrRows, to: anrURL)

        do {
            let built = try EDFSessionGrid.buildChannels(
                oralable: oralablePoints,
                emg: anrRows,
                requireEMG: true
            )
            try EDFWriter.write(
                channels: built.channels,
                annotations: built.annotations,
                to: edfURL,
                startDate: built.start,
                patientId: "DualA \(ts)",
                recordingId: "Startdate Oralable-ANR research",
                requireEMG: true
            )
        } catch {
            throw DualProtocolAExportError.edfFailed(error.localizedDescription)
        }

        try writePairFile(
            to: pairURL,
            sessionTimestamp: ts,
            temporalisName: temporalisName,
            anrName: anrName,
            oralableID: oralableID,
            anrID: anrID,
            cueStartUnix: cueStartUnix,
            preflight: preflight,
            couple: couple,
            skinTempMeanC: meanTemp,
            onSkinFraction: onSkinFrac,
            edfName: edfName
        )

        return DualProtocolAExportArtifacts(
            sessionTimestamp: ts,
            temporalisURL: temporalisURL,
            anrURL: anrURL,
            pairURL: pairURL,
            edfURL: edfURL
        )
    }
}
