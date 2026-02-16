//
//  MovementSparkline.swift
//  OralableApp
//
//  Sparkline with threshold-based coloring for movement data.
//  Colors all points based on overall movement state:
//  green when actively moving, blue when still.
//
//  Extracted from DashboardView.swift
//

import SwiftUI
import Charts

// MARK: - Movement Sparkline with Threshold Coloring
/// Sparkline that colors all points based on overall movement state
/// Green when actively moving, blue when still
struct MovementSparkline: View {
    let data: [Double]
    let threshold: Double  // Movement variability threshold from settings (500-5000)
    let isOverallActive: Bool  // Whether the overall state is "Active" (variability > threshold)
    let activeColor: Color
    let stillColor: Color

    var body: some View {
        // All points use the same color based on overall active/still state
        let pointColor = isOverallActive ? activeColor.opacity(0.8) : stillColor.opacity(0.6)

        Chart(Array(data.enumerated()), id: \.offset) { index, value in
            PointMark(
                x: .value("Index", index),
                y: .value("Value", value)
            )
            .foregroundStyle(pointColor)
            .symbolSize(10)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}
