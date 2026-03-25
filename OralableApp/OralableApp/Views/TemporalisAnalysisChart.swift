//
//  TemporalisAnalysisChart.swift
//  OralableApp
//
//  Oralable MAM: Clinical Temporalis — IR-DC (line), rescue events / hour (bars),
//  and SpO₂ < 90% markers.
//

import SwiftUI
import Charts
import OralableCore

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

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            Text("Oralable MAM: Clinical Temporalis Report — Analysis")
                .font(designSystem.typography.labelMedium)
                .foregroundColor(designSystem.colors.textPrimary)

            Chart {
                ForEach(lineSeries) { pt in
                    LineMark(
                        x: .value("Time", pt.time),
                        y: .value("IR-DC", pt.irDCValue)
                    )
                    .foregroundStyle(Color.purple.opacity(0.9))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(hypoxiaMarkers) { m in
                    PointMark(
                        x: .value("Time", m.time),
                        y: .value("IR-DC", yOnLine(near: m.time))
                    )
                    .symbolSize(72)
                    .foregroundStyle(designSystem.colors.error)
                }
            }
            .frame(height: 160)

            Chart {
                ForEach(rescuePerHour) { bar in
                    BarMark(
                        x: .value("Hour", bar.hourLabel),
                        y: .value("Rescue / h", bar.count)
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
            Label("IR-DC (hemodynamic)", systemImage: "waveform.path.ecg")
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.textSecondary)
            Label("Rescue events", systemImage: "exclamationmark.triangle.fill")
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
    }

    static func build(from samples: [SensorData], hourlyRescue: [HourlyTemporalisSegment]) -> Model {
        let oral = samples.filter { $0.deviceType == .oralable }
        let line: [TemporalisSeriesPoint] = oral.map {
            TemporalisSeriesPoint(time: $0.timestamp, irDCValue: Double($0.ppg.ir))
        }
        let markers: [SpO2HypoxiaMarker] = oral.compactMap { s in
            guard let sp = s.spo2, sp.percentage < 90 else { return nil }
            return SpO2HypoxiaMarker(time: s.timestamp, spo2: sp.percentage)
        }
        let bars: [RescueFrequencyBar] = hourlyRescue.map { h in
            RescueFrequencyBar(id: h.hourIndex, hourLabel: "H\(h.hourIndex + 1)", count: h.rescueEventCount)
        }
        return Model(line: line, bars: bars, markers: markers)
    }
}
