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
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)
                .foregroundColor(.primary)

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
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading View

    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading data...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Empty State

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(emptyStateTitle)
                .font(.headline)

            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
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
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(exportFile.url.lastPathComponent)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("\(filteredDataPoints.count) points in view")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            let sizeKB = Double(exportFile.fileSize) / 1024.0
            Text(String(format: "%.1f KB", sizeKB))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(designSystem.spacing.buttonPadding)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.medium)
    }
}
