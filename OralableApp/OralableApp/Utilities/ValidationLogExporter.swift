//
//  ValidationLogExporter.swift
//  OralableApp
//
//  Protocol B pilot export: nRF Connect–compatible BLE CSV for cursor_oralable self_validate.py
//

import Foundation
import OralableCore

enum ValidationLogExporter {

    /// Filename for Ed/Pedro handoff (`Oralable_PILOT_YYYYMMDD_HHmmss.csv`).
    static func pilotFilename(prefix: String = "Oralable_PILOT") -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd_HHmmss"
        return "\(prefix)_\(df.string(from: Date())).csv"
    }

    /// Writes `NRFConnectBLELogger` CSV (Timestamp, Source, Level, Line) to Documents.
    static func exportNRFConnectLog(filename: String) throws -> URL {
        let content = NRFConnectBLELogger.shared.csvContent()
        guard content.contains("\n"), NRFConnectBLELogger.shared.lineCount() > 0 else {
            throw ValidationLogExportError.emptyLog
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

enum ValidationLogExportError: LocalizedError {
    case emptyLog

    var errorDescription: String? {
        switch self {
        case .emptyLog:
            return "No BLE validation log captured yet. Connect the clip, set Worn on cheek, and stream for at least one minute."
        }
    }
}
