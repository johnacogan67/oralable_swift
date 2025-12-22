import SwiftUI

// MARK: - Data Summary Card Component
struct ShareDataSummaryCard: View {
    @EnvironmentObject var designSystem: DesignSystem
    @ObservedObject var sensorDataProcessor: SensorDataProcessor

    // MARK: - Computed Properties
    
    private var durationValue: String {
        guard !sensorDataProcessor.sensorDataHistory.isEmpty,
              let first = sensorDataProcessor.sensorDataHistory.first,
              let last = sensorDataProcessor.sensorDataHistory.last else {
            return "0"
        }
        
        let duration = last.timestamp.timeIntervalSince(first.timestamp)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)"
        } else {
            return "\(minutes)"
        }
    }
    
    private var durationSubtitle: String {
        guard !sensorDataProcessor.sensorDataHistory.isEmpty,
              let first = sensorDataProcessor.sensorDataHistory.first,
              let last = sensorDataProcessor.sensorDataHistory.last else {
            return "minutes"
        }
        
        let duration = last.timestamp.timeIntervalSince(first.timestamp)
        let hours = Int(duration) / 3600
        
        return hours > 0 ? "hours" : "minutes"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            Text("Data Summary")
                .font(designSystem.typography.h3)
                .foregroundColor(designSystem.colors.textPrimary)

            Divider()

            // Metrics Grid
            HStack(spacing: designSystem.spacing.lg) {
                ShareMetricBox(
                    title: "Sensor Data",
                    value: "\(sensorDataProcessor.sensorDataHistory.count)",
                    subtitle: "points",
                    icon: "waveform.path.ecg",
                    color: .blue
                )

                ShareMetricBox(
                    title: "Duration",
                    value: durationValue,
                    subtitle: durationSubtitle,
                    icon: "clock",
                    color: .green
                )
            }

            if !sensorDataProcessor.sensorDataHistory.isEmpty,
               let first = sensorDataProcessor.sensorDataHistory.first,
               let last = sensorDataProcessor.sensorDataHistory.last {
                Divider()

                VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
                    Label("Recording Period", systemImage: "clock")
                        .font(designSystem.typography.labelMedium)
                        .foregroundColor(designSystem.colors.textSecondary)

                    HStack {
                        Text(first.timestamp, style: .date)
                        Image(systemName: "arrow.right")
                        Text(last.timestamp, style: .date)
                    }
                    .font(designSystem.typography.bodySmall)
                    .foregroundColor(designSystem.colors.textTertiary)
                }
            }
        }
        .padding(designSystem.spacing.lg)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.lg)
        .designShadow(DesignSystem.Shadow.sm)
    }
}

struct ShareMetricBox: View {
    @EnvironmentObject var designSystem: DesignSystem
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
            HStack(spacing: designSystem.spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: DesignSystem.Sizing.Icon.sm))
                    .foregroundColor(color)

                Text(title)
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(designSystem.typography.displaySmall)
                    .foregroundColor(color)

                Text(subtitle)
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(designSystem.spacing.md)
        .background(color.opacity(0.1))
        .cornerRadius(designSystem.cornerRadius.md)
    }
}
