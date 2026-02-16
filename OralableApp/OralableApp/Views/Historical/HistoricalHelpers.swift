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

    func loadExportData() {
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
