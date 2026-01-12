//
//  PatientHistoricalView.swift
//  OralableForProfessionals
//
//  Historical chart view for patient session data.
//
//  Features:
//  - Multi-metric chart display
//  - Time range selection
//  - Session comparison
//  - Export functionality
//
//  Charts:
//  - Activity chart (PPG IR)
//  - Movement chart (accelerometer)
//  - Temperature chart
//
//  Similar to consumer HistoricalView but with
//  professional-specific analysis features.
//
//  Updated: December 9, 2025 - Simplified to match patient app
//

import SwiftUI
import Charts

/// Metric types available for viewing - mirrors OralableApp's HistoryMetricTab
enum PatientHistoryMetricTab: String, CaseIterable {
    case emg = "EMG"
    case ir = "IR"
    case move = "Move"
    case temp = "Temp"

    var metricType: String {
        switch self {
        case .emg: return "EMG Activity"
        case .ir: return "IR Activity"
        case .move: return "Movement"
        case .temp: return "Temperature"
        }
    }

    var chartColor: Color {
        switch self {
        case .emg: return .blue
        case .ir: return .purple
        case .move: return .green
        case .temp: return .orange
        }
    }

    var icon: String {
        switch self {
        case .emg: return "bolt.horizontal.circle.fill"
        case .ir: return "waveform.path.ecg"
        case .move: return "gyroscope"
        case .temp: return "thermometer"
        }
    }

    var unit: String {
        switch self {
        case .emg: return "µV"
        case .ir: return "ADC"
        case .move: return "g"
        case .temp: return "°C"
        }
    }
}

struct PatientHistoricalView: View {
    let patient: ProfessionalPatient

    @StateObject private var viewModel: PatientHistoricalViewModel
    @EnvironmentObject var designSystem: DesignSystem

    // Selected metric tab - matches patient app
    @State private var selectedTab: PatientHistoryMetricTab = .ir

    /// Tabs that have data available - only show tabs with actual recorded data
    private var availableTabs: [PatientHistoryMetricTab] {
        var tabs: [PatientHistoryMetricTab] = []

        // Check EMG data - from ANR M40 device
        let hasEMGData = viewModel.allSensorData.contains { $0.isANRDevice && ($0.emgValue ?? 0) > 0 }
        if hasEMGData { tabs.append(.emg) }

        // Check IR data - from Oralable device
        let hasIRData = viewModel.allSensorData.contains { $0.isOralableDevice && ($0.ppgIRValue ?? 0) > 0 }
        if hasIRData { tabs.append(.ir) }

        // Check Movement data - from Oralable device
        let hasMovementData = viewModel.allSensorData.contains { $0.isOralableDevice && $0.accelMagnitude > 0.001 }
        if hasMovementData { tabs.append(.move) }

        // Check Temperature data - from Oralable device
        let hasTempData = viewModel.allSensorData.contains { $0.isOralableDevice && $0.temperatureCelsius > 0 }
        if hasTempData { tabs.append(.temp) }

        // If no data for any tab, return all tabs (show empty states)
        return tabs.isEmpty ? PatientHistoryMetricTab.allCases : tabs
    }

    init(patient: ProfessionalPatient) {
        self.patient = patient
        _viewModel = StateObject(wrappedValue: PatientHistoricalViewModel(patient: patient))
    }

    // MARK: - Date Format

