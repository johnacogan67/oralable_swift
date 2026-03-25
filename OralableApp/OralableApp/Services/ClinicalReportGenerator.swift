//
//  ClinicalReportGenerator.swift
//  OralableApp
//
//  Single-page PDF: Oralable MAM: Clinical Temporalis Report
//

import UIKit

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
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let title = "Oralable MAM: Clinical Temporalis Report"
            let attributesTitle: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold)
            ]
            let attributesBody: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular)
            ]
            var y: CGFloat = 48
            title.draw(at: CGPoint(x: 48, y: y), withAttributes: attributesTitle)
            y += 32
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
            lines.append("Oralable MAM: Clinical Temporalis Report — end of summary")

            for line in lines {
                line.draw(at: CGPoint(x: 48, y: y), withAttributes: attributesBody)
                y += 18
            }
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
}
