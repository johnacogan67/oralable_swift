//
//  ClinicalReportGenerator.swift
//  OralableApp
//
//  Single-page PDF: Oralable MAM: Clinical Temporalis Report
//

import UIKit
import OralableCore

struct ClinicalReportPatientMetadata {
    var ageYears: Int?
    var weightKg: Double?
    var heightCm: Double?

    var bmi: Double? {
        guard let w = weightKg, let h = heightCm, h > 0 else { return nil }
        let m = h / 100.0
        return w / (m * m)
    }

    static func loadFromUserDefaults() -> ClinicalReportPatientMetadata {
        let age = UserDefaults.standard.object(forKey: "OralableClinical.ageYears") as? Int
        let weight = UserDefaults.standard.object(forKey: "OralableClinical.weightKg") as? Double
        let height = UserDefaults.standard.object(forKey: "OralableClinical.heightCm") as? Double
        return ClinicalReportPatientMetadata(ageYears: age, weightKg: weight, heightCm: height)
    }
}

struct ClinicalReportPayload {
    var patient: ClinicalReportPatientMetadata
    /// Display name for trial PDF header (e.g. Apple ID or entered name).
    var patientName: String
    /// Calendar date of the sleep/study session (anchor for Ed/Pedro review).
    var dateOfStudy: Date
    /// Six-character clinician handshake code (or CloudKit share prefix).
    var clinicianSyncCode: String
    /// Pearson r between hourly hypoxic burden (SASHB) and hourly rescue fraction (smoking gun proxy).
    var spO2ClenchCorrelation: Double?
    var tfiPercent: Double
    var generatedAt: Date
}

enum ClinicalReportGenerator {
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

    static func smokingGunCorrelation(hourly: [HourlyTemporalisSegment]) -> Double? {
        guard hourly.count >= 3 else { return nil }
        let x = hourly.map { $0.sashbHypoxicBurden }
        let y = hourly.map { rescueFraction($0) }
        return pearson(x, y)
    }

    private static func rescueFraction(_ h: HourlyTemporalisSegment) -> Double {
        let denom = max(1e-6, h.quiet + h.phasic + h.tonic + h.rescue)
        return h.rescue / denom
    }

    private static func pearson(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, a.count >= 3 else { return nil }
        let n = Double(a.count)
        let meanA = a.reduce(0, +) / n
        let meanB = b.reduce(0, +) / n
        var num = 0.0, denA = 0.0, denB = 0.0
        for i in 0..<a.count {
            let da = a[i] - meanA
            let db = b[i] - meanB
            num += da * db
            denA += da * da
            denB += db * db
        }
        let den = sqrt(denA * denB)
        guard den > 1e-12 else { return nil }
        return num / den
    }

