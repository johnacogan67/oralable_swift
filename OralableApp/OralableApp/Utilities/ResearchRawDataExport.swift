//
//  ResearchRawDataExport.swift
//  OralableApp
//
//  Raw 50 Hz lane CSV for REV10 / dual-stream exports (no UIKit).
//

import Foundation
import OralableCore

enum ResearchRawDataExport {

    /// One row per `SensorData` sample (deviceType, ISO8601 timestamp, PPG RGB raw, accel raw, optional HR/SpO2).
    /// `ambient_ir_raw` duplicates `ir` (REV10 IR-DC counts) for leakage / ambient-saturation analysis (e.g. McGill).
    /// `is_manual_override` is `1` when the fit gate was bypassed via research override for that export (otherwise `0`).
    static func writeOralableRaw50HzCSV(samples: [SensorData], to url: URL, isManualOverride: Bool = false) throws {
        var lines: [String] = []
        lines.reserveCapacity(samples.count + 1)
        let overrideFlag = isManualOverride ? "1" : "0"
        lines.append("device_type,iso8601_timestamp,red,ir,ambient_ir_raw,green,accel_x,accel_y,accel_z,temp_celsius,battery_percent,heart_rate_bpm,spo2_percent,is_manual_override,hrv_ms")
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for s in samples {
            let ts = fmt.string(from: s.timestamp)
            let hr = s.heartRate.map { String(format: "%.1f", $0.bpm) } ?? ""
            let hrv = s.heartRate?.hrvMs.map { String(format: "%.1f", $0) } ?? ""
            let ox = s.spo2.map { String(format: "%.0f", $0.percentage) } ?? ""
            let row = [
                s.deviceType.rawValue,
                ts,
                "\(s.ppg.red)",
                "\(s.ppg.ir)",
                "\(s.ppg.ir)",
                "\(s.ppg.green)",
                "\(s.accelerometer.x)",
                "\(s.accelerometer.y)",
                "\(s.accelerometer.z)",
                String(format: "%.3f", s.temperature.celsius),
                "\(s.battery.percentage)",
                hr,
                ox,
                overrideFlag,
                hrv
            ].joined(separator: ",")
            lines.append(row)
        }
        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw NSError(domain: "ResearchRawDataExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "UTF-8 encoding failed"])
        }
        try data.write(to: url, options: .atomic)
    }

    /// Merged night CSV from flush-rebuilt samples. Paper A handoff — not the ~3 min RAM dump.
    static func writeNightReportCSV(samples: [NightReportSample], nightDate: Date, to url: URL? = nil) throws -> URL {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyyMMdd"
        let dest = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("MAM_NIGHT_\(df.string(from: nightDate)).csv")
        var lines: [String] = []
        lines.reserveCapacity(samples.count + 1)
        lines.append("device_type,iso8601_timestamp,ir,accel_x,accel_y,accel_z,spo2_percent,temp_celsius,heart_rate_bpm,hrv_ms")
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for s in samples {
            let spo2 = s.spo2.isFinite ? String(format: "%.0f", s.spo2) : ""
            let temp = s.temperature.isFinite ? String(format: "%.3f", s.temperature) : ""
            let hr = s.heartRateBpm.isFinite ? String(format: "%.1f", s.heartRateBpm) : ""
            let hrv = s.hrvMs.isFinite ? String(format: "%.1f", s.hrvMs) : ""
            lines.append(
                [
                    "oralable",
                    fmt.string(from: s.timestamp),
                    "\(s.ir)",
                    "\(s.accelX)",
                    "\(s.accelY)",
                    "\(s.accelZ)",
                    spo2,
                    temp,
                    hr,
                    hrv
                ].joined(separator: ",")
            )
        }
        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw NSError(domain: "ResearchRawDataExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "UTF-8 encoding failed"])
        }
        try data.write(to: dest, options: .atomic)
        return dest
    }
}
