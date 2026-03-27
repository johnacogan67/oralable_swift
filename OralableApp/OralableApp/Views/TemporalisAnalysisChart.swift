//
//  TemporalisAnalysisChart.swift
//  OralableApp
//
//  Temporalis HOI — IR-DC (line), HOI / rescue events per bucket (bars),
//  and SpO₂ < 90% markers. Scopes: Hour / Day / Week (Health-style history).
//

import SwiftUI
import Charts
import OralableCore

enum TemporalisHistoryScope: String, CaseIterable, Identifiable {
    case hour = "Hour"
    case day = "Day"
    case week = "Week"
    var id: String { rawValue }
}

struct TemporalisSeriesPoint: Identifiable {
    let id = UUID()
    let time: Date
    let irDCValue: Double
}

struct RescueFrequencyBar: Identifiable {
    let id: Int
    let hourLabel: String
    let count: Int
}

struct SpO2HypoxiaMarker: Identifiable {
    let id = UUID()
    let time: Date
    let spo2: Double
}

struct TemporalisAnalysisChart: View {
    @EnvironmentObject var designSystem: DesignSystem

    let lineSeries: [TemporalisSeriesPoint]
    let rescuePerHour: [RescueFrequencyBar]
    let hypoxiaMarkers: [SpO2HypoxiaMarker]
    var detailCaption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            Text("Temporalis HOI — Analysis")
                .font(designSystem.typography.labelMedium)
                .foregroundColor(designSystem.colors.textPrimary)

            if let detailCaption, !detailCaption.isEmpty {
                Text(detailCaption)
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.textSecondary)
            }

            Chart {
                ForEach(lineSeries) { pt in
                    LineMark(
                        x: .value("Time", pt.time),
                        y: .value("Temporalis HOI (IR-DC)", pt.irDCValue)
                    )
                    .foregroundStyle(Color.purple.opacity(0.9))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(hypoxiaMarkers) { m in
                    PointMark(
                        x: .value("Time", m.time),
                        y: .value("Temporalis HOI (IR-DC)", yOnLine(near: m.time))
                    )
                    .symbolSize(72)
                    .foregroundStyle(designSystem.colors.error)
                }
            }
            .frame(height: 160)

            Chart {
                ForEach(rescuePerHour) { bar in
                    BarMark(
                        x: .value("Interval", bar.hourLabel),
                        y: .value("Temporalis HOI / h", bar.count)
                    )
                    .foregroundStyle(designSystem.colors.warning.opacity(0.7))
                }
            }
            .frame(height: 120)

            legend
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.card)
    }

    private var legend: some View {
        HStack(spacing: designSystem.spacing.md) {
            Label("Temporalis HOI (hemodynamic)", systemImage: "waveform.path.ecg")
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.textSecondary)
            Label("Temporalis HOI events", systemImage: "exclamationmark.triangle.fill")
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.textSecondary)
            Label("SpO₂ < 90%", systemImage: "lungs.fill")
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.error)
        }
    }

    private func yOnLine(near date: Date) -> Double {
        guard let first = lineSeries.first else { return 0 }
        let nearest = lineSeries.min(by: { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }) ?? first
        return nearest.irDCValue
    }
}

extension TemporalisAnalysisChart {
    struct Model {
        let line: [TemporalisSeriesPoint]
        let bars: [RescueFrequencyBar]
        let markers: [SpO2HypoxiaMarker]
        let detailCaption: String?
    }

