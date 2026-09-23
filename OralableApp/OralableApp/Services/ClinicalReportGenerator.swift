//
//  ClinicalReportGenerator.swift
//  OralableApp
//
//  Multi-page PDF: overnight Temporalis night report (Mac pack parity).
//  Pages: KPIs + bout hypnogram | hourly stack + smoking-gun | event table
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
    var patientName: String
    var dateOfStudy: Date
    var clinicianSyncCode: String
    var spO2ClenchCorrelation: Double?
    var tfiPercent: Double
    var generatedAt: Date
    var hourlySegments: [HourlyTemporalisSegment] = []
    /// Sample-level overnight analysis (Mac night-report parity). Nil → hourly-only fallback.
    var nightAnalysis: OvernightNightAnalysis? = nil
}

enum ClinicalReportGenerator {
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

    private static let colorQuiet = UIColor(red: 0.83, green: 0.83, blue: 0.83, alpha: 1)
    private static let colorTonic = UIColor(red: 0.25, green: 0.41, blue: 0.88, alpha: 1)
    private static let colorPhasic = UIColor(red: 0.31, green: 0.78, blue: 0.47, alpha: 1)
    private static let colorRescue = UIColor(red: 0.55, green: 0.0, blue: 0.0, alpha: 1)
    private static let colorRecovery = UIColor(red: 0.91, green: 0.72, blue: 0.43, alpha: 1)
    private static let colorSASHB = UIColor(red: 0.50, green: 0.86, blue: 1.0, alpha: 1)
    private static let colorIR = UIColor(red: 0.75, green: 0.22, blue: 0.17, alpha: 1)
    private static let colorSpO2 = UIColor(red: 0.36, green: 0.68, blue: 0.89, alpha: 1)

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

    static func overnightKPIs(from hourly: [HourlyTemporalisSegment]) -> (
        wearHours: Double,
        tonicMin: Double,
        phasicMin: Double,
        rescueMin: Double,
        rescueEvents: Int,
        sashbTotal: Double,
        meanTFI: Double
    ) {
        guard !hourly.isEmpty else { return (0, 0, 0, 0, 0, 0, 0) }
        let wearHours = Double(hourly.count)
        func minutes(_ keyPath: KeyPath<HourlyTemporalisSegment, Double>) -> Double {
            hourly.reduce(0.0) { $0 + $1[keyPath: keyPath] * 60.0 }
        }
        let meanTFI = hourly.map(\.tfiPercent).reduce(0, +) / Double(hourly.count)
        return (
            wearHours,
            minutes(\.tonic),
            minutes(\.phasic),
            minutes(\.rescue),
            hourly.reduce(0) { $0 + $1.rescueEventCount },
            hourly.reduce(0.0) { $0 + $1.sashbHypoxicBurden },
            meanTFI
        )
    }

