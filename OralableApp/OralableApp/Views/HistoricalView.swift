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
    @State var selectedTimePeriod: HistoricalTimePeriod = .day

    // Selected metric tab
    @State var selectedTab: HistoryMetricTab = .emg

    // Navigation date
    @State var selectedDate: Date = Date()

    // Session data points loaded from CSV
    @State var dataPoints: [HistoricalDataPoint] = []

    // Export file info
    @State var loadedExportFile: SessionDataLoader.ExportFileInfo?

    // Loading state
    @State var isLoading: Bool = false

    // Initial metric type passed from dashboard (optional)
    let initialMetricType: String?

    init(metricType: String? = nil) {
        self.initialMetricType = metricType
        Logger.shared.info("[HistoricalView] Initialized with metricType: \(metricType ?? "none")")
    }

    // MARK: - Computed Properties

    var hasData: Bool {
        !dataPoints.isEmpty
    }

    var hasExportFiles: Bool {
        loadedExportFile != nil || SessionDataLoader.shared.getMostRecentExportFile() != nil
    }

    /// Tabs that have data available - only show tabs with actual recorded data
    var availableTabs: [HistoryMetricTab] {
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
    var xAxisDomain: ClosedRange<Date> {
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
    var filteredDataPoints: [HistoricalDataPoint] {
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
                .padding(.horizontal, designSystem.spacing.md)
                .padding(.top, designSystem.spacing.buttonPadding)

            // Navigation (back/forward)
            navigationBar
                .padding(.horizontal, designSystem.spacing.md)
                .padding(.top, designSystem.spacing.buttonPadding)

            // Metric tab selector
            metricTabSelector
                .padding(.horizontal, designSystem.spacing.md)
                .padding(.top, designSystem.spacing.md)

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
                .padding(designSystem.spacing.md)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .background(designSystem.colors.backgroundPrimary)
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
                            .font(designSystem.typography.labelLarge)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedTimePeriod == period ? designSystem.colors.primaryBlack : Color.clear)
                    .foregroundColor(selectedTimePeriod == period ? designSystem.colors.primaryWhite : designSystem.colors.textPrimary)
                }
                .accessibilityLabel("\(period.rawValue) view")
                .accessibilityAddTraits(selectedTimePeriod == period ? .isSelected : [])
            }
        }
        .background(designSystem.colors.backgroundTertiary)
        .cornerRadius(designSystem.cornerRadius.medium)
        .accessibilityLabel("Time period selector")
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Back button
            Button(action: navigateBackward) {
                Image(systemName: "chevron.left")
                    .font(designSystem.typography.buttonLarge)
                    .foregroundColor(designSystem.colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(designSystem.colors.backgroundSecondary)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Previous \(selectedTimePeriod.rawValue.lowercased())")
            .accessibilityHint("Double tap to go to the previous \(selectedTimePeriod.rawValue.lowercased())")

            Spacer()

            // Current period display
            VStack(spacing: designSystem.spacing.xxs) {
                Text(navigationDisplayText)
                    .font(designSystem.typography.button)
                    .foregroundColor(designSystem.colors.textPrimary)

                Text(selectedTimePeriod == .hour ? "Hour View" : "Day View")
                    .font(designSystem.typography.footnote)
                    .foregroundColor(designSystem.colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Currently viewing \(navigationDisplayText)")

            Spacer()

            // Forward button
            Button(action: navigateForward) {
                Image(systemName: "chevron.right")
                    .font(designSystem.typography.buttonLarge)
                    .foregroundColor(canNavigateForward ? designSystem.colors.textPrimary : designSystem.colors.gray400)
                    .frame(width: 44, height: 44)
                    .background(designSystem.colors.backgroundSecondary)
                    .clipShape(Circle())
            }
            .disabled(!canNavigateForward)
            .accessibilityLabel("Next \(selectedTimePeriod.rawValue.lowercased())")
            .accessibilityHint(canNavigateForward ? "Double tap to go to the next \(selectedTimePeriod.rawValue.lowercased())" : "No later data available")
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
                    .foregroundColor(selectedTab == tab ? tab.chartColor : designSystem.colors.textSecondary)
                }
                .accessibilityLabel("\(tab.metricType) tab")
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.medium)
        .accessibilityLabel("Metric selector")
    }

    // MARK: - Metric Chart

    private var metricChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(selectedTab.metricType)
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.textPrimary)

                Spacer()

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
        .cornerRadius(designSystem.cornerRadius.card)
    }

}

// MARK: - Preview

struct HistoricalView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            HistoricalView()
                .environmentObject(DesignSystem())
        }
    }
}