    /// Default windowed build (Day) — last 24 hours, hourly Temporalis HOI bars, optional avg hourly SpO₂ nadir caption.
    static func build(
        from samples: [SensorData],
        hourlyRescue: [HourlyTemporalisSegment],
        scope: TemporalisHistoryScope = .day,
        now: Date = Date()
    ) -> Model {
        let window: TimeInterval
        switch scope {
        case .hour: window = 3600
        case .day: window = 86_400
        case .week: window = 604_800
        }

        let start = now.addingTimeInterval(-window)
        let oralAll = samples.filter { $0.deviceType == .oralable }
        let filtered = oralAll.filter { $0.timestamp >= start && $0.timestamp <= now }

        let line = downsampleLine(from: filtered)
        let segs = hourlyRescue
            .filter { $0.segmentEnd > start && $0.segmentStart < now }
            .sorted { $0.segmentStart < $1.segmentStart }

        let bars = barsForScope(scope: scope, segments: segs, windowStart: start, windowEnd: now)
        let markers: [SpO2HypoxiaMarker] = filtered.compactMap { s in
            guard let sp = s.spo2, sp.percentage < 90 else { return nil }
            return SpO2HypoxiaMarker(time: s.timestamp, spo2: sp.percentage)
        }

        let caption: String?
        if scope == .day {
            caption = averageHourlySpo2NadirCaption(samples: filtered)
        } else if scope == .week {
            caption = averageHourlySpo2NadirCaption(samples: filtered)
        } else {
            caption = nil
        }

        return Model(line: line, bars: bars, markers: markers, detailCaption: caption)
    }

    private static func downsampleLine(from filtered: [SensorData]) -> [TemporalisSeriesPoint] {
        let maxPoints = 800
        guard !filtered.isEmpty else { return [] }
        if filtered.count <= maxPoints {
            return filtered.map { TemporalisSeriesPoint(time: $0.timestamp, irDCValue: Double($0.ppg.ir)) }
        }
        let step = max(1, filtered.count / maxPoints)
        var out: [TemporalisSeriesPoint] = []
        var i = 0
        while i < filtered.count {
            let s = filtered[i]
            out.append(TemporalisSeriesPoint(time: s.timestamp, irDCValue: Double(s.ppg.ir)))
            i += step
        }
        return out
    }

    private static func barsForScope(
        scope: TemporalisHistoryScope,
        segments: [HourlyTemporalisSegment],
        windowStart: Date,
        windowEnd: Date
    ) -> [RescueFrequencyBar] {
        switch scope {
        case .hour:
            let count = segments.reduce(0) { $0 + $1.rescueEventCount }
            return [RescueFrequencyBar(id: 0, hourLabel: "This hour", count: count)]

        case .day:
            let hourFormatter = DateFormatter()
            hourFormatter.dateFormat = "ha"
            return segments.enumerated().map { idx, h in
                RescueFrequencyBar(
                    id: idx,
                    hourLabel: hourFormatter.string(from: h.segmentStart),
                    count: h.rescueEventCount
                )
            }

        case .week:
            let cal = Calendar.current
            var byDay: [Date: Int] = [:]
            for h in segments {
                let d = cal.startOfDay(for: h.segmentStart)
                byDay[d, default: 0] += h.rescueEventCount
            }
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"
            let sortedDays = byDay.keys.sorted()
            return sortedDays.enumerated().map { idx, d in
                RescueFrequencyBar(
                    id: idx,
                    hourLabel: dayFormatter.string(from: d),
                    count: byDay[d] ?? 0
                )
            }
        }
    }

    /// Mean of per-hour minimum SpO₂ over the window (documented with Temporalis HOI day view).
    private static func averageHourlySpo2NadirCaption(samples: [SensorData]) -> String? {
        guard !samples.isEmpty else { return nil }
        let cal = Calendar.current
        let grouped = Dictionary(grouping: samples) { s -> Date in
            let c = cal.dateComponents([.year, .month, .day, .hour], from: s.timestamp)
            return cal.date(from: c) ?? s.timestamp
        }
        var minima: [Double] = []
        for (_, hourSamples) in grouped {
            let vals = hourSamples.compactMap { $0.spo2?.percentage }.filter { $0 > 0 && $0 <= 100 }
            if let m = vals.min() {
                minima.append(m)
            }
        }
        guard !minima.isEmpty else { return nil }
        let avg = minima.reduce(0, +) / Double(minima.count)
        return String(format: "Avg hourly SpO₂ nadir: %.0f%% (%d hours with data)", avg, minima.count)
    }
}
