import SwiftUI

// MARK: - Statistics Card Component
struct HistoricalStatisticsCard: View {
    let metricType: MetricType
    let processed: HistoricalDataProcessor.ProcessedHistoricalData?

    private func formatValue(_ value: Double) -> String {
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
        VStack(alignment: .leading, spacing: 16) {
            if let stats = processed?.statistics, stats.sampleCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Average")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(formatValue(stats.average))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(metricType.color)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Average \(metricType.title): \(formatValue(stats.average))")

                Divider()

                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Minimum")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatValue(stats.minimum))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Minimum: \(formatValue(stats.minimum))")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Maximum")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatValue(stats.maximum))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Maximum: \(formatValue(stats.maximum))")

                    Spacer()
                }

                Divider()

                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Std Dev")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatValue(stats.standardDeviation))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coeff. Variation")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f%%", stats.variationCoefficient))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    Text("\(stats.sampleCount) pts")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Standard deviation: \(formatValue(stats.standardDeviation)), coefficient of variation: \(String(format: "%.1f percent", stats.variationCoefficient)), \(stats.sampleCount) data points")
            } else {
                Text("No statistics available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(metricType.title) statistics")
    }
}
