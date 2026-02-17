//
//  HistoricalChartViews.swift
//  OralableApp
//
//  Chart view components for HistoricalView including
//  activity, movement, and temperature charts with
//  time-period-aware axis configuration.
//
//  Extracted from HistoricalView.swift
//

import SwiftUI
import Charts

extension HistoricalView {

    @ViewBuilder
    var chartForSelectedTab: some View {
        switch selectedTab {
        case .emg, .ir:
            activityChart
        case .move:
            movementChart
        case .temp:
            temperatureChart
        }
    }

    var activityChart: some View {
        Chart(filteredDataPoints) { point in
            if let value = point.averagePPGIR {
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Activity", value)
                )
                .foregroundStyle(selectedTab.chartColor)
            }
        }
        .chartXScale(domain: xAxisDomain)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { _ in
                AxisGridLine()
                AxisValueLabel(format: xAxisDateFormat)
            }
        }
    }

    var movementChart: some View {
        Chart(filteredDataPoints) { point in
            PointMark(
                x: .value("Time", point.timestamp),
                y: .value("Acceleration", point.movementIntensity)
            )
            .foregroundStyle(point.isAtRest ? designSystem.colors.success.opacity(0.6) : designSystem.colors.warning)
            .symbolSize(10)
        }
        .chartXScale(domain: xAxisDomain)
        .chartYScale(domain: 0...3)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let g = value.as(Double.self) {
                        Text(String(format: "%.1f", g))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { _ in
                AxisGridLine()
                AxisValueLabel(format: xAxisDateFormat)
            }
        }
    }

    var temperatureChart: some View {
        Chart(filteredDataPoints) { point in
            if point.averageTemperature > 0 {
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Temperature", point.averageTemperature)
                )
                .foregroundStyle(selectedTab.chartColor)
            }
        }
        .chartXScale(domain: xAxisDomain)
        .chartYScale(domain: 30...42)
        .chartYAxis {
            AxisMarks(position: .leading, values: [30, 32, 34, 36, 38, 40, 42]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let temp = value.as(Double.self) {
                        Text(String(format: "%.0f°", temp))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { _ in
                AxisGridLine()
                AxisValueLabel(format: xAxisDateFormat)
            }
        }
    }

    /// X-axis values based on time period
    var xAxisValues: AxisMarkValues {
        switch selectedTimePeriod {
        case .hour:
            return .stride(by: .minute, count: 10)
        case .day:
            return .stride(by: .hour, count: 3)
        }
    }

    /// X-axis date format based on time period
    var xAxisDateFormat: Date.FormatStyle {
        switch selectedTimePeriod {
        case .hour:
            return .dateTime.minute()
        case .day:
            return .dateTime.hour()
        }
    }
}
