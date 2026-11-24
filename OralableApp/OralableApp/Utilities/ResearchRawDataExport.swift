//
//  ResearchRawDataExport.swift
//  OralableApp
//
//  Raw 50 Hz lane CSV for REV10 / dual-stream exports (no UIKit).
//

import Foundation
import OralableCore

enum ResearchRawDataExport {

    /// Dot decimal, no grouping. `String(format:)` without a locale follows the phone
    /// region, and `NightReportSampleLoader` splits on every comma. A French "36,500"
    /// then shifts SpO₂ onto the heart-rate field (floor 85, false all-night SASHB).
    static func csvNumber(_ value: Double, fractionDigits: Int) -> String {
        String(format: "%.\(fractionDigits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

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
            let hr = s.heartRate.map { csvNumber($0.bpm, fractionDigits: 1) } ?? ""
            let hrv = s.heartRate?.hrvMs.map { csvNumber($0, fractionDigits: 1) } ?? ""
            let ox = s.spo2.map { csvNumber($0.percentage, fractionDigits: 0) } ?? ""
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
                csvNumber(s.temperature.celsius, fractionDigits: 3),
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
            let spo2 = s.spo2.isFinite ? csvNumber(s.spo2, fractionDigits: 0) : ""
            let temp = s.temperature.isFinite ? csvNumber(s.temperature, fractionDigits: 3) : ""
            let hr = s.heartRateBpm.isFinite ? csvNumber(s.heartRateBpm, fractionDigits: 1) : ""
            let hrv = s.hrvMs.isFinite ? csvNumber(s.hrvMs, fractionDigits: 1) : ""
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
