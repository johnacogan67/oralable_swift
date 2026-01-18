//
//  HistoricalView.swift
//  OralableApp
//
//  Historical data visualization with Hour/Day tabs and navigation.
//
//  Features:
//  - Two-tab selector (Hour, Day)
//  - Hour tab: Hour-by-hour chart with hourly navigation
//  - Day tab: Day-by-day chart with daily navigation
//  - Metric tab selector (EMG, IR, Movement, Temperature)
//  - Data summary card (min, max, average)
//
//  Design: Apple-inspired black/white, light mode default
//
//  Updated: January 16, 2026 - Added Hour/Day tabs with navigation
//

import SwiftUI
import Charts

/// Time period for historical view
enum HistoricalTimePeriod: String, CaseIterable {
    case hour = "Hour"
    case day = "Day"

    var icon: String {
        switch self {
        case .hour: return "clock"
        case .day: return "calendar"
        }
    }
}

/// Metric types available for viewing
enum HistoryMetricTab: String, CaseIterable {
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

struct HistoricalView: View {
    @EnvironmentObject var designSystem: DesignSystem

    // Time period tab (Hour/Day)
    @State private var selectedTimePeriod: HistoricalTimePeriod = .day

    // Selected metric tab
    @State private var selectedTab: HistoryMetricTab = .emg

    // Navigation date
    @State private var selectedDate: Date = Date()

    // Session data points loaded from CSV
    @State private var dataPoints: [HistoricalDataPoint] = []

    // Export file info
    @State private var loadedExportFile: SessionDataLoader.ExportFileInfo?

    // Loading state
    @State private var isLoading: Bool = false

    // Initial metric type passed from dashboard (optional)
    let initialMetricType: String?

    init(metricType: String? = nil) {
        self.initialMetricType = metricType
        Logger.shared.info("[HistoricalView] Initialized with metricType: \(metricType ?? "none")")
    }

    // MARK: - Computed Properties

    private var hasData: Bool {
        !dataPoints.isEmpty
    }

    private var hasExportFiles: Bool {
        loadedExportFile != nil || SessionDataLoader.shared.getMostRecentExportFile() != nil
    }

    /// Tabs that have data available - only show tabs with actual recorded data
    private var availableTabs: [HistoryMetricTab] {
        var tabs: [HistoryMetricTab] = []

        // Check EMG data - uses averagePPGIR field when device is ANR
        // EMG data comes from ANR M40 device (no temperature, no PPG colors)
        let hasEMGData = dataPoints.contains { point in
            point.averagePPGIR != nil && point.averageTemperature == 0 && point.averagePPGRed == nil
        }
        if hasEMGData { tabs.append(.emg) }

        // Check IR data - uses averagePPGIR field when device is Oralable
        // IR/PPG data comes from Oralable device (has temperature or PPG colors)
        let hasIRData = dataPoints.contains { point in
            point.averagePPGIR != nil && (point.averageTemperature > 0 || point.averagePPGRed != nil || point.averagePPGGreen != nil)
        }
        if hasIRData { tabs.append(.ir) }

        // Check Movement data - movementIntensity > 0
        let hasMovementData = dataPoints.contains { point in
            point.movementIntensity > 0.001  // Small threshold to filter out noise
        }
        if hasMovementData { tabs.append(.move) }

        // Check Temperature data - averageTemperature > 0
        let hasTempData = dataPoints.contains { point in
            point.averageTemperature > 0
        }
        if hasTempData { tabs.append(.temp) }

        // If no data for any tab, return all tabs (show empty states)
        return tabs.isEmpty ? HistoryMetricTab.allCases : tabs
    }

