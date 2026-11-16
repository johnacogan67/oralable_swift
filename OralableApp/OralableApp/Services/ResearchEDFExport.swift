//
//  ResearchEDFExport.swift
//  OralableApp
//
//  Oralable-only research EDF+ (no ANR). Dual A uses DualProtocolAExport.
//

import Foundation
import OralableCore

enum ResearchEDFExportError: LocalizedError {
    case emptyHistory
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyHistory: return "No Oralable samples in history to export."
        case .writeFailed(let m): return m
        }
    }
}

enum ResearchEDFExport {
    /// Write Oralable-only session.edf (no EMG channel).
    static func writeOralableOnly(
        from history: [SensorData],
        to directory: URL? = nil
    ) throws -> URL {
        let oralable = history.filter { $0.deviceType == .oralable }
        guard oralable.count >= Int(EDFExportSpec.sampleRateHz) else {
            throw ResearchEDFExportError.emptyHistory
        }
        let points: [EDFSessionGrid.Point] = oralable.map { row in
            .init(
                time: row.timestamp,
                red: Double(row.ppg.red),
                ir: Double(row.ppg.ir),
                green: Double(row.ppg.green),
                accX: Double(row.accelerometer.x),
                accY: Double(row.accelerometer.y),
                accZ: Double(row.accelerometer.z),
                spo2: row.spo2.map { Double($0.percentage) }
            )
        }
        let built = try EDFSessionGrid.buildChannels(oralable: points, emg: [], requireEMG: false)
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ResearchEDF", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = DualProtocolAExport.makeSessionTimestamp()
        let url = dir.appendingPathComponent("session_\(stamp).edf")
        do {
            try EDFWriter.write(
                channels: built.channels,
                annotations: built.annotations,
                to: url,
                startDate: built.start,
                patientId: "Oralable \(stamp)",
                recordingId: "Startdate Oralable research",
                requireEMG: false
            )
        } catch {
            throw ResearchEDFExportError.writeFailed(error.localizedDescription)
        }
        return url
    }
}
