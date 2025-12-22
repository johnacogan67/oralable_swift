import SwiftUI

// MARK: - Recent Logs Component
struct ShareRecentLogsView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @ObservedObject var loggingService: AppLoggingService

    private var recentLogs: [LogEntry] {
        Array(loggingService.recentLogs.suffix(10).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            HStack {
                Label("Recent Activity", systemImage: "clock")
                    .font(designSystem.typography.h3)
                    .foregroundColor(designSystem.colors.textPrimary)

                Spacer()

                Text("Last \(min(10, loggingService.recentLogs.count))")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textTertiary)
            }

            Divider()

            if loggingService.recentLogs.isEmpty {
                VStack(spacing: designSystem.spacing.sm) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundColor(designSystem.colors.textDisabled)

                    Text("No activity yet")
                        .font(designSystem.typography.bodyMedium)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, designSystem.spacing.xl)
            } else {
                VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
                    ForEach(recentLogs) { log in
                        HStack(alignment: .top, spacing: designSystem.spacing.sm) {
                            Circle()
                                .fill(logColor(for: log.message))
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)

                            Text(log.message)
                                .font(designSystem.typography.bodySmall)
                                .foregroundColor(designSystem.colors.textSecondary)
                                .lineLimit(2)

                            Spacer()
                        }
                        .padding(.vertical, designSystem.spacing.xxs)
                    }
                }
            }
        }
        .padding(designSystem.spacing.lg)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.lg)
        .designShadow(DesignSystem.Shadow.sm)
    }

    private func logColor(for log: String) -> Color {
        if log.contains("ERROR") || log.contains("Failed") || log.contains("❌") {
            return .red
        } else if log.contains("WARNING") || log.contains("Disconnected") || log.contains("⚠️") {
            return .orange
        } else if log.contains("Connected") || log.contains("SUCCESS") || log.contains("✅") {
            return .green
        } else {
            return .blue
        }
    }
}
