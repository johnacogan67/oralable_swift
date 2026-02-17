import SwiftUI

// MARK: - Tooltip Component
struct HistoricalTooltip: View {
    @EnvironmentObject var designSystem: DesignSystem
    let metricType: MetricType
    let selected: SensorData
    let processed: HistoricalDataProcessor.ProcessedHistoricalData

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    private var valueText: String {
        let nearest = processed.normalizedData.min(by: { abs($0.timestamp.timeIntervalSince(selected.timestamp)) < abs($1.timestamp.timeIntervalSince(selected.timestamp)) })
        let value = nearest?.value ?? 0

        switch metricType {
        case .ppg:
            return String(format: "%.0f", value)
        case .temperature:
            return String(format: "%.1f°C", value)
        case .battery:
            return String(format: "%.0f%%", value)
        case .accelerometer:
            return String(format: "%.2f", value)
        case .heartRate:
            return String(format: "%.0f BPM", value)
        case .spo2:
            return String(format: "%.0f%%", value)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(timeFormatter.string(from: selected.timestamp))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(designSystem.colors.primaryWhite)
                Spacer()
                Image(systemName: metricType.icon)
                    .font(.caption2)
                    .foregroundColor(designSystem.colors.primaryWhite)
            }

            Text(valueText)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(designSystem.colors.primaryWhite)
        }
        .padding(designSystem.spacing.sm)
        .background(metricType.color)
        .clipShape(RoundedRectangle(cornerRadius: designSystem.cornerRadius.small + 2))
        .overlay(
            Path { path in
                let arrowWidth: CGFloat = 8
                let arrowHeight: CGFloat = 4
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: arrowWidth/2, y: arrowHeight))
                path.addLine(to: CGPoint(x: arrowWidth, y: 0))
                path.closeSubpath()
            }
            .fill(metricType.color)
            .offset(y: 6)
            .frame(width: 8, height: 4),
            alignment: .bottom
        )
    }
}
