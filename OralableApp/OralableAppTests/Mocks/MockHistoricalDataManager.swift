//
//  MockHistoricalDataManager.swift
//  OralableAppTests
//
//  Created: Refactoring Phase 1
//  Purpose: Mock historical data manager for testing
//

import Foundation
import Combine
@testable import MAMDiagnostics

/// Mock Historical Data Manager for unit testing
/// Allows tests to simulate historical data behavior without actual data processing
@MainActor
class MockHistoricalDataManager: HistoricalDataManagerProtocol {
    // MARK: - Metrics State
    @Published var minuteMetrics: HistoricalMetrics? = nil
    @Published var hourMetrics: HistoricalMetrics? = nil
    @Published var dayMetrics: HistoricalMetrics? = nil
    @Published var weekMetrics: HistoricalMetrics? = nil
    @Published var monthMetrics: HistoricalMetrics? = nil

    // MARK: - Update State
    @Published var isUpdating: Bool = false
    @Published var lastUpdateTime: Date? = nil

    // MARK: - Test Helpers
    var updateAllMetricsCalled = false
    var updateMetricsCalled: [TimeRange] = []
    var getMetricsCalled: [TimeRange] = []
    var hasMetricsCalled: [TimeRange] = []
    var clearAllMetricsCalled = false
    var clearMetricsCalled: [TimeRange] = []
    var startAutoUpdateCalled = false
    var stopAutoUpdateCalled = false
    var setUpdateIntervalCalled: TimeInterval?

    // MARK: - Actions
    func updateAllMetrics() {
        updateAllMetricsCalled = true
        isUpdating = true
        lastUpdateTime = Date()

        // Simulate async update
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            self.isUpdating = false
        }
    }

    func updateMetrics(for range: TimeRange) {
        updateMetricsCalled.append(range)
        isUpdating = true
        lastUpdateTime = Date()

        // Simulate async update
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            self.isUpdating = false
        }
    }

    func getMetrics(for range: TimeRange) -> HistoricalMetrics? {
        getMetricsCalled.append(range)
        switch range {
        case .minute: return minuteMetrics
        case .hour: return hourMetrics
        case .day: return dayMetrics
        case .week: return weekMetrics
        case .month: return monthMetrics
        }
    }

    func hasMetrics(for range: TimeRange) -> Bool {
        hasMetricsCalled.append(range)
        return getMetrics(for: range) != nil
    }

    func clearAllMetrics() {
        clearAllMetricsCalled = true
        minuteMetrics = nil
        hourMetrics = nil
        dayMetrics = nil
        weekMetrics = nil
        monthMetrics = nil
        lastUpdateTime = nil
    }

    func clearMetrics(for range: TimeRange) {
        clearMetricsCalled.append(range)
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
        startAutoUpdateCalled = true
    }

    func stopAutoUpdate() {
        stopAutoUpdateCalled = true
    }

    func setUpdateInterval(_ interval: TimeInterval) {
        setUpdateIntervalCalled = interval
    }

    // MARK: - Computed Properties
    var hasAnyMetrics: Bool {
        return minuteMetrics != nil || hourMetrics != nil || dayMetrics != nil || weekMetrics != nil || monthMetrics != nil
    }

    var availabilityDescription: String {
        var available: [String] = []
        if minuteMetrics != nil { available.append("Minute") }
        if hourMetrics != nil { available.append("Hour") }
        if dayMetrics != nil { available.append("Day") }
        if weekMetrics != nil { available.append("Week") }
        if monthMetrics != nil { available.append("Month") }
        return available.isEmpty ? "No metrics available" : "Available: \(available.joined(separator: ", "))"
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

    // MARK: - Test Simulation Methods

    /// Simulate metrics for a specific time range
    func simulateMetrics(for range: TimeRange, metrics: HistoricalMetrics) {
        switch range {
        case .minute: minuteMetrics = metrics
        case .hour: hourMetrics = metrics
        case .day: dayMetrics = metrics
        case .week: weekMetrics = metrics
        case .month: monthMetrics = metrics
        }
        lastUpdateTime = Date()
    }

    /// Reset all test flags
    func reset() {
        updateAllMetricsCalled = false
        updateMetricsCalled = []
        getMetricsCalled = []
        hasMetricsCalled = []
        clearAllMetricsCalled = false
        clearMetricsCalled = []
        startAutoUpdateCalled = false
        stopAutoUpdateCalled = false
        setUpdateIntervalCalled = nil
        clearAllMetrics()
    }
}
