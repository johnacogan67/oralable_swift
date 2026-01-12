//
//  HistoricalDataManager.swift
//  OralableApp
//
//  Manager for caching and updating historical metrics.
//
//  Purpose:
//  Prevents recalculating aggregations on every view update
//  by caching metrics for each time range.
//
//  Time Ranges Cached:
//  - Minute, Hour, Day, Week, Month metrics
//
//  Features:
//  - Background metric updates (60 second interval)
//  - Throttled updates to prevent excessive computation
//  - Memory-efficient caching
//
//  Integration:
//  - Works with SensorDataProcessor for raw data
//  - Provides data to HistoricalViewModel
//

import Foundation
import Combine
import UIKit

/// Manager for caching and updating historical metrics
/// This prevents recalculating aggregations on every view update
class HistoricalDataManager: ObservableObject {
    // MARK: - Published Properties
    @Published var minuteMetrics: HistoricalMetrics?
    @Published var hourMetrics: HistoricalMetrics?
    @Published var dayMetrics: HistoricalMetrics?
    @Published var weekMetrics: HistoricalMetrics?
    @Published var monthMetrics: HistoricalMetrics?

    @Published var isUpdating = false
    @Published var lastUpdateTime: Date?

    // MARK: - Private Properties
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let updateInterval: TimeInterval = 60.0 // Update every 60 seconds

    // Reference to the sensor data processor (internal for access by ViewModel)
    internal weak var sensorDataProcessor: SensorDataProcessor?

    // Throttling to prevent excessive updates
    private var lastMetricsUpdateTime: Date?
    private let minimumUpdateInterval: TimeInterval = 2.0 // Minimum 2 seconds between updates
    private var pendingUpdateTask: Task<Void, Never>?

    // MARK: - Initialization
    init(sensorDataProcessor: SensorDataProcessor?) {
        self.sensorDataProcessor = sensorDataProcessor
        Logger.shared.info("[HistoricalDataManager] Initialized with sensorDataProcessor: \(sensorDataProcessor != nil ? "YES" : "NO")")
        // Intentionally not starting auto-update by default
    }

    deinit {
        stopAutoUpdate()
    }

    // MARK: - Public Methods

    /// Manually trigger an update of all metrics (with throttling)
    @MainActor func updateAllMetrics() {
        // THROTTLING: Check if we've updated too recently
        if let lastUpdate = lastMetricsUpdateTime {
            let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
            if timeSinceLastUpdate < minimumUpdateInterval {
                let formatted = String(format: "%.1f", timeSinceLastUpdate)
                Logger.shared.debug("[HistoricalDataManager] ⏸ Throttling update (last update \(formatted)s ago, min interval: \(minimumUpdateInterval)s)")

                // Cancel any pending update and schedule a new one
                pendingUpdateTask?.cancel()
                pendingUpdateTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(self?.minimumUpdateInterval ?? 2.0) * 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.performMetricsUpdate()
                }
                return
            }
        }

