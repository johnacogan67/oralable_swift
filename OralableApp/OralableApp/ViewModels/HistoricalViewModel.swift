//
//  HistoricalViewModel.swift
//  OralableApp
//
//  ViewModel for historical data processing and chart display.
//  Acts as a coordinator that wires together specialized services.
//
//  Responsibilities:
//  - Coordinates between HistoricalSessionPlaybackService and HistoricalTimeRangeService
//  - Manages Combine pipelines for reactive data flow
//  - Provides a unified public API for views
//
//  Delegated Services:
//  - HistoricalSessionPlaybackService: Session loading, playback state, session data points
//  - HistoricalTimeRangeService: Time range navigation, offset, display text, formatting
//
//  Models (extracted):
//  - HistoricalStatisticsCache: Pre-computed statistics for efficient rendering
//  - ChartDataPoint: Simple chart data point struct
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
//  Updated: February 2026 - Extracted services for better separation of concerns
//

import Foundation
import Combine

@MainActor
class HistoricalViewModel: ObservableObject {

    // MARK: - Services

    /// Session playback service managing loaded sessions and session data points
    let sessionService: HistoricalSessionPlaybackService

    /// Time range navigation and formatting service
    let timeRangeService: HistoricalTimeRangeService

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

    /// Cached statistics (recomputed when data changes, not on every view render)
    @Published private(set) var statisticsCache = HistoricalStatisticsCache()

    /// Whether metrics are being updated
    @Published var isUpdating: Bool = false

    /// Last update time
    @Published var lastUpdateTime: Date?

    /// Whether to show detailed statistics
    @Published var showDetailedStats: Bool = false

    /// Selected data point for detail view
    @Published var selectedDataPoint: HistoricalDataPoint?

    // MARK: - Pass-through Published Properties (from services)

    /// Current offset from present time (0 = current period, -1 = previous period, etc.)
    /// Pass-through to timeRangeService
    var timeRangeOffset: Int {
        get { timeRangeService.timeRangeOffset }
        set { timeRangeService.timeRangeOffset = newValue }
    }

    // MARK: - Session Playback Properties (pass-through to sessionService)

    /// The loaded recording session (nil = live mode)
    var loadedSession: RecordingSession? {
        get { sessionService.loadedSession }
        set { sessionService.loadedSession = newValue }
    }

    /// Whether we're in session playback mode vs live mode
    var isSessionPlaybackMode: Bool {
        return sessionService.isSessionPlaybackMode
    }

