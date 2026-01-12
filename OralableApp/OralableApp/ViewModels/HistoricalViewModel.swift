//
//  HistoricalViewModel.swift
//  OralableApp
//
//  ViewModel for historical data processing and chart display.
//
//  Responsibilities:
//  - Loads data from CSV export files
//  - Processes data for selected time range
//  - Calculates statistics (min, max, average)
//  - Manages session playback mode
//
//  Time Ranges:
//  - Minute: Last 60 seconds
//  - Hour: Last 60 minutes
//  - Day: Last 24 hours (default)
//  - Week: Last 7 days
//  - Month: Last 30 days
//
//  Data Processing:
//  - Aggregates samples into time buckets
//  - Normalizes values for chart display
//  - Filters by metric type
//
//  Created: November 7, 2025
//  Updated: December 7, 2025 - Added session playback support
//

import Foundation
import Combine

@MainActor
class HistoricalViewModel: ObservableObject {
    
    // MARK: - Published Properties (Observable by View)
    
    /// Selected time range for viewing data
    @Published var selectedTimeRange: TimeRange = .minute

    /// Metrics for each time range
    @Published var minuteMetrics: HistoricalMetrics?
    @Published var hourMetrics: HistoricalMetrics?
    @Published var dayMetrics: HistoricalMetrics?
    @Published var weekMetrics: HistoricalMetrics?
    @Published var monthMetrics: HistoricalMetrics?
    
    /// Current metrics for selected range
    @Published var currentMetrics: HistoricalMetrics?
    
    /// Cached data points (debounced / computed off-main then published on main)
    /// Use this in views instead of calling the heavy computed getter repeatedly
    @Published private(set) var cachedDataPoints: [HistoricalDataPoint] = []
    
    /// Whether metrics are being updated
    @Published var isUpdating: Bool = false
    
    /// Last update time
    @Published var lastUpdateTime: Date?
    
    /// Whether to show detailed statistics
    @Published var showDetailedStats: Bool = false
    
    /// Selected data point for detail view
    @Published var selectedDataPoint: HistoricalDataPoint?
    
    /// Current offset from present time (0 = current period, -1 = previous period, etc.)
    @Published var timeRangeOffset: Int = 0
    
    // MARK: - Session Playback Properties
    
    /// The loaded recording session (nil = live mode)
    @Published var loadedSession: RecordingSession?
    
    /// Whether we're in session playback mode vs live mode
    var isSessionPlaybackMode: Bool {
        return loadedSession != nil
    }
    
    /// Session data points loaded from CSV file
    @Published private(set) var sessionDataPoints: [HistoricalDataPoint] = []
    
    /// Metric type filter for session data (e.g., "EMG Activity", "Movement", "Temperature")
    private var metricTypeFilter: String = "Movement"
    
    // MARK: - Private Properties

    private let historicalDataManager: HistoricalDataManagerProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // Internal cancellable for caching datapoints
    private var metricsCacheCancellable: AnyCancellable?
    
    // MARK: - Computed Properties
    
    /// Whether any metrics are available
    var hasAnyMetrics: Bool {
        if isSessionPlaybackMode {
            return !sessionDataPoints.isEmpty
        }
        return hourMetrics != nil || dayMetrics != nil || weekMetrics != nil || monthMetrics != nil
    }
    
    /// Whether current metrics are available
    var hasCurrentMetrics: Bool {
        if isSessionPlaybackMode {
            return !sessionDataPoints.isEmpty
        }
        return currentMetrics != nil
    }
    
    /// Whether the selected time range is the current period (today/this week/this month)
    var isCurrentTimeRange: Bool {
        if isSessionPlaybackMode {
            return true  // Session playback doesn't support time range navigation
        }
        return timeRangeOffset == 0
    }
    
    /// Total samples for current range
    var totalSamples: Int {
        if isSessionPlaybackMode {
            return sessionDataPoints.count
        }
        return currentMetrics?.totalSamples ?? 0
    }
    
