//
//  HistoricalStatisticsCache.swift
//  OralableApp
//
//  Pre-computed statistics cache to avoid redundant compactMap/reduce
//  on every view render. Extracted from HistoricalViewModel.swift.
//
//  Created: February 2026
//

import Foundation

/// Pre-computed statistics cache to avoid redundant compactMap/reduce on every view render
struct HistoricalStatisticsCache {
    var averageHeartRate: String = "--"
    var averageSpO2: String = "--"
    var averageTemperature: String = "--"
    var averageBattery: String = "--"
    var activeTime: String = "--"
    var dataPointsCount: String = "--"
    var totalGrindingEvents: String = "--"

    /// Recompute all statistics from data points in a single pass
    static func compute(
        from points: [HistoricalDataPoint],
        metrics: HistoricalMetrics?,
        isSessionPlayback: Bool
    ) -> HistoricalStatisticsCache {
        var cache = HistoricalStatisticsCache()
        guard !points.isEmpty else { return cache }

        // Heart rate
        let hrValues = points.compactMap { $0.averageHeartRate }
        if !hrValues.isEmpty {
            let avg = hrValues.reduce(0, +) / Double(hrValues.count)
            cache.averageHeartRate = avg > 0 ? String(format: "%.0f", avg) : "--"
        }

        // SpO2
        let spo2Values = points.compactMap { $0.averageSpO2 }
        if !spo2Values.isEmpty {
            let avg = spo2Values.reduce(0, +) / Double(spo2Values.count)
            cache.averageSpO2 = avg > 0 ? String(format: "%.0f", avg) : "--"
        }

        // Temperature
        if isSessionPlayback {
            let temps = points.map { $0.averageTemperature }.filter { $0 > 0 }
            if !temps.isEmpty {
                cache.averageTemperature = String(format: "%.1f", temps.reduce(0, +) / Double(temps.count))
            }
        } else if let metrics = metrics {
            cache.averageTemperature = String(format: "%.1f", metrics.avgTemperature)
        }

        // Battery
        if isSessionPlayback {
            let batteries = points.map { $0.averageBattery }.filter { $0 > 0 }
            if !batteries.isEmpty {
                cache.averageBattery = String(format: "%.0f", Double(batteries.reduce(0, +)) / Double(batteries.count))
            }
        } else if let metrics = metrics {
            cache.averageBattery = String(format: "%.0f", metrics.avgBatteryLevel)
        }

        // Active time
        let totalActivity = points.map { $0.movementIntensity }.reduce(0, +)
        let hours = Int(totalActivity)
        let minutes = Int((totalActivity - Double(hours)) * 60)
        cache.activeTime = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"

        // Data points count
        if isSessionPlayback {
            cache.dataPointsCount = "\(points.count)"
        } else if let metrics = metrics {
            cache.dataPointsCount = "\(metrics.dataPoints.count)"
        }

        // Grinding events
        if isSessionPlayback {
            let events = points.compactMap { $0.grindingEvents }.reduce(0, +)
            cache.totalGrindingEvents = "\(events)"
        } else if let metrics = metrics {
            cache.totalGrindingEvents = "\(metrics.totalGrindingEvents)"
        }

        return cache
    }
}
