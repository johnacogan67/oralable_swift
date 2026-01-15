//
//  SharedComponents.swift
//  OralableForProfessionals
//
//  Reusable UI components matching OralableApp style
//  Updated: January 15, 2026 - Use ColorSystem from OralableCore
//

import SwiftUI
import Charts
import OralableCore

// MARK: - Health Metric Card (Apple Health Style)

struct HealthMetricCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color
    var subtitle: String? = nil
    var sparklineData: [Double] = []
    var showChevron: Bool = false

    private let colors = OralableCore.DesignSystem.shared.colors

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)

                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colors.textTertiary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(colors.textPrimary)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                if !sparklineData.isEmpty {
                    MiniSparkline(data: sparklineData, color: color)
                        .frame(width: 60, height: 24)
                }
            }

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
            }
        }
        .padding(16)
        .background(colors.backgroundPrimary)
        .cornerRadius(12)
        .shadow(color: colors.shadow, radius: 4, x: 0, y: 2)
    }
}

// MARK: - Mini Sparkline Chart

struct MiniSparkline: View {
    let data: [Double]
    let color: Color

    var body: some View {
        if data.count >= 2 {
            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Index", index),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(color.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
    }
}

// MARK: - Summary Metric Card

struct SummaryMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var trend: Double? = nil

    private let colors = OralableCore.DesignSystem.shared.colors

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(colors.textSecondary)

                HStack(spacing: 8) {
                    Text(value)
                        .font(.title2.bold())
                        .foregroundColor(colors.textPrimary)

                    if let trend = trend {
                        TrendIndicator(value: trend)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(colors.backgroundPrimary)
        .cornerRadius(12)
        .shadow(color: colors.shadow, radius: 2, x: 0, y: 1)
    }
}

// MARK: - Trend Indicator

struct TrendIndicator: View {
    let value: Double

    private let colors = OralableCore.DesignSystem.shared.colors

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))

            Text(String(format: "%.0f%%", abs(value)))
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(value >= 0 ? colors.error : colors.success)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((value >= 0 ? colors.error : colors.success).opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Session Row Card

struct SessionRowCard: View {
    let date: Date
    let duration: TimeInterval
    let bruxismEvents: Int
    let peakIntensity: Double

    private let colors = OralableCore.DesignSystem.shared.colors

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate(date))
                    .font(.headline)
                    .foregroundColor(colors.textPrimary)

                Text(formattedDuration(duration))
                    .font(.caption)
                    .foregroundColor(colors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(bruxismEvents)")
                        .font(.headline)
                        .foregroundColor(colors.error)

                    Text("events")
                        .font(.caption)
                        .foregroundColor(colors.textSecondary)
                }

                Text(String(format: "Peak: %.1f", peakIntensity))
                    .font(.caption)
                    .foregroundColor(colors.textSecondary)
            }
        }
        .padding()
        .background(colors.backgroundPrimary)
        .cornerRadius(10)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil

    private let colors = OralableCore.DesignSystem.shared.colors

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(colors.textSecondary)

            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundColor(colors.textPrimary)

                Text(message)
                    .font(.body)
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            if let buttonTitle = buttonTitle, let action = buttonAction {
                Button(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text(buttonTitle)
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(colors.primaryWhite)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(colors.primaryBlack)
                    .cornerRadius(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Loading View

struct LoadingView: View {
    let message: String

    private let colors = OralableCore.DesignSystem.shared.colors

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text(message)
                .font(.subheadline)
                .foregroundColor(colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionTitle: String? = nil

    private let colors = OralableCore.DesignSystem.shared.colors

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
                .foregroundColor(colors.textPrimary)

            Spacer()

            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline)
                        .foregroundColor(colors.info)
                }
            }
        }
        .padding(.horizontal)
    }
}