        // Proceed with immediate update
        performMetricsUpdate()
    }

    /// Internal method that performs the actual metrics update
    @MainActor private func performMetricsUpdate() {
        guard let processor = sensorDataProcessor else {
            Logger.shared.warning("[HistoricalDataManager] ⚠️ SensorDataProcessor is nil, cannot update metrics")
            clearAllMetrics()
            return
        }

        if processor.sensorDataHistory.isEmpty {
            Logger.shared.warning("[HistoricalDataManager] ⚠️ No sensor data available (sensorDataHistory is empty), clearing metrics")
            clearAllMetrics()
            return
        }

        Logger.shared.info("[HistoricalDataManager] ✅ Starting metrics update | Sensor data count: \(processor.sensorDataHistory.count)")
        isUpdating = true
        lastMetricsUpdateTime = Date()

        // Snapshot data on the main actor to avoid concurrent mutation issues,
        // then perform expensive aggregation off-main, and finally publish results on main actor
        let sensorSnapshot = processor.sensorDataHistory

        Task {
            // Perform aggregation off-main in a detached task to avoid blocking the main actor
            let aggregates = await Task.detached { () -> (HistoricalMetrics?, HistoricalMetrics?, HistoricalMetrics?, HistoricalMetrics?, HistoricalMetrics?) in
                let minute = HistoricalDataAggregator.aggregate(data: sensorSnapshot, for: .minute, endDate: Date())
                let hour = HistoricalDataAggregator.aggregate(data: sensorSnapshot, for: .hour, endDate: Date())
                let day = HistoricalDataAggregator.aggregate(data: sensorSnapshot, for: .day, endDate: Date())
                let week = HistoricalDataAggregator.aggregate(data: sensorSnapshot, for: .week, endDate: Date())
                let month = HistoricalDataAggregator.aggregate(data: sensorSnapshot, for: .month, endDate: Date())
                return (minute, hour, day, week, month)
            }.value

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.minuteMetrics = aggregates.0
                self.hourMetrics = aggregates.1
                self.dayMetrics = aggregates.2
                self.weekMetrics = aggregates.3
                self.monthMetrics = aggregates.4
                self.lastUpdateTime = Date()
                self.isUpdating = false
                Logger.shared.info("[HistoricalDataManager] ✅ Metrics update completed and published to UI")
            }
        }
    }

    /// Update metrics for a specific time range only
    /// - Parameter range: The time range to update
    @MainActor func updateMetrics(for range: TimeRange) {
        guard let processor = sensorDataProcessor, !processor.sensorDataHistory.isEmpty else {
            Logger.shared.debug("[HistoricalDataManager] No sensor data available for range: \(range), clearing metrics")
            clearMetrics(for: range)
            return
        }

        Logger.shared.debug("[HistoricalDataManager] Updating metrics for range: \(range) | Data count: \(processor.sensorDataHistory.count)")

        // Snapshot and compute off-main
        let snapshot = processor.sensorDataHistory

        Task {
            let metrics = await Task.detached { () -> HistoricalMetrics? in
                HistoricalDataAggregator.aggregate(data: snapshot, for: range, endDate: Date())
            }.value

            await MainActor.run {
                switch range {
                case TimeRange.minute:
                    self.minuteMetrics = metrics
                case TimeRange.hour:
                    self.hourMetrics = metrics
                case TimeRange.day:
                    self.dayMetrics = metrics
                case TimeRange.week:
                    self.weekMetrics = metrics
                case TimeRange.month:
                    self.monthMetrics = metrics
                }
                self.lastUpdateTime = Date()
                Logger.shared.debug("[HistoricalDataManager] Metrics for \(range) published to UI")
            }
        }
    }

    /// Get metrics for a specific time range
    /// - Parameter range: The time range
    /// - Returns: Cached metrics or nil if not available
    func getMetrics(for range: TimeRange) -> HistoricalMetrics? {
        switch range {
        case TimeRange.minute: return minuteMetrics
        case TimeRange.hour: return hourMetrics
        case TimeRange.day: return dayMetrics
        case TimeRange.week: return weekMetrics
        case TimeRange.month: return monthMetrics
        }
    }

    /// Check if metrics are available for a range
    /// - Parameter range: The time range to check
    /// - Returns: True if metrics exist
    func hasMetrics(for range: TimeRange) -> Bool {
        return getMetrics(for: range) != nil
    }

    /// Clear all cached metrics
    func clearAllMetrics() {
        minuteMetrics = nil
        hourMetrics = nil
        dayMetrics = nil
        weekMetrics = nil
        monthMetrics = nil
        lastUpdateTime = nil
    }

    /// Clear metrics for a specific range
    /// - Parameter range: The time range to clear
    func clearMetrics(for range: TimeRange) {
        switch range {
        case TimeRange.minute: minuteMetrics = nil
        case TimeRange.hour: hourMetrics = nil
        case TimeRange.day: dayMetrics = nil
        case TimeRange.week: weekMetrics = nil
        case TimeRange.month: monthMetrics = nil
        }
    }

    // MARK: - Auto-Update Management

    /// Start automatic periodic updates
    @MainActor func startAutoUpdate() {
        stopAutoUpdate()

        // Initial update
        updateAllMetrics()

        // Schedule periodic updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateAllMetrics()
        }
    }

    /// Stop automatic updates
    func stopAutoUpdate() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    /// Set custom update interval
    /// - Parameter interval: Update interval in seconds
    func setUpdateInterval(_ interval: TimeInterval) {
        guard interval >= 10 else { return } // Minimum 10 seconds

        let wasRunning = updateTimer != nil
        stopAutoUpdate()

        if wasRunning {
            updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.updateAllMetrics()
            }
        }
    }

    // MARK: - Private Methods

    // DISABLED: Auto-update functionality removed for static historical snapshots
    /* ... */
}

// MARK: - Convenience Computed Properties
extension HistoricalDataManager {
    /// Returns true if any metrics are available
    var hasAnyMetrics: Bool {
        return minuteMetrics != nil || hourMetrics != nil || dayMetrics != nil || weekMetrics != nil || monthMetrics != nil
    }

    /// Returns a summary string of available metrics
    var availabilityDescription: String {
        var available: [String] = []

        if minuteMetrics != nil { available.append("Minute") }
        if hourMetrics != nil { available.append("Hour") }
        if dayMetrics != nil { available.append("Day") }
        if weekMetrics != nil { available.append("Week") }
        if monthMetrics != nil { available.append("Month") }

        return available.isEmpty ? "No metrics available" : "Available: \(available.joined(separator: ", "))"
    }

    /// Time since last update in seconds
    var timeSinceLastUpdate: TimeInterval? {
        guard let lastUpdate = lastUpdateTime else { return nil }
        return Date().timeIntervalSince(lastUpdate)
    }
}