    /// Data points for current range - returns session data or cached live data
    var dataPoints: [HistoricalDataPoint] {
        if isSessionPlaybackMode {
            return sessionDataPoints
        }
        return cachedDataPoints
    }
    
    /// Time range display text
    var timeRangeText: String {
        if isSessionPlaybackMode {
            if let session = loadedSession {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return "Session: \(formatter.string(from: session.startTime))"
            }
            return "Session Playback"
        }
        
        if timeRangeOffset == 0 {
            switch selectedTimeRange {
            case .minute: return "This Minute"
            case .hour: return "This Hour"
            case .day: return "Today"
            case .week: return "This Week"
            case .month: return "This Month"
            }
        } else if timeRangeOffset == -1 {
            switch selectedTimeRange {
            case .minute: return "Last Minute"
            case .hour: return "Last Hour"
            case .day: return "Yesterday"
            case .week: return "Last Week"
            case .month: return "Last Month"
            }
        } else {
            let absoluteOffset = abs(timeRangeOffset)
            switch selectedTimeRange {
            case .minute: return "\(absoluteOffset) Minutes Ago"
            case .hour: return "\(absoluteOffset) Hours Ago"
            case .day: return "\(absoluteOffset) Days Ago"
            case .week: return "\(absoluteOffset) Weeks Ago"
            case .month: return "\(absoluteOffset) Months Ago"
            }
        }
    }
    