    static func renderPDF(payload: ClinicalReportPayload) -> Data? {
        let fmt: (Double) -> String = { String(format: "%.3f", $0) }
        let studyDateFormatter = DateFormatter()
        studyDateFormatter.dateStyle = .long
        studyDateFormatter.timeStyle = .none

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let banner = "CONFIDENTIAL RESEARCH DATA: McGill/Beacon Clinical Trial"
            let title = "Oralable MAM: Clinical Temporalis Report"
            let attributesBanner: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
            ]
            let attributesTitle: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold)
            ]
            let attributesBody: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular)
            ]
            let attributesHeaderLabel: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold)
            ]
            let attributesHeaderValue: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold)
            ]
            var y: CGFloat = 40
            banner.draw(at: CGPoint(x: 48, y: y), withAttributes: attributesBanner)
            y += 22
            title.draw(at: CGPoint(x: 48, y: y), withAttributes: attributesTitle)
            y += 26

            let studyStr = studyDateFormatter.string(from: payload.dateOfStudy)
            let sync = payload.clinicianSyncCode.isEmpty ? "—" : payload.clinicianSyncCode.uppercased()
            let headerLines: [(String, String)] = [
                ("Patient Name", payload.patientName.isEmpty ? "—" : payload.patientName),
                ("Date of Study", studyStr),
                ("Clinician Sync Code", sync)
            ]
            let headerBoxTop = y
            let headerHeight: CGFloat = CGFloat(headerLines.count * 22 + 20)
            let headerFrame = CGRect(x: 44, y: headerBoxTop, width: pageRect.width - 88, height: headerHeight)
            UIColor.systemGray6.setFill()
            UIBezierPath(roundedRect: headerFrame, cornerRadius: 8).fill()
            UIColor.systemGray4.setStroke()
            let headerOutline = UIBezierPath(roundedRect: headerFrame, cornerRadius: 8)
            headerOutline.lineWidth = 1
            headerOutline.stroke()
            let monoSyncAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Courier-Bold", size: 16) ?? UIFont.monospacedSystemFont(ofSize: 16, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            y = headerBoxTop + 14
            for (label, value) in headerLines {
                let labelText = "\(label): "
                labelText.draw(at: CGPoint(x: 56, y: y), withAttributes: attributesHeaderLabel)
                let labelWidth = (labelText as NSString).size(withAttributes: attributesHeaderLabel).width
                if label == "Clinician Sync Code" {
                    value.draw(at: CGPoint(x: 56 + labelWidth, y: y), withAttributes: monoSyncAttributes)
                } else {
                    value.draw(at: CGPoint(x: 56 + labelWidth, y: y), withAttributes: attributesHeaderValue)
                }
                y += 22
            }
            y = headerBoxTop + headerHeight + 18

            let dateStr = ISO8601DateFormatter().string(from: payload.generatedAt)
            "Generated: \(dateStr)".draw(at: CGPoint(x: 48, y: y), withAttributes: attributesBody)
            y += 28

            var lines: [String] = []
            lines.append("Patient metadata")
            if let a = payload.patient.ageYears {
                lines.append("  Age: \(a) years")
            } else {
                lines.append("  Age: —")
            }
            if let w = payload.patient.weightKg {
                lines.append(String(format: "  Weight: %.1f kg", w))
            } else {
                lines.append("  Weight: —")
            }
            if let bmi = payload.patient.bmi {
                lines.append(String(format: "  BMI: %.1f", bmi))
            } else {
                lines.append("  BMI: —")
            }
            lines.append("")
            lines.append("Smoking gun correlation (hourly SASHB vs rescue fraction): \(payload.spO2ClenchCorrelation.map { fmt($0) } ?? "insufficient data")")
            lines.append("TFI (Temporalis Fatigue Index): \(fmt(payload.tfiPercent))%")
            lines.append("")

            for line in lines {
                line.draw(at: CGPoint(x: 48, y: y), withAttributes: attributesBody)
                y += 18
            }

            y = max(y, 520)
            let footerTitle = "How to Read This Report"
            let footerBody =
                """
                Temporalis Fatigue Index (TFI): A 0–100% composite index of masseter/temporalis hemodynamic loading derived from IR-DC trend and green AC coupling over the session (higher values indicate greater sustained neuromuscular load / fatigue proxy).

                Hypoxic Burden (SASHB): Session integral of oxygen deficit when SpO₂ falls below 90% — computed as Σ max(0, 90 − SpO₂) × Δt in percent·seconds (%·s). Higher values reflect greater cumulative sleep-related hypoxic exposure paired with the recorded Temporalis pattern.
                """
            footerTitle.draw(at: CGPoint(x: 48, y: y), withAttributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold)
            ])
            y += 20
            let footerRect = CGRect(x: 48, y: y, width: pageRect.width - 96, height: pageRect.height - y - 40)
            let ps = NSMutableParagraphStyle()
            ps.lineSpacing = 3
            let footAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .paragraphStyle: ps
            ]
            (footerBody as NSString).draw(
                with: footerRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: footAttr,
                context: nil
            )
        }
        return data
    }

    static func writeToTemporaryFile(payload: ClinicalReportPayload) throws -> URL {
        guard let data = renderPDF(payload: payload) else {
            throw NSError(domain: "ClinicalReportGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "PDF render failed"])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Oralable_MAM_Clinical_Temporalis_Report.pdf")
        try data.write(to: url)
        return url
    }

    /// PDF plus optional 10-minute calibration raw CSV for the iOS share sheet.
    static func writeResearchShareItems(payload: ClinicalReportPayload, calibrationRawCSV: URL?) throws -> [URL] {
        let pdfURL = try writeToTemporaryFile(payload: payload)
        var items: [URL] = [pdfURL]
        if let csv = calibrationRawCSV, FileManager.default.fileExists(atPath: csv.path) {
            items.append(csv)
        }
        return items
    }

    /// Convenience: write Oralable trial raw lane (exported from `SensorData` history).
    static func writeOralableRaw50HzCSV(samples: [SensorData], to url: URL, isManualOverride: Bool = false) throws {
        try ResearchRawDataExport.writeOralableRaw50HzCSV(samples: samples, to: url, isManualOverride: isManualOverride)
    }
}
