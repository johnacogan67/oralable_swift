//
//  MockHistoricalDataManager.swift
//  OralableApp
//
//  Mock implementation of HistoricalDataManagerProtocol for SwiftUI previews.
//  Provides a lightweight, no-op data manager that can be populated with
//  sample data for preview rendering.
//
//  Extracted from HistoricalViewModel.swift for better separation of concerns.
//
//  Note: A separate, more feature-rich MockHistoricalDataManager exists in
//  OralableAppTests/Mocks/ for unit testing with call tracking.
//
//  Created: February 2026
//

import Foundation
import Combine

/// Mock implementation of HistoricalDataManagerProtocol for previews and testing
@MainActor
class PreviewHistoricalDataManager: HistoricalDataManagerProtocol {
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
