//
//  HistoricalHelpers.swift
//  OralableApp
//
//  Helper methods for HistoricalView including data loading,
//  tab initialization, and value formatting.
//
//  Extracted from HistoricalView.swift
//

import SwiftUI

extension HistoricalView {

    // MARK: - Tab Initialization

    func setInitialTab() {
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

    // MARK: - Data Loading

    @MainActor
    func loadExportDataIfNeeded() async {
        let export = SessionDataLoader.shared.getMostRecentExportFile()
        let key = "\(export?.url.path ?? "none")|\(export?.creationDate.timeIntervalSince1970 ?? 0)|\(selectedTab.metricType)"

        // Avoid re-loading the same file/metric repeatedly during SwiftUI re-renders.
        if lastLoadKey == key {
            loadedExportFile = export
            return
        }
        lastLoadKey = key
        loadedExportFile = export

        guard export != nil else {
            dataPoints = []
            return
        }

        isLoading = true
        let metric = selectedTab.metricType

        let points: [HistoricalDataPoint] = await Task.detached(priority: .userInitiated) {
            SessionDataLoader.shared.loadFromMostRecentExport(metricType: metric)
        }.value

        dataPoints = points
        if let firstPoint = points.first {
            selectedDate = firstPoint.timestamp
        }
        isLoading = false
    }

    // MARK: - Value Accessors

    func getLatestValue() -> Double? {
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

    func getMinValue() -> Double? {
        let values = getValuesForSelectedTab()
        return values.min()
    }

    func getMaxValue() -> Double? {
        let values = getValuesForSelectedTab()
        return values.max()
    }

    func getAverageValue() -> Double? {
        let values = getValuesForSelectedTab()
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func getValuesForSelectedTab() -> [Double] {
        switch selectedTab {
        case .emg, .ir:
            return filteredDataPoints.compactMap { $0.averagePPGIR }
        case .move:
            return filteredDataPoints.map { $0.movementIntensity }
        case .temp:
            return filteredDataPoints.map { $0.averageTemperature }.filter { $0 > 0 }
        }
    }

    // MARK: - Value Formatting

    func formatValue(_ value: Double?) -> String {
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
