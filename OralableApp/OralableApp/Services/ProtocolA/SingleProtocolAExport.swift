//
//  SingleProtocolAExport.swift
//  OralableApp
//
//  Oralable-only Protocol A Setup export (EDF + sidecar). No ANR.
//

import Foundation
import OralableCore

struct SingleProtocolAExportArtifacts: Equatable, Sendable {
    let sessionTimestamp: String
    let edfURL: URL
    let sidecarURL: URL
    let sampleCount: Int
    let sessionStart: Date
    let sessionEnd: Date

    var shareURLs: [URL] { [edfURL, sidecarURL] }
}

enum SingleProtocolAExportError: LocalizedError {
    case emptyOralable
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyOralable:
            return "No Oralable samples captured. Keep BLE linked for the whole Protocol A session."
        case .writeFailed(let m):
            return m
        }
    }
}

enum SingleProtocolAExport {
    static func sessionDirectory(sessionTimestamp: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs
            .appendingPathComponent("ProtocolASetup", isDirectory: true)
            .appendingPathComponent(sessionTimestamp, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func writeSessionPack(
        oralablePoints: [EDFSessionGrid.Point],
        oralableID: String,
        couple: SingleProtocolACoupleStats?,
        sessionTimestamp: String? = nil,
        sessionStart: Date? = nil,
        sessionEnd: Date? = nil
    ) throws -> SingleProtocolAExportArtifacts {
        let stamp = sessionTimestamp ?? DualProtocolAExport.makeSessionTimestamp()
        guard !oralablePoints.isEmpty else { throw SingleProtocolAExportError.emptyOralable }

        let dir = try sessionDirectory(sessionTimestamp: stamp)
        let edfURL = dir.appendingPathComponent("session_\(stamp).edf")
        let sidecarURL = dir.appendingPathComponent("PROTOCOL_A_SETUP_\(stamp).txt")

        let built: (channels: [EDFChannel], annotations: [EDFAnnotation], start: Date)
        do {
            built = try EDFSessionGrid.buildChannels(
                oralable: oralablePoints,
                emg: [],
                requireEMG: false
            )
            try EDFWriter.write(
                channels: built.channels,
                annotations: built.annotations,
                to: edfURL,
                startDate: built.start,
                patientId: "Oralable \(stamp)",
                recordingId: "Startdate Protocol A Setup",
                requireEMG: false
            )
        } catch {
            throw SingleProtocolAExportError.writeFailed(error.localizedDescription)
        }

        let start = sessionStart ?? oralablePoints.map(\.time).min() ?? built.start
        let end = sessionEnd ?? oralablePoints.map(\.time).max() ?? Date()

        var lines: [String] = [
            "protocol=single_mam_protocol_a_setup",
            "session=\(stamp)",
            "oralable_id=\(oralableID)",
            "edf=\(edfURL.lastPathComponent)",
            "sample_count=\(oralablePoints.count)",
            "wellness_only=1",
            "seat_qc=couple"
        ]
        if let couple {
            lines.append("couple_preflight_passed=\(couple.passed ? 1 : 0)")
            lines.append("couple=\(couple.coupleRaw.map(String.init) ?? "unknown")")
            lines.append("allow_couple_1=\(couple.allowCouple1 ? 1 : 0)")
            lines.append("couple_pulse=\(couple.pulseLatched ? 1 : 0)")
            if let hr = couple.hrBPM {
                lines.append(String(format: "couple_hr=%.1f", hr))
            }
            lines.append("couple_snippet=\(couple.snippet)")
        }
        try lines.joined(separator: "\n").appending("\n").write(to: sidecarURL, atomically: true, encoding: .utf8)

        return SingleProtocolAExportArtifacts(
            sessionTimestamp: stamp,
            edfURL: edfURL,
            sidecarURL: sidecarURL,
            sampleCount: oralablePoints.count,
            sessionStart: start,
            sessionEnd: end
        )
    }

    /// Share URLs for an on-disk Setup pack (Documents/ProtocolASetup/<stamp>/).
    static func shareURLs(sessionTimestamp: String) -> [URL]? {
        guard let dir = try? sessionDirectory(sessionTimestamp: sessionTimestamp) else { return nil }
        let edf = dir.appendingPathComponent("session_\(sessionTimestamp).edf")
        let sidecar = dir.appendingPathComponent("PROTOCOL_A_SETUP_\(sessionTimestamp).txt")
        let fm = FileManager.default
        guard fm.fileExists(atPath: edf.path), fm.fileExists(atPath: sidecar.path) else { return nil }
        return [edf, sidecar]
    }
}
