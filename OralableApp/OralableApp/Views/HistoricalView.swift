//
//  HistoricalView.swift
//  OralableApp
//
//  Historical data visualization from exported CSV sessions.
//
//  Features:
//  - Metric tab selector (EMG, IR, Movement, Temperature)
//  - Chart displaying data over time
//  - X-axis spans full day (midnight to midnight)
//  - Data summary card (min, max, average)
//  - Loads from most recent CSV export file
//
//  Chart Types:
//  - Activity chart: Line chart for PPG data
//  - Movement chart: Point chart with rest/active coloring
//  - Temperature chart: Line chart with 30-42°C range
//
//  Data Source: CSV files in Documents directory
//
//  Updated: December 8, 2025 - Load from ShareView exports instead of RecordingSessions
//  Updated: December 8, 2025 - Fixed movement chart to use movementIntensity directly (already in g units)
//

import SwiftUI
import Charts

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

    // Selected metric tab
    @State private var selectedTab: HistoryMetricTab = .emg
    
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

    /// Date format for x-axis labels
    private var xAxisDateFormat: Date.FormatStyle {
        if loadedExportFile != nil {
            // Check data span to determine format
            if let first = dataPoints.first?.timestamp, let last = dataPoints.last?.timestamp {
                let duration = last.timeIntervalSince(first)
                if duration > 3600 * 24 { // More than a day
                    return .dateTime.month().day()
                } else if duration > 3600 { // More than an hour
                    return .dateTime.hour().minute()
                }
            }
        }
        return .dateTime.hour().minute().second()
    }

    /// X-axis domain - always show full day (midnight to midnight)
    private var xAxisDomain: ClosedRange<Date> {
        let calendar = Calendar.current

        // Use first data point's date, or today if no data
        let referenceDate = dataPoints.first?.timestamp ?? Date()

        let startOfDay = calendar.startOfDay(for: referenceDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        return startOfDay...endOfDay
    }

    var body: some View {
        VStack(spacing: 0) {
            // Metric tab selector
            metricTabSelector
                .padding(.horizontal, designSystem.spacing.md)
                .padding(.top, designSystem.spacing.sm)
            
            ScrollView {
                VStack(spacing: designSystem.spacing.lg) {
                    // Export file info banner
                    if let exportFile = loadedExportFile {
                        exportInfoBanner(exportFile: exportFile)
                    }
                    
                    // Chart or empty state
                    if isLoading {
                        loadingView
                    } else if hasData {
                        metricChart
                        dataSummaryCard
                    } else {
                        emptyStateView
                    }
                }
                .padding(designSystem.spacing.md)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
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
    
    // MARK: - Export Info Banner
    
    private func exportInfoBanner(exportFile: SessionDataLoader.ExportFileInfo) -> some View {
        VStack(spacing: designSystem.spacing.xs) {
            HStack {
                // File icon
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 14))
                    .foregroundColor(designSystem.colors.textSecondary)
                
                // File name
                Text(exportFile.url.lastPathComponent)
                    .font(.caption.bold())
                    .foregroundColor(designSystem.colors.textPrimary)
                    .lineLimit(1)
                
                Spacer()
                
                // Data points count
                Text("\(dataPoints.count) points")
                    .font(.caption)
                    .foregroundColor(designSystem.colors.textTertiary)
            }
            
            HStack {
                // Export date
                let formatter: DateFormatter = {
                    let f = DateFormatter()
                    f.dateStyle = .medium
                    f.timeStyle = .short
                    return f
                }()
                Text("Exported: \(formatter.string(from: exportFile.creationDate))")
                    .font(.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
                
                Spacer()
                
                // File size
                let sizeKB = Double(exportFile.fileSize) / 1024.0
                Text(String(format: "%.1f KB", sizeKB))
                    .font(.caption)
                    .foregroundColor(designSystem.colors.textTertiary)
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
            
            // Chart
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
        Chart(dataPoints) { point in
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
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
    }
    
    // FIXED: Use movementIntensity directly (already in g units from SessionDataLoader)
    private var movementChart: some View {
        Chart(dataPoints) { point in
            PointMark(
                x: .value("Time", point.timestamp),
                y: .value("Acceleration", point.movementIntensity)  // ← FIXED: was movementIntensityInG
            )
            .foregroundStyle(point.isAtRest ? Color.blue.opacity(0.6) : Color.green.opacity(0.8))
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
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
    }
    
    private var temperatureChart: some View {
        Chart(dataPoints) { point in
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
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
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
            Text("Loading data...")
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
        if !hasExportFiles {
            return "No Exports"
        }
        return "No \(selectedTab.rawValue) Data"
    }
    
    private var emptyStateMessage: String {
        if !hasExportFiles {
            return "Use the Share tab to export sensor data, then view it here."
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
        Logger.shared.info("[HistoricalView] 📁 Documents path: \(documentsPath.path)")
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            Logger.shared.info("[HistoricalView] 📁 Found \(files.count) files in Documents:")
            
            let csvFiles = files.filter {
                $0.pathExtension == "csv" && $0.lastPathComponent.hasPrefix("oralable_data_")
            }
            Logger.shared.info("[HistoricalView] 📊 Matching CSV files: \(csvFiles.count)")
        } catch {
            Logger.shared.error("[HistoricalView] ❌ Failed to list documents: \(error)")
        }
        
        // Get export file
        loadedExportFile = SessionDataLoader.shared.getMostRecentExportFile()
        Logger.shared.info("[HistoricalView] 🔍 Export file found: \(loadedExportFile?.url.lastPathComponent ?? "NONE")")
        
        if let exportFile = loadedExportFile {
            Logger.shared.info("[HistoricalView] 📂 Calling loadFromMostRecentExport for metric: \(selectedTab.metricType)")
            let points = SessionDataLoader.shared.loadFromMostRecentExport(metricType: selectedTab.metricType)
            Logger.shared.info("[HistoricalView] ✅ Loaded \(points.count) data points")
            
            if points.isEmpty {
                Logger.shared.warning("[HistoricalView] ⚠️ No data points returned - checking file directly...")
                // Try loading file directly to debug
                do {
                    let content = try String(contentsOf: exportFile.url, encoding: .utf8)
                    let lines = content.components(separatedBy: .newlines)
                    Logger.shared.info("[HistoricalView] 📄 File has \(lines.count) lines")
                    if lines.count > 1 {
                        Logger.shared.info("[HistoricalView] 📄 Header: \(lines[0])")
                        Logger.shared.info("[HistoricalView] 📄 First data: \(lines[1])")
                    }
                } catch {
                    Logger.shared.error("[HistoricalView] ❌ Failed to read file: \(error)")
                }
            }
            
            dataPoints = points

            // Update selected tab if current selection has no data
            if !availableTabs.contains(selectedTab), let firstTab = availableTabs.first {
                selectedTab = firstTab
            }
        } else {
            Logger.shared.warning("[HistoricalView] ⚠️ No export files found")
        }

        isLoading = false
    }
    
    // FIXED: Use movementIntensity directly (already in g units from SessionDataLoader)
    private func getLatestValue() -> Double? {
        guard let lastPoint = dataPoints.last else { return nil }
        
        switch selectedTab {
        case .emg, .ir:
            return lastPoint.averagePPGIR
        case .move:
            return lastPoint.movementIntensity  // ← FIXED: was movementIntensityInG
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
    
    // FIXED: Use movementIntensity directly (already in g units from SessionDataLoader)
    private func getValuesForSelectedTab() -> [Double] {
        switch selectedTab {
        case .emg, .ir:
            return dataPoints.compactMap { $0.averagePPGIR }
        case .move:
            return dataPoints.map { $0.movementIntensity }  // ← FIXED: was movementIntensityInG
        case .temp:
            return dataPoints.map { $0.averageTemperature }.filter { $0 > 0 }
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
