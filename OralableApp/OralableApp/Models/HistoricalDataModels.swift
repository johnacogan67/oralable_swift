import Foundation

// MARK: - Time Range Selection
/// Represents the time period for viewing historical data
enum TimeRange: String, CaseIterable, Codable {
    case minute = "Minute"
    case hour = "Hour"
    case day = "Day"
    case week = "Week"
    case month = "Month"

    /// Returns the number of seconds for this time range
    var seconds: TimeInterval {
        switch self {
        case .minute: return 60 // 1 minute
        case .hour: return 3600 // 1 hour
        case .day: return 86400 // 24 hours
        case .week: return 604800 // 7 days
        case .month: return 2592000 // 30 days
        }
    }

    /// Returns the ideal number of data points to display for this range
    var idealDataPoints: Int {
        switch self {
        case .minute: return 12 // 5-second intervals
        case .hour: return 12 // 5-minute intervals
        case .day: return 24 // hourly
        case .week: return 7 // daily
        case .month: return 30 // daily
        }
    }
}

// Note: HistoricalDataPoint is defined in SensorModels.swift

// MARK: - Historical Metrics
/// Contains calculated metrics and trends for a time range
struct HistoricalMetrics: Codable {
    let timeRange: String
    let startDate: Date
    let endDate: Date
    
    // Overall Statistics
    let totalSamples: Int
    let dataPoints: [HistoricalDataPoint]
    
    // Trends (comparing latest to earliest in range)
    let temperatureTrend: Double // Positive = increasing, Negative = decreasing
    let batteryTrend: Double
    let activityTrend: Double
    
    // Summary Statistics
    let avgTemperature: Double
    let avgBatteryLevel: Double
    let totalGrindingEvents: Int
    let totalGrindingDuration: TimeInterval
}

// MARK: - Data Aggregator
/// Helper class to aggregate raw sensor data into time-based metrics
class HistoricalDataAggregator {
    
    /// Aggregates sensor data for a specific time range
    /// - Parameters:
    ///   - data: Array of SensorData to aggregate
    ///   - range: The time range to aggregate over
    ///   - endDate: The end date for the range (defaults to now)
    /// - Returns: HistoricalMetrics containing aggregated data
    static func aggregate(data: [SensorData],
                         for range: TimeRange,
                         endDate: Date = Date()) -> HistoricalMetrics {

        let startDate = endDate.addingTimeInterval(-range.seconds)

        // Logging to verify timestamp distribution
        Logger.shared.info("[HistoricalDataAggregator] 🔍 Aggregating \(data.count) points for \(range)")

        // Log timestamp distribution
        if !data.isEmpty {
            let timestamps = data.map { $0.timestamp }
            if let oldest = timestamps.min(), let newest = timestamps.max() {
                let spanSeconds = newest.timeIntervalSince(oldest)
                Logger.shared.info("[HistoricalDataAggregator] Data span: \(String(format: "%.1f", spanSeconds))s | Oldest: \(oldest) | Newest: \(newest)")
            }
        }

        // Filter data to the time range
        let filteredData = data.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
        Logger.shared.info("[HistoricalDataAggregator] Filtered: \(filteredData.count)/\(data.count) points in range [\(startDate) to \(endDate)]")

        // Only log warnings when there's an issue
        if !data.isEmpty && filteredData.isEmpty {
            let oldestTimestamp = data.map { $0.timestamp }.min() ?? Date()
            let newestTimestamp = data.map { $0.timestamp }.max() ?? Date()
            Logger.shared.warning("[HistoricalDataAggregator] ⚠️ No data in range! Data: \(oldestTimestamp) to \(newestTimestamp)")
        }

        guard !filteredData.isEmpty else {
            return createEmptyMetrics(range: range, startDate: startDate, endDate: endDate)
        }

        // Create time buckets for aggregation
        let bucketSize = range.seconds / Double(range.idealDataPoints)
        var buckets: [[SensorData]] = Array(repeating: [], count: range.idealDataPoints)

        // Distribute data into buckets
        for sensorData in filteredData {
            let timeSinceStart = sensorData.timestamp.timeIntervalSince(startDate)
            let bucketIndex = min(Int(timeSinceStart / bucketSize), range.idealDataPoints - 1)
            buckets[bucketIndex].append(sensorData)
        }

        // Create aggregated data points from buckets
        var dataPoints: [HistoricalDataPoint] = []

        for (index, bucket) in buckets.enumerated() {
            guard !bucket.isEmpty else { continue }

            let bucketTimestamp = startDate.addingTimeInterval(Double(index) * bucketSize + bucketSize / 2)
            let aggregatedPoint = aggregateBucket(bucket, timestamp: bucketTimestamp)
            dataPoints.append(aggregatedPoint)
        }
        
        // Calculate trends
        let temperatureTrend = calculateTrend(dataPoints.map { $0.averageTemperature })
        let batteryTrend = calculateTrend(dataPoints.map { Double($0.averageBattery) })
        let activityTrend = calculateTrend(dataPoints.map { $0.movementIntensity })
        
        // Calculate summary statistics
        let avgTemperature = dataPoints.map { $0.averageTemperature }.reduce(0, +) / Double(max(dataPoints.count, 1))
        let avgBatteryLevel = dataPoints.map { Double($0.averageBattery) }.reduce(0, +) / Double(max(dataPoints.count, 1))
        let totalGrindingEvents = dataPoints.compactMap { $0.grindingEvents }.reduce(0, +)
        let totalGrindingDuration: TimeInterval = 0 // Not available in current structure
        
        return HistoricalMetrics(
            timeRange: range.rawValue,
            startDate: startDate,
            endDate: endDate,
            totalSamples: filteredData.count,
            dataPoints: dataPoints,
            temperatureTrend: temperatureTrend,
            batteryTrend: batteryTrend,
            activityTrend: activityTrend,
            avgTemperature: avgTemperature,
            avgBatteryLevel: avgBatteryLevel,
            totalGrindingEvents: totalGrindingEvents,
            totalGrindingDuration: totalGrindingDuration
        )
    }
    