    static func renderPDF(payload: ClinicalReportPayload) -> Data? {
        let fmt: (Double) -> String = { String(format: "%.3f", $0) }
        let fmt1: (Double) -> String = { v in
            guard v.isFinite else { return "—" }
            return String(format: "%.1f", v)
        }
        let studyDateFormatter = DateFormatter()
        studyDateFormatter.dateStyle = .long
        studyDateFormatter.timeStyle = .none

        let hourly = payload.hourlySegments.sorted { $0.hourIndex < $1.hourIndex }
        let analysis = payload.nightAnalysis
        let hourlyKPIs = overnightKPIs(from: hourly)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            // PAGE 1 — summary + KPIs + bout hypnogram
            ctx.beginPage()
            var y = drawHeader(
                banner: "CONFIDENTIAL RESEARCH DATA: McGill/Beacon Clinical Trial",
                title: "Oralable MAM: Overnight Temporalis Report",
                payload: payload,
                studyDateFormatter: studyDateFormatter
            )

            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .regular)]
            let bold: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .bold)]

            "Patient metadata".draw(at: CGPoint(x: 48, y: y), withAttributes: bold)
            y += 18
            "  Age: \(payload.patient.ageYears.map { "\($0) years" } ?? "—")".draw(at: CGPoint(x: 48, y: y), withAttributes: body); y += 16
            "  Weight: \(payload.patient.weightKg.map { String(format: "%.1f kg", $0) } ?? "—")".draw(at: CGPoint(x: 48, y: y), withAttributes: body); y += 16
            "  BMI: \(payload.patient.bmi.map { String(format: "%.1f", $0) } ?? "—")".draw(at: CGPoint(x: 48, y: y), withAttributes: body); y += 20

            "Overnight KPIs (device-inferred wellness states — not a diagnosis)".draw(
                at: CGPoint(x: 48, y: y), withAttributes: bold
            )
            y += 18

            // Prefer overnight hourly mean TFI over live gauge (disconnect resets live TFI to 50).
            let tfiDisplay = hourlyKPIs.meanTFI > 0 ? hourlyKPIs.meanTFI : payload.tfiPercent

            let kpiLines: [String]
            if let a = analysis {
                let k = a.kpis
                kpiLines = [
                    "Wear: \(fmt1(k.wearS / 60.0)) min (\(a.sampleCount) samples)   |   TFI: \(fmt1(tfiDisplay))%",
                    "Tonic: \(fmt1(k.tonicMin)) min (longest \(fmt1(k.longestTonicS)) s)   |   Phasic: \(fmt1(k.phasicMin)) min (\(k.phasicBoutCount) bouts)",
                    "Rescue: \(k.rescueCount) events (\(fmt1(k.rescueTotalS)) s)   |   Recovery med/max: \(fmt1(k.recoveryMedianS))/\(fmt1(k.recoveryMaxS)) s",
                    "SASHB: \(fmt1(k.sashb)) %·s   |   SpO₂ μ/min: \(fmt1(k.spo2Mean))/\(fmt1(k.spo2Min))%",
                    "Smoking-gun r (hourly): \(payload.spO2ClenchCorrelation.map { fmt($0) } ?? "insufficient data")"
                ]
            } else {
                kpiLines = [
                    "Wear: \(fmt1(hourlyKPIs.wearHours)) h   |   TFI: \(fmt1(tfiDisplay))%",
                    "Tonic: \(fmt1(hourlyKPIs.tonicMin)) min   |   Phasic: \(fmt1(hourlyKPIs.phasicMin)) min",
                    "Rescue: \(hourlyKPIs.rescueEvents) events (\(fmt1(hourlyKPIs.rescueMin)) min)   |   SASHB: \(fmt1(hourlyKPIs.sashbTotal)) %·s",
                    "Smoking-gun r (hourly SASHB vs rescue): \(payload.spO2ClenchCorrelation.map { fmt($0) } ?? "insufficient data")",
                    "(Bout-level analysis unavailable — showing hourly rollups only)"
                ]
            }
            for line in kpiLines {
                line.draw(at: CGPoint(x: 48, y: y), withAttributes: body)
                y += 16
            }
            y += 10

            if let a = analysis, !a.timeline.isEmpty {
                "State hypnogram (bout-level)".draw(at: CGPoint(x: 48, y: y), withAttributes: bold)
                y += 8
                let hypoFrame = CGRect(x: 48, y: y, width: pageRect.width - 96, height: 110)
                drawBoutHypnogram(in: hypoFrame, timeline: a.timeline)
                y = hypoFrame.maxY + 10
            } else {
                "State hypnogram (hourly fractions)".draw(at: CGPoint(x: 48, y: y), withAttributes: bold)
                y += 8
                let hypoFrame = CGRect(x: 48, y: y, width: pageRect.width - 96, height: 72)
                drawHourlyHypnogram(in: hypoFrame, hourly: hourly)
                y = hypoFrame.maxY + 10
            }
            drawLegend(at: CGPoint(x: 48, y: y), includeRecovery: analysis != nil)
            drawFooterNote(atY: pageRect.height - 70)

            // PAGE 2 — hourly + smoking gun
            ctx.beginPage()
            y = 40
            "Hourly stacked burden + SASHB".draw(at: CGPoint(x: 48, y: y), withAttributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold)
            ])
            y += 24
            let chartFrame = CGRect(x: 48, y: y, width: pageRect.width - 96, height: 200)
            if let a = analysis, !a.hourly.isEmpty {
                drawAnalysisHourlyStack(in: chartFrame, hourly: a.hourly)
            } else {
                drawHourlyStackedBurden(in: chartFrame, hourly: hourly)
            }
            y = chartFrame.maxY + 20

            "Smoking-gun dual rail (IR-DC + SpO₂)".draw(at: CGPoint(x: 48, y: y), withAttributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .bold)
            ])
            y += 18
            let gunFrame = CGRect(x: 48, y: y, width: pageRect.width - 96, height: 280)
            if let a = analysis, a.timeline.count >= 2 {
                drawSmokingGun(in: gunFrame, timeline: a.timeline)
            } else {
                "No sample timeline for dual-rail chart.".draw(
                    at: CGPoint(x: gunFrame.minX + 12, y: gunFrame.midY),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 11)]
                )
            }
            drawFooterNote(atY: pageRect.height - 70)

            // PAGE 3 — event table
            ctx.beginPage()
            y = 40
            "Event table (bouts)".draw(at: CGPoint(x: 48, y: y), withAttributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold)
            ])
            y += 24
            drawEventTable(atY: &y, bouts: analysis?.bouts ?? [])
            drawFooterNote(atY: pageRect.height - 70)
        }
        return data
    }

    // MARK: - Drawing

    private static func drawHeader(
        banner: String,
        title: String,
        payload: ClinicalReportPayload,
        studyDateFormatter: DateFormatter
    ) -> CGFloat {
        var y: CGFloat = 40
        banner.draw(at: CGPoint(x: 48, y: y), withAttributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
        ])
        y += 22
        title.draw(at: CGPoint(x: 48, y: y), withAttributes: [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold)
        ])
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
        UIBezierPath(roundedRect: headerFrame, cornerRadius: 8).stroke()

        let labelAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .bold)]
        let monoSyncAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Courier-Bold", size: 16) ?? UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)
        ]
        y = headerBoxTop + 14
        for (label, value) in headerLines {
            let labelText = "\(label): "
            labelText.draw(at: CGPoint(x: 56, y: y), withAttributes: labelAttr)
            let labelWidth = (labelText as NSString).size(withAttributes: labelAttr).width
            if label == "Clinician Sync Code" {
                value.draw(at: CGPoint(x: 56 + labelWidth, y: y), withAttributes: monoSyncAttributes)
            } else {
                value.draw(at: CGPoint(x: 56 + labelWidth, y: y), withAttributes: labelAttr)
            }
            y += 22
        }
        y = headerBoxTop + headerHeight + 14
        let dateStr = ISO8601DateFormatter().string(from: payload.generatedAt)
        "Generated: \(dateStr)".draw(at: CGPoint(x: 48, y: y), withAttributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular)
        ])
        return y + 22
    }

    private static func drawLegend(at origin: CGPoint, includeRecovery: Bool) {
        var items: [(String, UIColor)] = [
            ("Quiet", colorQuiet),
            ("Tonic", colorTonic),
            ("Phasic", colorPhasic),
            ("Rescue", colorRescue)
        ]
        if includeRecovery {
            items.append(("Recovery", colorRecovery))
        }
        items.append(("SASHB", colorSASHB))
        var x = origin.x
        let font: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9, weight: .regular)]
        for (name, color) in items {
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: x, y: origin.y, width: 10, height: 10), cornerRadius: 2).fill()
            name.draw(at: CGPoint(x: x + 14, y: origin.y - 1), withAttributes: font)
            x += 68
        }
    }

    private static func drawFooterNote(atY y: CGFloat) {
        let note =
            "Device-inferred wellness states — not a medical diagnosis. Colors match the Python overnight night-report pack."
        note.draw(
            at: CGPoint(x: 48, y: y),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 8, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
        )
    }

    private static func color(for state: OvernightMamState) -> UIColor {
        switch state {
        case .quiet: return colorQuiet
        case .tonic: return colorTonic
        case .phasic: return colorPhasic
        case .rescue: return colorRescue
        case .recovery: return colorRecovery
        }
    }

    private static func drawBoutHypnogram(in rect: CGRect, timeline: [OvernightTimelinePoint]) {
        UIColor.systemGray6.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        guard let first = timeline.first, let last = timeline.last, last.elapsedS > first.elapsedS else { return }

        let order: [OvernightMamState] = [.quiet, .recovery, .phasic, .tonic, .rescue]
        let rowH = (rect.height - 16) / CGFloat(order.count)
        let t0 = first.elapsedS
        let span = max(1e-3, last.elapsedS - t0)
        let plot = rect.insetBy(dx: 8, dy: 8)

        var i = 0
        while i < timeline.count {
            let st = timeline[i].state
            var j = i + 1
            while j < timeline.count && timeline[j].state == st { j += 1 }
            let x0 = plot.minX + CGFloat((timeline[i].elapsedS - t0) / span) * plot.width
            let x1 = plot.minX + CGFloat((timeline[j - 1].elapsedS - t0) / span) * plot.width
            if let row = order.firstIndex(of: st) {
                let y = plot.minY + CGFloat(row) * rowH
                color(for: st).setFill()
                UIBezierPath(rect: CGRect(x: x0, y: y, width: max(1, x1 - x0 + 1), height: rowH * 0.85)).fill()
            }
            i = j
        }

        let labFont: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]
        for (row, st) in order.enumerated() {
            let y = plot.minY + CGFloat(row) * rowH
            st.displayName.draw(at: CGPoint(x: plot.minX, y: y), withAttributes: labFont)
        }
    }

    private static func drawHourlyHypnogram(in rect: CGRect, hourly: [HourlyTemporalisSegment]) {
        UIColor.systemGray6.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        guard !hourly.isEmpty else {
            "No hourly Temporalis segments for this session.".draw(
                at: CGPoint(x: rect.minX + 12, y: rect.midY - 6),
                withAttributes: [.font: UIFont.systemFont(ofSize: 10)]
            )
            return
        }
        let barH = rect.height - 16
        let barY = rect.minY + 8
        let totalW = rect.width - 16
        let slotW = totalW / CGFloat(hourly.count)
        for (idx, h) in hourly.enumerated() {
            let denom = max(1e-6, h.quiet + h.phasic + h.tonic + h.rescue)
            let parts: [(Double, UIColor)] = [
                (h.quiet / denom, colorQuiet),
                (h.phasic / denom, colorPhasic),
                (h.tonic / denom, colorTonic),
                (h.rescue / denom, colorRescue)
            ]
            var x = rect.minX + 8 + CGFloat(idx) * slotW
            for (frac, color) in parts {
                let w = slotW * CGFloat(frac)
                color.setFill()
                UIBezierPath(rect: CGRect(x: x, y: barY, width: max(0.5, w), height: barH)).fill()
                x += w
            }
        }
    }

    private static func drawHourlyStackedBurden(in rect: CGRect, hourly: [HourlyTemporalisSegment]) {
        UIColor.systemGray6.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        guard !hourly.isEmpty else { return }
        let plot = rect.insetBy(dx: 36, dy: 24)
        let maxMin = max(60.0, hourly.map { ($0.quiet + $0.phasic + $0.tonic + $0.rescue) * 60.0 }.max() ?? 60)
        let maxSashb = max(1.0, hourly.map(\.sashbHypoxicBurden).max() ?? 1)
        drawStackedBars(
            plot: plot,
            count: hourly.count,
            maxMin: maxMin,
            maxSashb: maxSashb,
            minutesAt: { i in
                let h = hourly[i]
                return [
                    (h.quiet * 60, colorQuiet),
                    (h.phasic * 60, colorPhasic),
                    (h.tonic * 60, colorTonic),
                    (h.rescue * 60, colorRescue)
                ]
            },
            sashbAt: { hourly[$0].sashbHypoxicBurden }
        )
    }

    private static func drawAnalysisHourlyStack(in rect: CGRect, hourly: [OvernightHourlyBurden]) {
        UIColor.systemGray6.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        let plot = rect.insetBy(dx: 36, dy: 24)
        let maxMin = max(
            1.0,
            hourly.map { $0.quietMin + $0.phasicMin + $0.tonicMin + $0.rescueMin + $0.recoveryMin }.max() ?? 1
        )
        let maxSashb = max(1.0, hourly.map(\.sashbDelta).max() ?? 1)
        drawStackedBars(
            plot: plot,
            count: hourly.count,
            maxMin: maxMin,
            maxSashb: maxSashb,
            minutesAt: { i in
                let h = hourly[i]
                return [
                    (h.quietMin, colorQuiet),
                    (h.recoveryMin, colorRecovery),
                    (h.phasicMin, colorPhasic),
                    (h.tonicMin, colorTonic),
                    (h.rescueMin, colorRescue)
                ]
            },
            sashbAt: { hourly[$0].sashbDelta }
        )
    }

    private static func drawStackedBars(
        plot: CGRect,
        count: Int,
        maxMin: Double,
        maxSashb: Double,
        minutesAt: (Int) -> [(Double, UIColor)],
        sashbAt: (Int) -> Double
    ) {
        guard count > 0 else { return }
        UIColor.darkGray.setStroke()
        let axis = UIBezierPath()
        axis.move(to: CGPoint(x: plot.minX, y: plot.maxY))
        axis.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        axis.move(to: CGPoint(x: plot.minX, y: plot.minY))
        axis.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        axis.lineWidth = 1
        axis.stroke()

        let slotW = plot.width / CGFloat(count)
        let barW = slotW * 0.62
        var sashbPoints: [CGPoint] = []
        for i in 0..<count {
            let x0 = plot.minX + CGFloat(i) * slotW + (slotW - barW) / 2
            var yBottom = plot.maxY
            for (mins, color) in minutesAt(i) {
                let hPx = CGFloat(mins / maxMin) * plot.height
                color.setFill()
                UIBezierPath(rect: CGRect(x: x0, y: yBottom - hPx, width: barW, height: hPx)).fill()
                yBottom -= hPx
            }
            let sx = x0 + barW / 2
            let sy = plot.maxY - CGFloat(sashbAt(i) / maxSashb) * plot.height
            sashbPoints.append(CGPoint(x: sx, y: sy))
        }
        if sashbPoints.count >= 2 {
            colorSASHB.setStroke()
            let line = UIBezierPath()
            line.move(to: sashbPoints[0])
            for p in sashbPoints.dropFirst() { line.addLine(to: p) }
            line.lineWidth = 2
            line.stroke()
        }
    }

    private static func drawSmokingGun(in rect: CGRect, timeline: [OvernightTimelinePoint]) {
        UIColor.systemGray6.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        let top = CGRect(x: rect.minX + 8, y: rect.minY + 8, width: rect.width - 16, height: (rect.height - 24) / 2)
        let bot = CGRect(x: rect.minX + 8, y: top.maxY + 8, width: rect.width - 16, height: (rect.height - 24) / 2)

        let t0 = timeline.first!.elapsedS
        let t1 = timeline.last!.elapsedS
        let span = max(1e-3, t1 - t0)

        func x(_ e: Double, in r: CGRect) -> CGFloat {
            r.minX + CGFloat((e - t0) / span) * r.width
        }

        // IR rail
        let irs = timeline.map(\.ir)
        let irMin = (irs.min() ?? 0)
        let irMax = max(irMin + 1, irs.max() ?? 1)
        let irPath = UIBezierPath()
        for (i, p) in timeline.enumerated() {
            let px = x(p.elapsedS, in: top)
            let py = top.maxY - CGFloat((p.ir - irMin) / (irMax - irMin)) * top.height
            if i == 0 { irPath.move(to: CGPoint(x: px, y: py)) }
            else { irPath.addLine(to: CGPoint(x: px, y: py)) }
        }
        colorIR.setStroke()
        irPath.lineWidth = 1
        irPath.stroke()

        for p in timeline where [.tonic, .phasic, .rescue].contains(p.state) {
            let px = x(p.elapsedS, in: top)
            let py = top.maxY - CGFloat((p.ir - irMin) / (irMax - irMin)) * top.height
            color(for: p.state).setFill()
            UIBezierPath(ovalIn: CGRect(x: px - 1.5, y: py - 1.5, width: 3, height: 3)).fill()
        }
        "IR-DC".draw(at: CGPoint(x: top.minX, y: top.minY), withAttributes: [
            .font: UIFont.systemFont(ofSize: 8, weight: .semibold)
        ])

        // SpO2 rail
        let spo2Path = UIBezierPath()
        for (i, p) in timeline.enumerated() {
            let px = x(p.elapsedS, in: bot)
            let py = bot.maxY - CGFloat((min(100, max(84, p.spo2)) - 84) / 16.0) * bot.height
            if i == 0 { spo2Path.move(to: CGPoint(x: px, y: py)) }
            else { spo2Path.addLine(to: CGPoint(x: px, y: py)) }
        }
        // Shade SASHB zone
        for i in 1..<timeline.count {
            let a = timeline[i - 1]
            let b = timeline[i]
            if a.spo2 < 90 || b.spo2 < 90 {
                let x0 = x(a.elapsedS, in: bot)
                let x1 = x(b.elapsedS, in: bot)
                let y90 = bot.maxY - CGFloat((90 - 84) / 16.0) * bot.height
                let ya = bot.maxY - CGFloat((min(100, max(84, a.spo2)) - 84) / 16.0) * bot.height
                let yb = bot.maxY - CGFloat((min(100, max(84, b.spo2)) - 84) / 16.0) * bot.height
                colorSASHB.withAlphaComponent(0.25).setFill()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x0, y: y90))
                path.addLine(to: CGPoint(x: x0, y: ya))
                path.addLine(to: CGPoint(x: x1, y: yb))
                path.addLine(to: CGPoint(x: x1, y: y90))
                path.close()
                path.fill()
            }
        }
        colorSpO2.setStroke()
        spo2Path.lineWidth = 1.2
        spo2Path.stroke()
        for p in timeline where p.state == .rescue {
            let px = x(p.elapsedS, in: bot)
            colorRescue.setStroke()
            let tick = UIBezierPath()
            tick.move(to: CGPoint(x: px, y: bot.minY + 4))
            tick.addLine(to: CGPoint(x: px, y: bot.maxY - 4))
            tick.lineWidth = 1
            tick.stroke()
        }
        "SpO₂".draw(at: CGPoint(x: bot.minX, y: bot.minY), withAttributes: [
            .font: UIFont.systemFont(ofSize: 8, weight: .semibold)
        ])
    }

    private static func drawEventTable(atY y: inout CGFloat, bouts: [OvernightBout]) {
        let header = "start_s   end_s   dur_s   type       minSpO2  dSpO2   peakMot  rec_s"
        let mono: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        ]
        let boldMono: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .bold)
        ]
        header.draw(at: CGPoint(x: 48, y: y), withAttributes: boldMono)
        y += 14
        let rows = bouts.prefix(45)
        if rows.isEmpty {
            "No event bouts detected.".draw(at: CGPoint(x: 48, y: y), withAttributes: [
                .font: UIFont.systemFont(ofSize: 11)
            ])
            return
        }
        for b in rows {
            let typePad = (b.state.rawValue + String(repeating: " ", count: 9)).prefix(9)
            let line = String(
                format: "%7.1f  %7.1f  %6.1f  %@  %6.1f  %6.1f  %7.4f  %5.1f",
                b.startS, b.endS, b.durationS, String(typePad),
                b.minSpo2.isFinite ? b.minSpo2 : -1,
                b.deltaSpo2.isFinite ? b.deltaSpo2 : 0,
                b.peakMotion.isFinite ? b.peakMotion : 0,
                b.recoveryS
            )
            line.draw(at: CGPoint(x: 48, y: y), withAttributes: mono)
            y += 11
            if y > pageRect.height - 90 { break }
        }
        if bouts.count > rows.count {
            y += 8
            "… \(bouts.count - rows.count) more bouts in attached CSV".draw(
                at: CGPoint(x: 48, y: y),
                withAttributes: [.font: UIFont.systemFont(ofSize: 9)]
            )
        }
    }

    // MARK: - Share outputs

    static func writeToTemporaryFile(payload: ClinicalReportPayload) throws -> URL {
        guard let data = renderPDF(payload: payload) else {
            throw NSError(domain: "ClinicalReportGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "PDF render failed"])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Oralable_MAM_Clinical_Temporalis_Report.pdf")
        try data.write(to: url)
        return url
    }

    static func writeEventCSV(analysis: OvernightNightAnalysis) throws -> URL {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd_HHmmss"
        let name = "Oralable_Night_Events_\(df.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try OvernightStateClassifier.eventCSV(from: analysis).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func writeResearchShareItems(
        payload: ClinicalReportPayload,
        calibrationRawCSV: URL?,
        includeEventCSV: Bool = true
    ) throws -> [URL] {
        let pdfURL = try writeToTemporaryFile(payload: payload)
        var items: [URL] = [pdfURL]
        if includeEventCSV, let analysis = payload.nightAnalysis, !analysis.bouts.isEmpty {
            items.append(try writeEventCSV(analysis: analysis))
        }
        if let csv = calibrationRawCSV, FileManager.default.fileExists(atPath: csv.path) {
            items.append(csv)
        }
        return items
    }

    static func writeOralableRaw50HzCSV(samples: [SensorData], to url: URL, isManualOverride: Bool = false) throws {
        try ResearchRawDataExport.writeOralableRaw50HzCSV(samples: samples, to: url, isManualOverride: isManualOverride)
    }
}
