import SwiftUI
import Charts

// MARK: - Enhanced Historical Chart Component
struct HistoricalChartView: View {
    @EnvironmentObject var designSystem: DesignSystem
    let metricType: MetricType
    let timeRange: TimeRange
    @Binding var selectedDataPoint: SensorData?
    let processed: HistoricalDataProcessor.ProcessedHistoricalData?

    // X-axis domain - the full time range regardless of data points
    private var xAxisDomain: ClosedRange<Date> {
        guard let processed = processed, !processed.rawData.isEmpty else {
            let now = Date()
            return now.addingTimeInterval(-3600)...now
        }

        let calendar = Calendar.current
        let referenceDate = processed.rawData.first?.timestamp ?? Date()

        switch timeRange {
        case .minute:
            if let minuteInterval = calendar.dateInterval(of: .minute, for: referenceDate) {
                return minuteInterval.start...minuteInterval.end
            }
        case .hour:
            if let hourInterval = calendar.dateInterval(of: .hour, for: referenceDate) {
                return hourInterval.start...hourInterval.end
            }
        case .day:
            let startOfDay = calendar.startOfDay(for: referenceDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return startOfDay...endOfDay
        case .week:
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) {
                return weekInterval.start...weekInterval.end
            }
        case .month:
            if let monthInterval = calendar.dateInterval(of: .month, for: referenceDate) {
                return monthInterval.start...monthInterval.end
            }
        }

        return referenceDate...referenceDate.addingTimeInterval(3600)
    }

    // X-axis stride based on time range
    private var xAxisStride: Calendar.Component {
        switch timeRange {
        case .minute:
            return .second
        case .hour:
            return .minute
        case .day:
            return .hour
        case .week:
            return .day
        case .month:
            return .day
        }
    }

    // X-axis date format based on time range
    private var xAxisDateFormat: Date.FormatStyle {
        switch timeRange {
        case .minute:
            return .dateTime.hour().minute().second()
        case .hour:
            return .dateTime.hour().minute()
        case .day:
            return .dateTime.hour()
        case .week:
            return .dateTime.weekday(.abbreviated).day()
        case .month:
            return .dateTime.month(.abbreviated).day()
        }
    }

    private var chartPoints: [(timestamp: Date, value: Double)] {
        guard let processed = processed else { return [] }
        if metricType == .ppg {
            return processed.normalizedData
        } else {
            return processed.normalizedData
        }
    }

    private var emptyStateMessage: String {
        "No data available for the selected period"
    }

    /// Accessibility summary describing the chart content for VoiceOver users
    private var chartAccessibilitySummary: String {
        guard let processed = processed, !chartPoints.isEmpty else {
            return "\(metricType.title) chart. No data available for the selected period."
        }
        let stats = processed.statistics
        let sampleCount = stats.sampleCount
        let avg = String(format: "%.0f", stats.average)
        let min = String(format: "%.0f", stats.minimum)
        let max = String(format: "%.0f", stats.maximum)
        return "\(metricType.title) chart with \(sampleCount) data points. Average: \(avg), minimum: \(min), maximum: \(max). Time range: \(timeRange.rawValue)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metricType.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let processed {
                        Text("\(processed.statistics.sampleCount) samples \u{2022} \(processed.processingMethod) processing")
                            .font(designSystem.typography.caption2)
                            .foregroundColor(designSystem.colors.textSecondary)
                            .opacity(0.7)
                    }
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)

            if chartPoints.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 40))
                        .foregroundColor(designSystem.colors.gray400)
                    Text("No data available")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                    Text(emptyStateMessage)
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 200)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(metricType.title) chart. No data available for the selected period.")
            } else {
                Chart {
                    ForEach(Array(chartPoints.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value(metricType.title, point.value)
                        )
                        .foregroundStyle(metricType == .ppg ? .blue : metricType.color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value(metricType.title, point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [(metricType == .ppg ? Color.blue : metricType.color).opacity(0.1),
                                         (metricType == .ppg ? Color.blue : metricType.color).opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    if let selected = selectedDataPoint {
                        if let closest = closestPoint(to: selected.timestamp) {
                            PointMark(
                                x: .value("Time", closest.timestamp),
                                y: .value(metricType.title, closest.value)
                            )
                            .foregroundStyle(metricType == .ppg ? .blue : metricType.color)
                            .symbol(.circle)
                            .symbolSize(80)

                            RuleMark(x: .value("Time", closest.timestamp))
                                .foregroundStyle(.gray.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                        }
                    }
                }
                .frame(height: 250)
                .chartXScale(domain: xAxisDomain)
                .chartXAxis {
                    AxisMarks(values: .stride(by: xAxisStride)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.gray.opacity(0.3))
                        AxisValueLabel(format: xAxisDateFormat)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 6)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.gray.opacity(0.3))
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(String(format: "%.0f", doubleValue))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chartAccessibilitySummary)
            }

            if let selected = selectedDataPoint, let processed {
                HistoricalTooltip(
                    metricType: metricType,
                    selected: selected,
                    processed: processed
                )
            }

            Text("Context is key to getting a better understanding of your \(metricType.title).")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
                .padding(.top, designSystem.spacing.sm)
        }
        .padding()
        .background(designSystem.colors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: designSystem.cornerRadius.large))
        .designShadow(.small)
    }

    private func closestPoint(to time: Date) -> (timestamp: Date, value: Double)? {
        guard !chartPoints.isEmpty else { return nil }
        return chartPoints.min(by: { abs($0.timestamp.timeIntervalSince(time)) < abs($1.timestamp.timeIntervalSince(time)) })
    }
}