    /// Date range text for display
    var dateRangeText: String {
        if isSessionPlaybackMode {
            guard let session = loadedSession else { return "No session" }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let start = formatter.string(from: session.startTime)
            if let endTime = session.endTime {
                let end = formatter.string(from: endTime)
                return "\(start) - \(end)"
            }
            return "Started: \(start)"
        }
        
        guard let metrics = currentMetrics else {
            return "No data"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        
        let start = formatter.string(from: metrics.startDate)
        let end = formatter.string(from: metrics.endDate)
        
        return "\(start) - \(end)"
    }
    
    // MARK: - Metric Text Properties
    
    /// Average heart rate text
    var averageHeartRateText: String {
        let points = isSessionPlaybackMode ? sessionDataPoints : (currentMetrics?.dataPoints ?? [])
        guard !points.isEmpty else { return "--" }
        let avgHR = points.compactMap { $0.averageHeartRate }.reduce(0, +) / Double(max(points.compactMap { $0.averageHeartRate }.count, 1))
        return avgHR > 0 ? String(format: "%.0f", avgHR) : "--"
    }
    
    /// Average SpO2 text
    var averageSpO2Text: String {
        let points = isSessionPlaybackMode ? sessionDataPoints : (currentMetrics?.dataPoints ?? [])
        guard !points.isEmpty else { return "--" }
        let avgSpO2 = points.compactMap { $0.averageSpO2 }.reduce(0, +) / Double(max(points.compactMap { $0.averageSpO2 }.count, 1))
        return avgSpO2 > 0 ? String(format: "%.0f", avgSpO2) : "--"
    }
    
    /// Average temperature text
    var averageTemperatureText: String {
        if isSessionPlaybackMode {
            let temps = sessionDataPoints.map { $0.averageTemperature }.filter { $0 > 0 }
            guard !temps.isEmpty else { return "--" }
            return String(format: "%.1f", temps.reduce(0, +) / Double(temps.count))
        }
        guard let metrics = currentMetrics else { return "--" }
        return String(format: "%.1f", metrics.avgTemperature)
    }
    
    /// Average battery text
    var averageBatteryText: String {
        if isSessionPlaybackMode {
            let batteries = sessionDataPoints.map { $0.averageBattery }.filter { $0 > 0 }
            guard !batteries.isEmpty else { return "--" }
            return String(format: "%.0f", Double(batteries.reduce(0, +)) / Double(batteries.count))
        }
        guard let metrics = currentMetrics else { return "--" }
        return String(format: "%.0f", metrics.avgBatteryLevel)
    }
    
    /// Active time text
    var activeTimeText: String {
        let points = isSessionPlaybackMode ? sessionDataPoints : (currentMetrics?.dataPoints ?? [])
        guard !points.isEmpty else { return "--" }
        let totalActivity = points.map { $0.movementIntensity }.reduce(0, +)
        let hours = Int(totalActivity)
        let minutes = Int((totalActivity - Double(hours)) * 60)
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
    
    /// Data points count text
    var dataPointsCountText: String {
        if isSessionPlaybackMode {
            return "\(sessionDataPoints.count)"
        }
        guard let metrics = currentMetrics else { return "--" }
        return "\(metrics.dataPoints.count)"
    }
    
    /// Total grinding events text
    var totalGrindingEventsText: String {
        if isSessionPlaybackMode {
            let events = sessionDataPoints.compactMap { $0.grindingEvents }.reduce(0, +)
            return "\(events)"
        }
        guard let metrics = currentMetrics else { return "--" }
        return "\(metrics.totalGrindingEvents)"
    }
    
    // MARK: - Initialization

    /// Initialize with injected historicalDataManager
    /// - Parameter historicalDataManager: Historical data manager conforming to protocol (allows mocking for tests)
    init(historicalDataManager: HistoricalDataManagerProtocol) {
        Logger.shared.info("[HistoricalViewModel] Initializing with protocol-based dependency injection...")
        self.historicalDataManager = historicalDataManager
        Logger.shared.info("[HistoricalViewModel] Setting up bindings...")
        setupBindings()
        Logger.shared.info("[HistoricalViewModel] Updating current metrics for initial selectedTimeRange: \(selectedTimeRange)")
        updateCurrentMetrics()
        Logger.shared.info("[HistoricalViewModel] Initialization complete")
    }

    // MARK: - Setup
    
    private func setupBindings() {
        // Subscribe to selectedTimeRange changes
        $selectedTimeRange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newRange in
                guard let self = self else { return }
                
                // Skip if in session playback mode
                if self.isSessionPlaybackMode { return }
                
                Logger.shared.info("[HistoricalViewModel] Time range changed to: \(newRange)")
                self.updateCurrentMetrics()
                // Trigger update if we don't have metrics for this range
                let hasMetrics: Bool = {
                    switch newRange {
                    case .minute: return self.minuteMetrics != nil
                    case .hour: return self.hourMetrics != nil
                    case .day: return self.dayMetrics != nil
                    case .week: return self.weekMetrics != nil
                    case .month: return self.monthMetrics != nil
                    }
                }()
                if !hasMetrics {
                    Logger.shared.warning("[HistoricalViewModel] No metrics available for \(newRange), requesting update...")
                    self.historicalDataManager.updateMetrics(for: newRange)
                }
            }
            .store(in: &cancellables)

        // Subscribe to historical data manager's published properties (using protocol publishers)
        historicalDataManager.minuteMetricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                guard let self = self, !self.isSessionPlaybackMode else { return }
                if let metrics = metrics {
                    Logger.shared.info("[HistoricalViewModel] Received Minute metrics | Data points: \(metrics.dataPoints.count) | Total samples: \(metrics.totalSamples)")
                } else {
                    Logger.shared.debug("[HistoricalViewModel] Minute metrics cleared (nil)")
                }
                self.minuteMetrics = metrics
                self.updateCurrentMetricsIfNeeded()
            }
            .store(in: &cancellables)

        historicalDataManager.hourMetricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                guard let self = self, !self.isSessionPlaybackMode else { return }
                if let metrics = metrics {
                    Logger.shared.info("[HistoricalViewModel] Received Hour metrics | Data points: \(metrics.dataPoints.count) | Total samples: \(metrics.totalSamples)")
                } else {
                    Logger.shared.debug("[HistoricalViewModel] Hour metrics cleared (nil)")
                }
                self.hourMetrics = metrics
                self.updateCurrentMetricsIfNeeded()
            }
            .store(in: &cancellables)