    /// Aggregates a bucket of sensor data into a single data point
    private static func aggregateBucket(_ bucket: [SensorData], timestamp: Date) -> HistoricalDataPoint {
        let count = Double(bucket.count)
        
        // PPG averages
        let avgIR = bucket.map { Double($0.ppg.ir) }.reduce(0, +) / count
        let avgRed = bucket.map { Double($0.ppg.red) }.reduce(0, +) / count
        let avgGreen = bucket.map { Double($0.ppg.green) }.reduce(0, +) / count
        
        // Accelerometer averages
        // let avgAccelX = bucket.map { Double($0.accelerometer.x) }.reduce(0, +) / count
        // let avgAccelY = bucket.map { Double($0.accelerometer.y) }.reduce(0, +) / count
        // let avgAccelZ = bucket.map { Double($0.accelerometer.z) }.reduce(0, +) / count
        // let avgMagnitude = bucket.map { $0.accelerometer.magnitude }.reduce(0, +) / count
        
        // Temperature statistics
        let temperatures = bucket.map { $0.temperature.celsius }
        let avgTemperature = temperatures.reduce(0, +) / count
        // let minTemperature = temperatures.min() ?? 0
        // let maxTemperature = temperatures.max() ?? 0
        
        // Battery average
        let avgBatteryLevel = bucket.map { Double($0.battery.percentage) }.reduce(0, +) / count
        
        // Activity average (using accelerometer magnitude as proxy)
        let magnitudes = bucket.map { $0.accelerometer.magnitude }
        let avgActivityLevel = magnitudes.reduce(0, +) / count

        // Calculate movement variability (standard deviation of magnitudes)
        let magnitudeMean = avgActivityLevel
        let magnitudeVariance = magnitudes.map { pow($0 - magnitudeMean, 2) }.reduce(0, +) / count
        let magnitudeVariability = sqrt(magnitudeVariance)

        // Note: Grinding metrics would need to be implemented in SensorData
        let grindingCount = 0 // bucket.filter { $0.grinding.isActive }.count
        // let totalGrindingDuration: TimeInterval = 0 // bucket.map { $0.grinding.duration }.reduce(0, +)
        // let avgGrindingIntensity = 0.0 // placeholder

        return HistoricalDataPoint(
            timestamp: timestamp,
            averageHeartRate: nil, // Would need heart rate data from SensorData
            heartRateQuality: nil,
            averageSpO2: nil, // Would need SpO2 data from SensorData
            spo2Quality: nil,
            averageTemperature: avgTemperature,
            averageBattery: Int(avgBatteryLevel),
            movementIntensity: avgActivityLevel,
            movementVariability: magnitudeVariability,
            grindingEvents: grindingCount,
            averagePPGIR: avgIR,
            averagePPGRed: avgRed,
            averagePPGGreen: avgGreen
        )
    }
    
    /// Calculates the trend (slope) of a series of values
    /// Returns positive for increasing trend, negative for decreasing
    private static func calculateTrend(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        
        let first = values.prefix(values.count / 3).reduce(0, +) / Double(max(values.count / 3, 1))
        let last = values.suffix(values.count / 3).reduce(0, +) / Double(max(values.count / 3, 1))
        
        return last - first
    }
    
    /// Creates empty metrics when no data is available
    private static func createEmptyMetrics(range: TimeRange, startDate: Date, endDate: Date) -> HistoricalMetrics {
        return HistoricalMetrics(
            timeRange: range.rawValue,
            startDate: startDate,
            endDate: endDate,
            totalSamples: 0,
            dataPoints: [],
            temperatureTrend: 0,
            batteryTrend: 0,
            activityTrend: 0,
            avgTemperature: 0,
            avgBatteryLevel: 0,
            totalGrindingEvents: 0,
            totalGrindingDuration: 0
        )
    }
}

// MARK: - Export Summary Model

/// Summary information about an export operation
struct ExportSummary {
    let sensorDataCount: Int
    let logCount: Int
    let dateRange: String
    let estimatedSize: String
}