    /// X-axis domain based on selected time period
    private var xAxisDomain: ClosedRange<Date> {
        let calendar = Calendar.current

        switch selectedTimePeriod {
        case .hour:
            // Show one hour
            guard let hourStart = calendar.dateInterval(of: .hour, for: selectedDate)?.start else {
                return selectedDate...selectedDate.addingTimeInterval(3600)
            }
            let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? hourStart
            return hourStart...hourEnd

        case .day:
            // Show one day (midnight to midnight)
            let startOfDay = calendar.startOfDay(for: selectedDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return startOfDay...endOfDay
        }
    }

    /// Filtered data points for the selected time period
    private var filteredDataPoints: [HistoricalDataPoint] {
        let calendar = Calendar.current

        switch selectedTimePeriod {
        case .hour:
            guard let hourInterval = calendar.dateInterval(of: .hour, for: selectedDate) else {
                return []
            }
            return dataPoints.filter { hourInterval.contains($0.timestamp) }

        case .day:
            return dataPoints.filter { calendar.isDate($0.timestamp, inSameDayAs: selectedDate) }
        }
    }

    /// Display text for current navigation
    private var navigationDisplayText: String {
        let formatter = DateFormatter()

        switch selectedTimePeriod {
        case .hour:
            formatter.dateFormat = "HH:00 - HH:59, dd MMM"
            return formatter.string(from: selectedDate)

        case .day:
            formatter.dateFormat = "EEEE, dd MMMM yyyy"
            return formatter.string(from: selectedDate)
        }
    }

    /// Check if can navigate forward (don't go past current time)
    private var canNavigateForward: Bool {
        let calendar = Calendar.current
        let now = Date()

        switch selectedTimePeriod {
        case .hour:
            guard let currentHourStart = calendar.dateInterval(of: .hour, for: selectedDate)?.start,
                  let nowHourStart = calendar.dateInterval(of: .hour, for: now)?.start else {
                return false
            }
            return currentHourStart < nowHourStart

        case .day:
            return !calendar.isDate(selectedDate, inSameDayAs: now)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Time period selector (Hour/Day)
            timePeriodSelector
                .padding(.horizontal, 16)
                .padding(.top, 12)

            // Navigation (back/forward)
            navigationBar
                .padding(.horizontal, 16)
                .padding(.top, 12)

            // Metric tab selector
            metricTabSelector
                .padding(.horizontal, 16)
                .padding(.top, 16)

            ScrollView {
                VStack(spacing: 20) {
                    // Export file info banner
                    if let exportFile = loadedExportFile {
                        exportInfoBanner(exportFile: exportFile)
                    }

                    // Chart or empty state
                    if isLoading {
                        loadingView
                    } else if hasData && !filteredDataPoints.isEmpty {
                        metricChart
                        dataSummaryCard
                    } else {
                        emptyStateView
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(.systemBackground))
        .onAppear {
            setInitialTab()
            loadExportData()
        }
        .onChange(of: selectedTab) { _, newTab in
            // Validate tab is still available
            if availableTabs.contains(newTab) {
                loadExportData()
            } else if let firstTab = availableTabs.first {
                selectedTab = firstTab
            }
        }
    }

    // MARK: - Time Period Selector

    private var timePeriodSelector: some View {
        HStack(spacing: 0) {
            ForEach(HistoricalTimePeriod.allCases, id: \.self) { period in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTimePeriod = period
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: period.icon)
                            .font(.system(size: 14))
                        Text(period.rawValue)
                            .font(.system(size: 15, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedTimePeriod == period ? Color.black : Color.clear)
                    .foregroundColor(selectedTimePeriod == period ? .white : .primary)
                }
            }
        }
        .background(Color(.systemGray5))
        .cornerRadius(10)
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Back button
            Button(action: navigateBackward) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }

            Spacer()

            // Current period display
            VStack(spacing: 2) {
                Text(navigationDisplayText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Text(selectedTimePeriod == .hour ? "Hour View" : "Day View")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Forward button
            Button(action: navigateForward) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(canNavigateForward ? .primary : .gray)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .disabled(!canNavigateForward)
        }
    }

    // MARK: - Navigation Actions

    private func navigateBackward() {
        let calendar = Calendar.current

        switch selectedTimePeriod {
        case .hour:
            selectedDate = calendar.date(byAdding: .hour, value: -1, to: selectedDate) ?? selectedDate
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        }
    }

    private func navigateForward() {
        guard canNavigateForward else { return }

        let calendar = Calendar.current

        switch selectedTimePeriod {
        case .hour:
            selectedDate = calendar.date(byAdding: .hour, value: 1, to: selectedDate) ?? selectedDate
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
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
                    .foregroundColor(selectedTab == tab ? tab.chartColor : .secondary)
                }
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Export Info Banner

    private func exportInfoBanner(exportFile: SessionDataLoader.ExportFileInfo) -> some View {
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
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Metric Chart

    private var metricChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(selectedTab.metricType)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if let latestValue = getLatestValue() {
                    Text(formatValue(latestValue))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            // Chart
            chartForSelectedTab
                .frame(height: 250)
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
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

    private var movementChart: some View {
        Chart(filteredDataPoints) { point in
            PointMark(
                x: .value("Time", point.timestamp),
                y: .value("Acceleration", point.movementIntensity)
            )
            .foregroundStyle(point.isAtRest ? Color.green.opacity(0.6) : Color.orange)
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

    private var temperatureChart: some View {
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
    private var xAxisValues: AxisMarkValues {
        switch selectedTimePeriod {
        case .hour:
            return .stride(by: .minute, count: 10)
        case .day:
            return .stride(by: .hour, count: 3)
        }
    }

    /// X-axis date format based on time period
    private var xAxisDateFormat: Date.FormatStyle {
        switch selectedTimePeriod {
        case .hour:
            return .dateTime.minute()
        case .day:
            return .dateTime.hour()
        }
    }

    // MARK: - Data Summary Card

    private var dataSummaryCard: some View {
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
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func summaryItem(title: String, value: String) -> some View {
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

    private var loadingView: some View {
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

    private var emptyStateView: some View {
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

    private var emptyStateTitle: String {
        if !hasExportFiles {
            return "No Exports"
        }
        if filteredDataPoints.isEmpty && hasData {
            return "No Data for This Period"
        }
        return "No \(selectedTab.rawValue) Data"
    }

    private var emptyStateMessage: String {
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

    // MARK: - Helper Methods

    private func setInitialTab() {
        // If initial metric type specified, try to use it
        if let initial = initialMetricType {
            switch initial {
            case "EMG Activity":
                if availableTabs.contains(.emg) {
                    selectedTab = .emg
                    return
                }
            case "IR Activity", "Muscle Activity", "PPG":
                if availableTabs.contains(.ir) {
                    selectedTab = .ir
                    return
                }
            case "Movement":
                if availableTabs.contains(.move) {
                    selectedTab = .move
                    return
                }
            case "Temperature":
                if availableTabs.contains(.temp) {
                    selectedTab = .temp
                    return
                }
            default:
                break
            }
        }

        // Default to first available tab
        if let firstTab = availableTabs.first {
            selectedTab = firstTab
        }
    }

    private func loadExportData() {
        isLoading = true
        dataPoints = []

        // DEBUG: List files
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        Logger.shared.info("[HistoricalView] Documents path: \(documentsPath.path)")

        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            Logger.shared.info("[HistoricalView] Found \(files.count) files in Documents")

            let csvFiles = files.filter {
                $0.pathExtension == "csv" && $0.lastPathComponent.hasPrefix("oralable_data_")
            }
            Logger.shared.info("[HistoricalView] Matching CSV files: \(csvFiles.count)")
        } catch {
            Logger.shared.error("[HistoricalView] Failed to list documents: \(error)")
        }

        // Get export file
        loadedExportFile = SessionDataLoader.shared.getMostRecentExportFile()
        Logger.shared.info("[HistoricalView] Export file found: \(loadedExportFile?.url.lastPathComponent ?? "NONE")")

        if let _ = loadedExportFile {
            Logger.shared.info("[HistoricalView] Calling loadFromMostRecentExport for metric: \(selectedTab.metricType)")
            let points = SessionDataLoader.shared.loadFromMostRecentExport(metricType: selectedTab.metricType)
            Logger.shared.info("[HistoricalView] Loaded \(points.count) data points")

            dataPoints = points

            // Set selected date to the date of the data
            if let firstPoint = points.first {
                selectedDate = firstPoint.timestamp
            }

            // Update selected tab if current selection has no data
            if !availableTabs.contains(selectedTab), let firstTab = availableTabs.first {
                selectedTab = firstTab
            }
        } else {
            Logger.shared.warning("[HistoricalView] No export files found")
        }

        isLoading = false
    }

    private func getLatestValue() -> Double? {
        guard let lastPoint = filteredDataPoints.last else { return nil }

        switch selectedTab {
        case .emg, .ir:
            return lastPoint.averagePPGIR
        case .move:
            return lastPoint.movementIntensity
        case .temp:
            return lastPoint.averageTemperature > 0 ? lastPoint.averageTemperature : nil
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
            return filteredDataPoints.compactMap { $0.averagePPGIR }
        case .move:
            return filteredDataPoints.map { $0.movementIntensity }
        case .temp:
            return filteredDataPoints.map { $0.averageTemperature }.filter { $0 > 0 }
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

// MARK: - Preview

struct HistoricalView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            HistoricalView()
                .environmentObject(DesignSystem())
        }
    }
}