        historicalDataManager.dayMetricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                guard let self = self, !self.isSessionPlaybackMode else { return }
                if let metrics = metrics {
                    Logger.shared.info("[HistoricalViewModel] Received Day metrics | Data points: \(metrics.dataPoints.count) | Total samples: \(metrics.totalSamples)")
                } else {
                    Logger.shared.debug("[HistoricalViewModel] Day metrics cleared (nil)")
                }
                self.dayMetrics = metrics
                self.updateCurrentMetricsIfNeeded()
            }
            .store(in: &cancellables)

        historicalDataManager.weekMetricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                guard let self = self, !self.isSessionPlaybackMode else { return }
                if let metrics = metrics {
                    Logger.shared.info("[HistoricalViewModel] Received Week metrics | Data points: \(metrics.dataPoints.count) | Total samples: \(metrics.totalSamples)")
                } else {
                    Logger.shared.debug("[HistoricalViewModel] Week metrics cleared (nil)")
                }
                self.weekMetrics = metrics
                self.updateCurrentMetricsIfNeeded()
            }
            .store(in: &cancellables)

        historicalDataManager.monthMetricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                guard let self = self, !self.isSessionPlaybackMode else { return }
                if let metrics = metrics {
                    Logger.shared.info("[HistoricalViewModel] Received Month metrics | Data points: \(metrics.dataPoints.count) | Total samples: \(metrics.totalSamples)")
                } else {
                    Logger.shared.debug("[HistoricalViewModel] Month metrics cleared (nil)")
                }
                self.monthMetrics = metrics
                self.updateCurrentMetricsIfNeeded()
            }
            .store(in: &cancellables)

        historicalDataManager.isUpdatingPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$isUpdating)

        historicalDataManager.lastUpdateTimePublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastUpdateTime)

        // Keep the existing selectedTimeRange sink that updates current metrics
        $selectedTimeRange
            .sink { [weak self] range in
                guard let self = self, !self.isSessionPlaybackMode else { return }
                Logger.shared.debug("[HistoricalViewModel] Time range changed to: \(range)")
                self.updateCurrentMetrics()
            }
            .store(in: &cancellables)

        // Build a debounced cache pipeline: compute cachedDataPoints off-main then publish on main.
        metricsCacheCancellable = Publishers.CombineLatest($currentMetrics, $selectedTimeRange)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.global(qos: .userInitiated))
            .map { (metrics, _) -> [HistoricalDataPoint] in
                return metrics?.dataPoints ?? []
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] points in
                guard let self = self, !self.isSessionPlaybackMode else { return }
                self.cachedDataPoints = points
                Logger.shared.debug("[HistoricalViewModel] Cached dataPoints updated: \(points.count) points")
            }
    }
    
    // MARK: - Public Methods - Session Playback
    
    /// Load data from a recording session
    /// - Parameters:
    ///   - session: The recording session to load
    ///   - metricType: The metric type to display (e.g., "EMG Activity", "Movement")
    func loadSession(_ session: RecordingSession, metricType: String) {
        Logger.shared.info("[HistoricalViewModel] Loading session: \(session.id) for metric: \(metricType)")
        
        self.loadedSession = session
        self.metricTypeFilter = metricType
        
        // Load data points from the session file
        let dataPoints = SessionDataLoader.shared.loadHistoricalDataPoints(from: session, metricType: metricType)
        self.sessionDataPoints = dataPoints
        
        Logger.shared.info("[HistoricalViewModel] Loaded \(dataPoints.count) data points from session")
    }
    
    /// Load the most recent completed session for the current metric type
    /// - Parameters:
    ///   - sessions: Array of available recording sessions
    ///   - metricType: The metric type to display
    func loadMostRecentSession(from sessions: [RecordingSession], metricType: String) {
        // Determine device type based on metric
        let targetDeviceType: DeviceType? = metricType == "EMG Activity" ? .anr : .oralable
        
        let session: RecordingSession?
        if let deviceType = targetDeviceType {
            session = SessionDataLoader.shared.getMostRecentCompletedSession(from: sessions, deviceType: deviceType)
        } else {
            session = SessionDataLoader.shared.getMostRecentCompletedSession(from: sessions)
        }
        
        if let session = session {
            loadSession(session, metricType: metricType)
        } else {
            Logger.shared.warning("[HistoricalViewModel] No completed sessions found for metric: \(metricType)")
            // Clear session playback mode
            self.loadedSession = nil
            self.sessionDataPoints = []
        }
    }
    
    /// Exit session playback mode and return to live data
    func exitSessionPlayback() {
        Logger.shared.info("[HistoricalViewModel] Exiting session playback mode")
        self.loadedSession = nil
        self.sessionDataPoints = []
        
        // Refresh live data
        updateCurrentMetrics()
    }
    
    // MARK: - Public Methods - Data Management

    /// Update all metrics
    func updateAllMetrics() {
        // Skip if in session playback mode
        if isSessionPlaybackMode {
            Logger.shared.debug("[HistoricalViewModel] Skipping updateAllMetrics - in session playback mode")
            return
        }
        
        Logger.shared.info("[HistoricalViewModel] Requesting metrics update from HistoricalDataManager")
        Logger.shared.info("[HistoricalViewModel] Current state BEFORE update:")
        Logger.shared.info("[HistoricalViewModel]   - hourMetrics: \(hourMetrics?.dataPoints.count ?? 0) points")
        Logger.shared.info("[HistoricalViewModel]   - dayMetrics: \(dayMetrics?.dataPoints.count ?? 0) points")
        Logger.shared.info("[HistoricalViewModel]   - weekMetrics: \(weekMetrics?.dataPoints.count ?? 0) points")
        historicalDataManager.updateAllMetrics()
    }

    /// Update metrics for current time range
    func updateCurrentRangeMetrics() {
        if isSessionPlaybackMode { return }
        Logger.shared.debug("[HistoricalViewModel] Requesting metrics update for range: \(selectedTimeRange)")
        historicalDataManager.updateMetrics(for: selectedTimeRange)
    }

    /// Refresh current view
    func refresh() {
        if isSessionPlaybackMode {
            // Reload session data
            if let session = loadedSession {
                loadSession(session, metricType: metricTypeFilter)
            }
        } else {
            Logger.shared.info("[HistoricalViewModel] Manual refresh triggered")
            updateCurrentRangeMetrics()
        }
    }
    
    /// Async refresh for SwiftUI refreshable modifier
    func refreshAsync() async {
        refresh()
        // Give a small delay to ensure UI updates properly
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }
    
    /// Clear all cached metrics
    func clearAllMetrics() {
        historicalDataManager.clearAllMetrics()
        currentMetrics = nil
        cachedDataPoints = []
        sessionDataPoints = []
        loadedSession = nil
    }
    
    /// Start automatic updates
    func startAutoUpdate() {
        if isSessionPlaybackMode { return }
        historicalDataManager.startAutoUpdate()
    }
    
    /// Stop automatic updates
    func stopAutoUpdate() {
        historicalDataManager.stopAutoUpdate()
    }
    
    // MARK: - Public Methods - Time Range Selection
    
    /// Select a specific time range
    func selectTimeRange(_ range: TimeRange) {
        if isSessionPlaybackMode { return }  // Disabled in session playback
        selectedTimeRange = range
    }
    
    /// Move to next time range (forward in time, toward present)
    func selectNextTimeRange() {
        if isSessionPlaybackMode { return }
        if timeRangeOffset < 0 {
            timeRangeOffset += 1
            updateCurrentRangeMetrics()
        }
    }
    
    /// Move to previous time range (backward in time)
    func selectPreviousTimeRange() {
        if isSessionPlaybackMode { return }
        timeRangeOffset -= 1
        updateCurrentRangeMetrics()
    }
    
    // MARK: - Public Methods - Data Point Selection
    
    /// Select a data point for detailed view
    func selectDataPoint(_ point: HistoricalDataPoint) {
        selectedDataPoint = point
    }
    
    /// Clear selected data point
    func clearSelectedDataPoint() {
        selectedDataPoint = nil
    }
    
    /// Toggle detailed statistics view
    func toggleDetailedStats() {
        showDetailedStats.toggle()
    }

    // MARK: - Public Methods - Data Sufficiency

    /// Check if there's sufficient data for the current time range
    var hasSufficientDataForCurrentRange: Bool {
        let points = isSessionPlaybackMode ? sessionDataPoints : (currentMetrics?.dataPoints ?? [])
        
        // Need at least 2 data points for a meaningful chart
        guard points.count >= 2 else { return false }

        guard let firstPoint = points.first,
              let lastPoint = points.last else { return false }

        let dataSpan = lastPoint.timestamp.timeIntervalSince(firstPoint.timestamp)

        // For session playback, any data span is acceptable
        if isSessionPlaybackMode {
            return dataSpan >= 1.0  // At least 1 second
        }
        
        // Set lenient minimum spans based on time range
        let minimumSpanSeconds: TimeInterval
        switch selectedTimeRange {
        case .minute:
            minimumSpanSeconds = 5 // 5 seconds minimum
        case .hour:
            minimumSpanSeconds = 30 // 30 seconds minimum
        case .day:
            minimumSpanSeconds = 300 // 5 minutes minimum
        case .week:
            minimumSpanSeconds = 1800 // 30 minutes minimum
        case .month:
            minimumSpanSeconds = 7200 // 2 hours minimum
        }

        return dataSpan >= minimumSpanSeconds
    }

    /// Get a descriptive message about data sufficiency
    var dataSufficiencyMessage: String? {
        let points = isSessionPlaybackMode ? sessionDataPoints : (currentMetrics?.dataPoints ?? [])
        
        if points.isEmpty {
            if isSessionPlaybackMode {
                return "No data available in this session file."
            }
            return "No data available for this time range. Connect your device to start collecting data."
        }

        if points.count == 1 {
            return "Only 1 data point available. Need at least 2 points to show a chart."
        }

        // Check if data spans enough time
        if let firstPoint = points.first,
           let lastPoint = points.last {
            let dataSpan = lastPoint.timestamp.timeIntervalSince(firstPoint.timestamp)
            let hours = Int(dataSpan / 3600)
            let minutes = Int((dataSpan.truncatingRemainder(dividingBy: 3600)) / 60)
            let seconds = Int(dataSpan.truncatingRemainder(dividingBy: 60))

            let timeSpanDescription: String
            if hours > 0 {
                timeSpanDescription = "\(hours)h \(minutes)m"
            } else if minutes > 0 {
                timeSpanDescription = "\(minutes)m \(seconds)s"
            } else {
                timeSpanDescription = "\(seconds)s"
            }

            // For session playback, show duration info
            if isSessionPlaybackMode {
                return "Session duration: \(timeSpanDescription) (\(points.count) data points)"
            }
            
            // Check against minimum spans
            let minimumSpanSeconds: TimeInterval
            let minimumSpanText: String
            switch selectedTimeRange {
            case .minute:
                minimumSpanSeconds = 5
                minimumSpanText = "5 seconds"
            case .hour:
                minimumSpanSeconds = 30
                minimumSpanText = "30 seconds"
            case .day:
                minimumSpanSeconds = 300
                minimumSpanText = "5 minutes"
            case .week:
                minimumSpanSeconds = 1800
                minimumSpanText = "30 minutes"
            case .month:
                minimumSpanSeconds = 7200
                minimumSpanText = "2 hours"
            }

            if dataSpan < minimumSpanSeconds {
                return "Data only spans \(timeSpanDescription). Need at least \(minimumSpanText) for \(selectedTimeRange.rawValue) view."
            }
        }

        return nil  // Sufficient data
    }
    
    // MARK: - Private Methods

    private func updateCurrentMetrics() {
        if isSessionPlaybackMode { return }
        
        Logger.shared.info("[HistoricalViewModel] updateCurrentMetrics() called for selectedTimeRange: \(selectedTimeRange)")

        switch selectedTimeRange {
        case .minute:
            Logger.shared.debug("[HistoricalViewModel] Minute case - minuteMetrics state: \(minuteMetrics == nil ? "NIL" : "EXISTS with \(minuteMetrics!.dataPoints.count) points")")
            currentMetrics = minuteMetrics
        case .hour:
            Logger.shared.debug("[HistoricalViewModel] Hour case - hourMetrics state: \(hourMetrics == nil ? "NIL" : "EXISTS with \(hourMetrics!.dataPoints.count) points")")
            currentMetrics = hourMetrics
        case .day:
            currentMetrics = dayMetrics
        case .week:
            currentMetrics = weekMetrics
        case .month:
            currentMetrics = monthMetrics
        }
    }

    private func updateCurrentMetricsIfNeeded() {
        if isSessionPlaybackMode { return }
        // Update current metrics if the selected range matches the updated range
        updateCurrentMetrics()
    }
    
    // MARK: - Formatting Helpers
    
    /// Format a data point's timestamp
    func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        if isSessionPlaybackMode {
            // For session playback, show full time
            formatter.dateFormat = "HH:mm:ss"
            return formatter.string(from: date)
        }
        
        switch selectedTimeRange {
        case .minute:
            formatter.dateFormat = "HH:mm:ss"
        case .hour, .day:
            formatter.dateFormat = "HH:mm"
        case .week:
            formatter.dateFormat = "EEE"
        case .month:
            formatter.dateFormat = "MMM d"
        }
        
        return formatter.string(from: date)
    }
    
    /// Format temperature value
    func formatTemperature(_ temp: Double) -> String {
        String(format: "%.1f°C", temp)
    }
    
    /// Format battery value
    func formatBattery(_ battery: Int) -> String {
        "\(battery)%"
    }
    
    /// Format heart rate value
    func formatHeartRate(_ hr: Double?) -> String {
        guard let hr = hr else { return "--" }
        return String(format: "%.0f bpm", hr)
    }
    
    /// Format SpO2 value
    func formatSpO2(_ spo2: Double?) -> String {
        guard let spo2 = spo2 else { return "--" }
        return String(format: "%.0f%%", spo2)
    }
}