    /// Session data points loaded from CSV file
    var sessionDataPoints: [HistoricalDataPoint] {
        return sessionService.sessionDataPoints
    }

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
        return timeRangeService.isCurrentTimeRange(isSessionPlaybackMode: isSessionPlaybackMode)
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
        return timeRangeService.timeRangeText(
            selectedTimeRange: selectedTimeRange,
            isSessionPlaybackMode: isSessionPlaybackMode,
            loadedSession: loadedSession
        )
    }

    /// Date range text for display
    var dateRangeText: String {
        return timeRangeService.dateRangeText(
            isSessionPlaybackMode: isSessionPlaybackMode,
            loadedSession: loadedSession,
            currentMetrics: currentMetrics
        )
    }

    // MARK: - Metric Text Properties (cached, recomputed when data changes)

    var averageHeartRateText: String { statisticsCache.averageHeartRate }
    var averageSpO2Text: String { statisticsCache.averageSpO2 }
    var averageTemperatureText: String { statisticsCache.averageTemperature }
    var averageBatteryText: String { statisticsCache.averageBattery }
    var activeTimeText: String { statisticsCache.activeTime }
    var dataPointsCountText: String { statisticsCache.dataPointsCount }
    var totalGrindingEventsText: String { statisticsCache.totalGrindingEvents }

    // MARK: - Initialization

    /// Initialize with injected historicalDataManager
    /// - Parameter historicalDataManager: Historical data manager conforming to protocol (allows mocking for tests)
    init(historicalDataManager: HistoricalDataManagerProtocol) {
        Logger.shared.info("[HistoricalViewModel] Initializing with protocol-based dependency injection...")
        self.historicalDataManager = historicalDataManager
        self.sessionService = HistoricalSessionPlaybackService()
        self.timeRangeService = HistoricalTimeRangeService()
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

        // Build a debounced cache pipeline: compute cachedDataPoints and statistics off-main then publish on main.
        metricsCacheCancellable = Publishers.CombineLatest($currentMetrics, $selectedTimeRange)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.global(qos: .userInitiated))
            .map { (metrics, _) -> ([HistoricalDataPoint], HistoricalStatisticsCache) in
                let points = metrics?.dataPoints ?? []
                let stats = HistoricalStatisticsCache.compute(from: points, metrics: metrics, isSessionPlayback: false)
                return (points, stats)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (points, stats) in
                guard let self = self, !self.isSessionPlaybackMode else { return }
                self.cachedDataPoints = points
                self.statisticsCache = stats
                Logger.shared.debug("[HistoricalViewModel] Cached dataPoints updated: \(points.count) points")
            }

        // Recalculate statistics when session data changes (playback mode)
        sessionService.$sessionDataPoints
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.global(qos: .userInitiated))
            .map { points in
                HistoricalStatisticsCache.compute(from: points, metrics: nil, isSessionPlayback: true)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                guard let self = self, self.isSessionPlaybackMode else { return }
                self.statisticsCache = stats
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods - Session Playback (delegated to sessionService)

    /// Load data from a recording session
    /// - Parameters:
    ///   - session: The recording session to load
    ///   - metricType: The metric type to display (e.g., "EMG Activity", "Movement")
    func loadSession(_ session: RecordingSession, metricType: String) {
        sessionService.loadSession(session, metricType: metricType)
    }

    /// Load the most recent completed session for the current metric type
    /// - Parameters:
    ///   - sessions: Array of available recording sessions
    ///   - metricType: The metric type to display
    func loadMostRecentSession(from sessions: [RecordingSession], metricType: String) {
        sessionService.loadMostRecentSession(from: sessions, metricType: metricType)
    }

    /// Exit session playback mode and return to live data
    func exitSessionPlayback() {
        sessionService.exitSessionPlayback()
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
                sessionService.loadSession(session, metricType: sessionService.metricTypeFilter)
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
        sessionService.exitSessionPlayback()
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

    // MARK: - Public Methods - Time Range Selection (delegated to timeRangeService)

    /// Select a specific time range
    func selectTimeRange(_ range: TimeRange) {
        if isSessionPlaybackMode { return }  // Disabled in session playback
        selectedTimeRange = range
    }

    /// Move to next time range (forward in time, toward present)
    func selectNextTimeRange() {
        timeRangeService.selectNextTimeRange(
            isSessionPlaybackMode: isSessionPlaybackMode
        ) { [weak self] in
            self?.updateCurrentRangeMetrics()
        }
    }

    /// Move to previous time range (backward in time)
    func selectPreviousTimeRange() {
        timeRangeService.selectPreviousTimeRange(
            isSessionPlaybackMode: isSessionPlaybackMode
        ) { [weak self] in
            self?.updateCurrentRangeMetrics()
        }
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

    // MARK: - Formatting Helpers (delegated to timeRangeService)

    /// Format a data point's timestamp
    func formatTimestamp(_ date: Date) -> String {
        return timeRangeService.formatTimestamp(
            date,
            selectedTimeRange: selectedTimeRange,
            isSessionPlaybackMode: isSessionPlaybackMode
        )
    }

    /// Format temperature value
    func formatTemperature(_ temp: Double) -> String {
        return timeRangeService.formatTemperature(temp)
    }

    /// Format battery value
    func formatBattery(_ battery: Int) -> String {
        return timeRangeService.formatBattery(battery)
    }

    /// Format heart rate value
    func formatHeartRate(_ hr: Double?) -> String {
        return timeRangeService.formatHeartRate(hr)
    }

    /// Format SpO2 value
    func formatSpO2(_ spo2: Double?) -> String {
        return timeRangeService.formatSpO2(spo2)
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
}

// MARK: - Mock for Previews

extension HistoricalViewModel {
    static func mock() -> HistoricalViewModel {
        // Create mock historical data manager
        let mockHistoricalManager = PreviewHistoricalDataManager()

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
