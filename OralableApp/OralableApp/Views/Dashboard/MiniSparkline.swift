//
//  MiniSparkline.swift
//  OralableApp
//
//  Compact sparkline chart for displaying trend data
//  in metric cards using Swift Charts.
//
//  Extracted from DashboardView.swift
//

import SwiftUI
import Charts

// MARK: - Mini Sparkline Chart
struct MiniSparkline: View {
    let data: [Double]
    let color: Color

    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { index, value in
            LineMark(
                x: .value("Index", index),
                y: .value("Value", value)
            )
            .foregroundStyle(color.opacity(0.6))
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}