// MARK: - Chart Data Point

/// Represents a single point on a chart
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

// MARK: - Mock for Previews

extension HistoricalViewModel {
    static func mock() -> HistoricalViewModel {
        // Create mock historical data manager
        let mockHistoricalManager = MockHistoricalDataManager()
        
        let viewModel = HistoricalViewModel(historicalDataManager: mockHistoricalManager)
        
        // Create mock metrics
        let mockDataPoints = (0..<10).map { index in
            HistoricalDataPoint(
                timestamp: Date().addingTimeInterval(TimeInterval(-3600 * index)),
                averageHeartRate: 65.0 + Double.random(in: -5...5),
                heartRateQuality: 0.9,
                averageSpO2: 98.0 + Double.random(in: -2...2),
                spo2Quality: 0.95,
                averageTemperature: 36.5 + Double.random(in: -0.5...0.5),
                averageBattery: 85 - (index * 5),
                movementIntensity: Double.random(in: 0...1),
                grindingEvents: Int.random(in: 0...3)
            )
        }
        
        let mockMetrics = HistoricalMetrics(
            timeRange: "Day",
            startDate: Date().addingTimeInterval(-86400),
            endDate: Date(),
            totalSamples: 1000,
            dataPoints: mockDataPoints,
            temperatureTrend: 0.2,
            batteryTrend: -5.0,
            activityTrend: 0.1,
            avgTemperature: 36.5,
            avgBatteryLevel: 75.0,
            totalGrindingEvents: 5,
            totalGrindingDuration: 300
        )
        
        // Set the mock metrics on the manager
        mockHistoricalManager.dayMetrics = mockMetrics
        
        // Update the view model's metrics (they'll be automatically synced via publishers)
        viewModel.dayMetrics = mockMetrics
        viewModel.currentMetrics = mockMetrics
        
        return viewModel
    }
}

