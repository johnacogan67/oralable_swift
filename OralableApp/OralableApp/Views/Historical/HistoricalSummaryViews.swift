//
//  HistoricalSummaryViews.swift
//  OralableApp
//
//  Summary, loading, empty state, and export info views
//  for HistoricalView.
//
//  Extracted from HistoricalView.swift
//

import SwiftUI

extension HistoricalView {

    // MARK: - Data Summary Card

    var dataSummaryCard: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.buttonPadding) {
            Text("Summary")
                .font(designSystem.typography.headline)
                .foregroundColor(designSystem.colors.textPrimary)

            HStack(spacing: 16) {
                summaryItem(title: "Min", value: formatValue(getMinValue()))
                Divider().frame(height: 40)
                summaryItem(title: "Avg", value: formatValue(getAverageValue()))
                Divider().frame(height: 40)
                summaryItem(title: "Max", value: formatValue(getMaxValue()))
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.card)
    }

    func summaryItem(title: String, value: String) -> some View {
        VStack(spacing: designSystem.spacing.xs) {
            Text(title)
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading View

    var loadingView: some View {
        VStack(spacing: designSystem.spacing.md) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading data...")
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(designSystem.spacing.xl + designSystem.spacing.sm)
    }

    // MARK: - Empty State

    var emptyStateView: some View {
        VStack(spacing: designSystem.spacing.md) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(designSystem.colors.textSecondary)

            Text(emptyStateTitle)
                .font(designSystem.typography.headline)

            Text(emptyStateMessage)
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(designSystem.spacing.xl + designSystem.spacing.sm)
    }

    var emptyStateTitle: String {
        if !hasExportFiles {
            return "No Exports"
        }
        if filteredDataPoints.isEmpty && hasData {
            return "No Data for This Period"
        }
        return "No \(selectedTab.rawValue) Data"
    }

    var emptyStateMessage: String {
        if !hasExportFiles {
            return "Use the Share tab to export sensor data, then view it here."
        }

        if filteredDataPoints.isEmpty && hasData {
            return "Navigate to a different \(selectedTimePeriod.rawValue.lowercased()) to view data."
        }

        switch selectedTab {
        case .emg:
            return "No EMG data found in the export. Connect an ANR M40 device and export data."
        case .ir:
            return "No IR data found in the export. Connect an Oralable device and export data."
        case .move:
            return "No movement data found in the export."
        case .temp:
            return "No temperature data found in the export. Temperature is only recorded by the Oralable device."
        }
    }

    // MARK: - Export Info Banner

    func exportInfoBanner(exportFile: SessionDataLoader.ExportFileInfo) -> some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(designSystem.colors.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(exportFile.url.lastPathComponent)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("\(filteredDataPoints.count) points in view")
                    .font(designSystem.typography.caption2)
                    .foregroundColor(designSystem.colors.textSecondary)
            }

            Spacer()

            let sizeKB = Double(exportFile.fileSize) / 1024.0
            Text(String(format: "%.1f KB", sizeKB))
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
        }
        .padding(designSystem.spacing.buttonPadding)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.medium)
    }
}
