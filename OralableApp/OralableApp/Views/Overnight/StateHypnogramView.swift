//
//  StateHypnogramView.swift
//  OralableApp
//
//  In-app adaptation of Mac/PDF state hypnogram (FIG-CO-025 / TEMPORALIS_20260724).
//  Device-inferred wellness states — not a medical diagnosis.
//

import SwiftUI
import UIKit

extension OvernightMamState {
    /// PDF-matching colors from ClinicalReportGenerator.
    var hypnogramColor: Color {
        switch self {
        case .quiet: return Color(red: 0.83, green: 0.83, blue: 0.83)
        case .tonic: return Color(red: 0.25, green: 0.41, blue: 0.88)
        case .phasic: return Color(red: 0.31, green: 0.78, blue: 0.47)
        case .rescue: return Color(red: 0.55, green: 0.0, blue: 0.0)
        case .recovery: return Color(red: 0.91, green: 0.72, blue: 0.43)
        }
    }

    /// Lane order matching ClinicalReportGenerator.drawBoutHypnogram.
    static var hypnogramLaneOrder: [OvernightMamState] {
        [.quiet, .recovery, .phasic, .tonic, .rescue]
    }
}

/// Horizontal multi-lane state barcode (quiet / recovery / phasic / tonic / rescue).
struct StateHypnogramView: View {
    let analysis: OvernightNightAnalysis?
    var showLegend: Bool = true
    var caption: String? = "State hypnogram — primary overnight measure (FIG-CO-025 adaptation)"

    private let laneOrder = OvernightMamState.hypnogramLaneOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let analysis, !analysis.timeline.isEmpty {
                hypnogramCanvas(timeline: analysis.timeline)
                if showLegend {
                    legend
                }
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No overnight state timeline yet. Wear overnight, then refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            }
        }
    }

    private func hypnogramCanvas(timeline: [OvernightTimelinePoint]) -> some View {
        GeometryReader { geo in
            let plot = CGRect(x: 8, y: 8, width: max(1, geo.size.width - 16), height: max(1, geo.size.height - 16))
            let rowH = plot.height / CGFloat(laneOrder.count)
            let t0 = timeline.first!.elapsedS
            let span = max(1e-3, timeline.last!.elapsedS - t0)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(uiColor: .systemGray6))

                ForEach(Array(laneOrder.enumerated()), id: \.offset) { row, state in
                    Text(state.displayName)
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                        .position(
                            x: plot.minX + 18,
                            y: plot.minY + CGFloat(row) * rowH + rowH * 0.4
                        )
                }

                Canvas { context, _ in
                    var i = 0
                    while i < timeline.count {
                        let st = timeline[i].state
                        var j = i + 1
                        while j < timeline.count && timeline[j].state == st { j += 1 }
                        if let row = laneOrder.firstIndex(of: st) {
                            let x0 = plot.minX + CGFloat((timeline[i].elapsedS - t0) / span) * plot.width
                            let x1 = plot.minX + CGFloat((timeline[j - 1].elapsedS - t0) / span) * plot.width
                            let rect = CGRect(
                                x: x0,
                                y: plot.minY + CGFloat(row) * rowH,
                                width: max(1, x1 - x0 + 1),
                                height: rowH * 0.85
                            )
                            context.fill(Path(rect), with: .color(st.hypnogramColor))
                        }
                        i = j
                    }
                }
            }
        }
        .frame(height: 110)
        .accessibilityLabel("Overnight state hypnogram")
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(laneOrder, id: \.self) { state in
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.hypnogramColor)
                        .frame(width: 8, height: 8)
                    Text(state.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