// MARK: - Mock Historical Data Manager

/// Mock implementation of HistoricalDataManagerProtocol for previews and testing
@MainActor
class MockHistoricalDataManager: HistoricalDataManagerProtocol {
    // MARK: - Metrics State
    @Published var minuteMetrics: HistoricalMetrics?
    @Published var hourMetrics: HistoricalMetrics?
    @Published var dayMetrics: HistoricalMetrics?
    @Published var weekMetrics: HistoricalMetrics?
    @Published var monthMetrics: HistoricalMetrics?
    
    // MARK: - Update State
    @Published var isUpdating: Bool = false
    @Published var lastUpdateTime: Date?
    
    // MARK: - Actions
    func updateAllMetrics() {
        // No-op for mock
    }
    
    func updateMetrics(for range: TimeRange) {
        // No-op for mock
    }
    
    func getMetrics(for range: TimeRange) -> HistoricalMetrics? {
        switch range {
        case .minute: return minuteMetrics
        case .hour: return hourMetrics
        case .day: return dayMetrics
        case .week: return weekMetrics
        case .month: return monthMetrics
        }
    }
    
    func hasMetrics(for range: TimeRange) -> Bool {
        getMetrics(for: range) != nil
    }
    
    func clearAllMetrics() {
        minuteMetrics = nil
        hourMetrics = nil
        dayMetrics = nil
        weekMetrics = nil
        monthMetrics = nil
    }