    private var xAxisDateFormat: Date.FormatStyle {
        guard !viewModel.dataPoints.isEmpty else {
            return .dateTime.hour().minute().second()
        }

        // Check data span to determine format
        if let first = viewModel.dataPoints.first?.timestamp,
           let last = viewModel.dataPoints.last?.timestamp {
            let duration = last.timeIntervalSince(first)
            if duration < 60 {
                return .dateTime.hour().minute().second()
            } else if duration < 3600 {
                return .dateTime.hour().minute()
            }
        }

        return .dateTime.hour().minute()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Metric tab selector - matches patient app
            metricTabSelector
                .padding(.horizontal, designSystem.spacing.md)
                .padding(.top, designSystem.spacing.sm)

            ScrollView {
                VStack(spacing: designSystem.spacing.lg) {
                    // Patient info banner
                    patientInfoBanner

                    // Data info banner (like patient app's export file banner)
                    if !viewModel.dataPoints.isEmpty {
                        dataInfoBanner
                    }

                    // Chart or loading/empty state
                    if viewModel.isLoading {
                        loadingView
                    } else if !viewModel.dataPoints.isEmpty {
                        metricChart
                        dataSummaryCard
                    } else {
                        emptyStateView
                    }
                }
                .padding(designSystem.spacing.md)
            }
            .refreshable {
                // Pull-to-refresh: reload all patient data from CloudKit
                await viewModel.loadAllData()
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .task {
            // Set initial metric type before loading
            viewModel.updateMetricType(selectedTab.metricType)
            await viewModel.loadAllData()

            // After data loads, set initial tab to first available if current is invalid
            if !availableTabs.contains(selectedTab), let firstTab = availableTabs.first {
                selectedTab = firstTab
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            // Validate tab is still available
            if availableTabs.contains(newTab) {
                viewModel.updateMetricType(newTab.metricType)
            } else if let firstTab = availableTabs.first {
                selectedTab = firstTab
            }
        }
    }

    // MARK: - Metric Tab Selector

    private var metricTabSelector: some View {
        HStack(spacing: 0) {
            ForEach(availableTabs, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16))
                        Text(tab.rawValue)
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedTab == tab ? tab.chartColor.opacity(0.15) : Color.clear)
                    .foregroundColor(selectedTab == tab ? tab.chartColor : designSystem.colors.textSecondary)
                }
            }
        }
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.medium)
    }

    // MARK: - Patient Info Banner

    private var patientInfoBanner: some View {
        HStack(spacing: designSystem.spacing.sm) {
            // Patient avatar
            Circle()
                .fill(designSystem.colors.backgroundTertiary)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(patient.displayInitials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(designSystem.colors.textSecondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(patient.displayName)
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.textPrimary)

                Text("Connected \(formattedDate(patient.accessGrantedDate))")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textTertiary)
            }

            Spacer()
        }
        .padding(designSystem.spacing.sm)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.medium)
    }

    // MARK: - Data Info Banner (mirrors patient app's export info banner)

    private var dataInfoBanner: some View {
        VStack(spacing: designSystem.spacing.xs) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14))
                    .foregroundColor(designSystem.colors.textSecondary)

                Text("Shared Data")
                    .font(.caption.bold())
                    .foregroundColor(designSystem.colors.textPrimary)

                Spacer()

                Text("\(viewModel.dataPoints.count) points")
                    .font(.caption)
                    .foregroundColor(designSystem.colors.textTertiary)
            }

            HStack {
                if let dateRange = viewModel.dataDateRange {
                    Text(dateRange)
                        .font(.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                }

                Spacer()

                if let lastUpdate = patient.lastDataUpdate {
                    Text("Updated: \(relativeDate(lastUpdate))")
                        .font(.caption)
                        .foregroundColor(designSystem.colors.textTertiary)
                }
            }
        }
        .padding(designSystem.spacing.sm)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.medium)
    }

    // MARK: - Metric Chart

    private var metricChart: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            // Header
            HStack {
                Text(selectedTab.metricType)
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.textPrimary)

                Spacer()

                // Latest value
                if let latestValue = getLatestValue() {
                    Text(formatValue(latestValue))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }

            // Chart based on selected tab
            chartForSelectedTab
                .frame(height: 250)
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.large)
    }

    @ViewBuilder
    private var chartForSelectedTab: some View {
        switch selectedTab {
        case .emg, .ir:
            activityChart
        case .move:
            movementChart
        case .temp:
            temperatureChart
        }
    }

    private var activityChart: some View {
        Chart(viewModel.dataPoints) { point in
            if let value = point.averagePPGIR {
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Activity", value)
                )
                .foregroundStyle(selectedTab.chartColor)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: xAxisDateFormat)
            }
        }
    }

    private var movementChart: some View {
        Chart(viewModel.dataPoints) { point in
            PointMark(
                x: .value("Time", point.timestamp),
                y: .value("Acceleration", point.movementIntensity)
            )
            .foregroundStyle(point.movementIntensity < 0.1 ? Color.blue.opacity(0.6) : Color.green.opacity(0.8))
            .symbolSize(10)
        }
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
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: xAxisDateFormat)
            }
        }
    }

    private var temperatureChart: some View {
        Chart(viewModel.dataPoints) { point in
            if let temp = point.averageTemperature, temp > 0 {
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Temperature", temp)
                )
                .foregroundStyle(selectedTab.chartColor)
            }
        }
        .chartYScale(domain: 30...42)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let temp = value.as(Double.self) {
                        Text(String(format: "%.0f°", temp))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: xAxisDateFormat)
            }
        }
    }

    // MARK: - Data Summary Card

    private var dataSummaryCard: some View {
        VStack(spacing: designSystem.spacing.sm) {
            HStack {
                Text("Summary")
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.textPrimary)
                Spacer()
            }

            HStack(spacing: designSystem.spacing.md) {
                summaryItem(title: "Min", value: formatValue(getMinValue()))
                summaryItem(title: "Max", value: formatValue(getMaxValue()))
                summaryItem(title: "Avg", value: formatValue(getAverageValue()))
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.large)
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(designSystem.colors.textTertiary)
            Text(value)
                .font(.system(.body, design: .monospaced).bold())
                .foregroundColor(designSystem.colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, designSystem.spacing.sm)
        .background(designSystem.colors.backgroundTertiary)
        .cornerRadius(designSystem.cornerRadius.small)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: designSystem.spacing.md) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading participant data...")
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(designSystem.spacing.xl)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: designSystem.spacing.lg) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                .font(.system(size: 60))
                .foregroundColor(designSystem.colors.textTertiary)

            Text(emptyStateTitle)
                .font(designSystem.typography.h2)
                .foregroundColor(designSystem.colors.textPrimary)

            Text(emptyStateMessage)
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(designSystem.spacing.xl)
    }

    private var emptyStateTitle: String {
        "No Data Available"
    }

    private var emptyStateMessage: String {
        switch selectedTab {
        case .emg:
            return "This participant hasn't shared any EMG data yet. They need to connect an ANR M40 device and share data with you."
        case .ir:
            return "This participant hasn't shared any IR/PPG data yet. They need to record a session and share it with you."
        case .move:
            return "This participant hasn't shared any movement data yet."
        case .temp:
            return "This participant hasn't shared any temperature data yet."
        }
    }

    // MARK: - Helper Methods

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func getLatestValue() -> Double? {
        guard let lastPoint = viewModel.dataPoints.last else { return nil }

        switch selectedTab {
        case .emg, .ir:
            return lastPoint.averagePPGIR
        case .move:
            return lastPoint.movementIntensity
        case .temp:
            return lastPoint.averageTemperature
        }
    }

    private func getMinValue() -> Double? {
        let values = getValuesForSelectedTab()
        return values.min()
    }

    private func getMaxValue() -> Double? {
        let values = getValuesForSelectedTab()
        return values.max()
    }

    private func getAverageValue() -> Double? {
        let values = getValuesForSelectedTab()
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func getValuesForSelectedTab() -> [Double] {
        switch selectedTab {
        case .emg, .ir:
            return viewModel.dataPoints.compactMap { $0.averagePPGIR }
        case .move:
            return viewModel.dataPoints.map { $0.movementIntensity }
        case .temp:
            return viewModel.dataPoints.compactMap { $0.averageTemperature }.filter { $0 > 0 }
        }
    }

    private func formatValue(_ value: Double?) -> String {
        guard let value = value else { return "--" }

        switch selectedTab {
        case .emg:
            return String(format: "%.0f %@", value, selectedTab.unit)
        case .ir:
            return String(format: "%.0f %@", value, selectedTab.unit)
        case .move:
            return String(format: "%.2f %@", value, selectedTab.unit)
        case .temp:
            return String(format: "%.1f%@", value, selectedTab.unit)
        }
    }
}