    func clearMetrics(for range: TimeRange) {
        switch range {
        case .minute: minuteMetrics = nil
        case .hour: hourMetrics = nil
        case .day: dayMetrics = nil
        case .week: weekMetrics = nil
        case .month: monthMetrics = nil
        }
    }
    
    // MARK: - Auto-Update Management
    func startAutoUpdate() {
        // No-op for mock
    }
    
    func stopAutoUpdate() {
        // No-op for mock
    }
    
    func setUpdateInterval(_ interval: TimeInterval) {
        // No-op for mock
    }
    
    // MARK: - Computed Properties
    var hasAnyMetrics: Bool {
        hourMetrics != nil || dayMetrics != nil || weekMetrics != nil || monthMetrics != nil
    }
    
    var availabilityDescription: String {
        "Mock data available"
    }
    
    var timeSinceLastUpdate: TimeInterval? {
        guard let lastUpdate = lastUpdateTime else { return nil }
        return Date().timeIntervalSince(lastUpdate)
    }

    // MARK: - Publishers
    var minuteMetricsPublisher: Published<HistoricalMetrics?>.Publisher { $minuteMetrics }
    var hourMetricsPublisher: Published<HistoricalMetrics?>.Publisher { $hourMetrics }
    var dayMetricsPublisher: Published<HistoricalMetrics?>.Publisher { $dayMetrics }
    var weekMetricsPublisher: Published<HistoricalMetrics?>.Publisher { $weekMetrics }
    var monthMetricsPublisher: Published<HistoricalMetrics?>.Publisher { $monthMetrics }
    var isUpdatingPublisher: Published<Bool>.Publisher { $isUpdating }
    var lastUpdateTimePublisher: Published<Date?>.Publisher { $lastUpdateTime }
}
