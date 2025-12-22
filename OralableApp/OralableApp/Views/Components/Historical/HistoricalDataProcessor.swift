import Foundation
import SwiftUI

// MARK: - Centralized Data Processing Manager
@MainActor
class HistoricalDataProcessor: ObservableObject {
    @Published var processedData: ProcessedHistoricalData?
    @Published var isProcessing = false
    @Published var selectedDataPoint: SensorData?

    private let normalizationService: PPGNormalizationService
    private var cachedData: [String: ProcessedHistoricalData] = [:]

    init(normalizationService: PPGNormalizationService) {
        self.normalizationService = normalizationService
    }

    struct ProcessedHistoricalData {
        let rawData: [SensorData]
        let normalizedData: [(timestamp: Date, value: Double)]
        let statistics: DataStatistics
        let segments: [DataSegment]
        let deviceContext: DeviceContext?
        let cacheKey: String
        let processingMethod: String
    }

    struct DataStatistics {
        let average: Double
        let minimum: Double
        let maximum: Double
        let standardDeviation: Double
        let variationCoefficient: Double
        let sampleCount: Int
    }

    struct DataSegment {
        let startIndex: Int
        let endIndex: Int
        let isStable: Bool
        let confidence: Double
        let timestamp: Date
    }

    struct DeviceContext {
        let state: DeviceState
        let confidence: Double
        let isStabilized: Bool
        let timeInState: TimeInterval
    }

    func processData(
        from sensorDataProcessor: SensorDataProcessor,
        metricType: MetricType,
        timeRange: TimeRange,
        selectedDate: Date,
        appMode: HistoricalAppMode
    ) async {
        // Create normalized cache key based on the actual time period
        let calendar = Calendar.current
        let normalizedDate: Date

        switch timeRange {
        case .minute:
            normalizedDate = calendar.dateInterval(of: .minute, for: selectedDate)?.start ?? selectedDate
        case .hour:
            normalizedDate = calendar.dateInterval(of: .hour, for: selectedDate)?.start ?? selectedDate
        case .day:
            normalizedDate = calendar.startOfDay(for: selectedDate)
        case .week:
            normalizedDate = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        case .month:
            normalizedDate = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        }

        let cacheKey = "\(metricType.rawValue)_\(timeRange.rawValue)_\(Int(normalizedDate.timeIntervalSince1970))"

        // DEBUG: Log what we're trying to process
        print("🔄 Processing historical data:")
        print("   Metric: \(metricType.title)")
        print("   Time Range: \(timeRange.rawValue)")
        print("   Selected Date: \(selectedDate)")
        print("   Normalized Date: \(normalizedDate)")
        print("   Cache Key: \(cacheKey)")
        print("   Total sensor history count: \(sensorDataProcessor.sensorDataHistory.count)")

        if let cached = cachedData[cacheKey] {
            print("✅ Using cached data")
            self.processedData = cached
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        let filteredData = filterData(from: sensorDataProcessor.sensorDataHistory, timeRange: timeRange, selectedDate: selectedDate)

        guard !filteredData.isEmpty else {
            print("❌ No data after filtering")
            processedData = nil
            return
        }

        print("📊 Processing \(filteredData.count) filtered readings")

        let normalizedData = await processMetricData(filteredData, metricType: metricType, appMode: appMode)
        let statistics = calculateStatistics(from: normalizedData)
        let segments = appMode.allowsAdvancedAnalytics ? detectDataSegments(filteredData) : []
        let deviceContext = appMode.allowsAdvancedAnalytics ? analyzeDeviceContext(filteredData) : nil

        let processed = ProcessedHistoricalData(
            rawData: filteredData,
            normalizedData: normalizedData,
            statistics: statistics,
            segments: segments,
            deviceContext: deviceContext,
            cacheKey: cacheKey,
            processingMethod: appMode.allowsAdvancedAnalytics ? "Advanced" : "Basic"
        )

        cachedData[cacheKey] = processed

        if cachedData.count > 20 {
            let oldestKey = cachedData.keys.sorted().first!
            cachedData.removeValue(forKey: oldestKey)
        }

        print("✅ Processed data successfully - \(statistics.sampleCount) samples")

        self.processedData = processed
    }

    private func filterData(from data: [SensorData], timeRange: TimeRange, selectedDate: Date) -> [SensorData] {
        let calendar = Calendar.current

        // DEBUG: Log data availability
        print("📊 Filtering \(data.count) total sensor readings")
        if let earliest = data.first?.timestamp, let latest = data.last?.timestamp {
            print("📅 Data range: \(earliest) to \(latest)")
        }

        var filtered: [SensorData] = []

        switch timeRange {
        case .minute:
            let startOfMinute = calendar.dateInterval(of: .minute, for: selectedDate)?.start ?? selectedDate
            let endOfMinute = calendar.date(byAdding: .minute, value: 1, to: startOfMinute) ?? selectedDate
            print("⏰ Minute filter: \(startOfMinute) to \(endOfMinute)")
            filtered = data.filter { $0.timestamp >= startOfMinute && $0.timestamp < endOfMinute }
        case .hour:
            let startOfHour = calendar.dateInterval(of: .hour, for: selectedDate)?.start ?? selectedDate
            let endOfHour = calendar.date(byAdding: .hour, value: 1, to: startOfHour) ?? selectedDate
            print("⏰ Hour filter: \(startOfHour) to \(endOfHour)")
            filtered = data.filter { $0.timestamp >= startOfHour && $0.timestamp < endOfHour }
        case .day:
            let startOfDay = calendar.startOfDay(for: selectedDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            print("📅 Day filter: \(startOfDay) to \(endOfDay)")
            filtered = data.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }
        case .week:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
            let endOfWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: startOfWeek) ?? selectedDate
            print("📅 Week filter: \(startOfWeek) to \(endOfWeek)")
            filtered = data.filter { $0.timestamp >= startOfWeek && $0.timestamp < endOfWeek }
        case .month:
            let startOfMonth = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? selectedDate
            print("📅 Month filter: \(startOfMonth) to \(endOfMonth)")
            filtered = data.filter { $0.timestamp >= startOfMonth && $0.timestamp < endOfMonth }
        }

        print("✅ Filtered to \(filtered.count) readings for selected period")

        if filtered.isEmpty {
            print("⚠️ No data found for selected period")
        }

        return filtered
    }

    private func processMetricData(_ data: [SensorData], metricType: MetricType, appMode: HistoricalAppMode) async -> [(timestamp: Date, value: Double)] {
        switch metricType {
        case .ppg:
            if appMode.allowsAdvancedAnalytics {
                let rawPPG = data.map { (timestamp: $0.timestamp, ir: Double($0.ppg.ir), red: Double($0.ppg.red), green: Double($0.ppg.green)) }
                let normalized = normalizationService.normalizePPGData(rawPPG, method: .persistent, sensorData: data)
                return normalized.map { (timestamp: $0.timestamp, value: $0.ir) }
            } else {
                return data.map { (timestamp: $0.timestamp, value: Double($0.ppg.ir)) }
            }
        case .temperature:
            return data.map { (timestamp: $0.timestamp, value: $0.temperature.celsius) }
        case .battery:
            return data.map { (timestamp: $0.timestamp, value: Double($0.battery.percentage)) }
        case .accelerometer:
            return data.map { (timestamp: $0.timestamp, value: $0.accelerometer.magnitude) }
        case .heartRate:
            return data.compactMap { sensorData in
                guard let heartRate = sensorData.heartRate else { return nil }
                return (timestamp: sensorData.timestamp, value: heartRate.bpm)
            }
        case .spo2:
            return data.compactMap { sensorData in
                guard let spo2 = sensorData.spo2 else { return nil }
                return (timestamp: sensorData.timestamp, value: spo2.percentage)
            }
        }
    }

    private func calculateStatistics(from data: [(timestamp: Date, value: Double)]) -> DataStatistics {
        let values = data.map { $0.value }
        guard !values.isEmpty else {
            return DataStatistics(average: 0, minimum: 0, maximum: 0, standardDeviation: 0, variationCoefficient: 0, sampleCount: 0)
        }

        let average = values.reduce(0, +) / Double(values.count)
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0

        let variance = values.map { pow($0 - average, 2) }.reduce(0, +) / Double(values.count)
        let standardDeviation = sqrt(variance)
        let variationCoefficient = average != 0 ? (standardDeviation / abs(average)) * 100 : 0

        return DataStatistics(
            average: average,
            minimum: minimum,
            maximum: maximum,
            standardDeviation: standardDeviation,
            variationCoefficient: variationCoefficient,
            sampleCount: values.count
        )
    }

    private func detectDataSegments(_ data: [SensorData]) -> [DataSegment] {
        var segments: [DataSegment] = []
        let windowSize = 5

        guard data.count > windowSize * 2 else { return [] }

        var currentStart = 0
        for i in windowSize..<(data.count - windowSize) {
            let window = Array(data[(i-windowSize)..<(i+windowSize)])
            let variation = calculateWindowVariation(window)

            if variation > 0.5 {
                if i - currentStart > windowSize {
                    segments.append(DataSegment(
                        startIndex: currentStart,
                        endIndex: i,
                        isStable: true,
                        confidence: 0.8,
                        timestamp: data[currentStart].timestamp
                    ))
                }
                currentStart = i + windowSize
            }
        }

        if currentStart < data.count - windowSize {
            segments.append(DataSegment(
                startIndex: currentStart,
                endIndex: data.count,
                isStable: true,
                confidence: 0.8,
                timestamp: data[currentStart].timestamp
            ))
        }

        return segments
    }

    private func calculateWindowVariation(_ data: [SensorData]) -> Double {
        let magnitudes = data.map { $0.accelerometer.magnitude }
        let mean = magnitudes.reduce(0, +) / Double(magnitudes.count)
        let variance = magnitudes.map { pow($0 - mean, 2) }.reduce(0, +) / Double(magnitudes.count)
        return sqrt(variance)
    }

    private func analyzeDeviceContext(_ data: [SensorData]) -> DeviceContext? {
        guard data.count >= 5 else { return nil }

        let recent = Array(data.suffix(10))
        let movementVariation = calculateWindowVariation(recent)
        let tempChange = (recent.map { $0.temperature.celsius }.max() ?? 0) - (recent.map { $0.temperature.celsius }.min() ?? 0)
        let batteryLevel = recent.last?.battery.percentage ?? 0

        let state: DeviceState
        if batteryLevel > 95 && movementVariation < 0.1 {
            state = .onChargerStatic
        } else if movementVariation < 0.1 && tempChange < 0.5 {
            state = .offChargerStatic
        } else if movementVariation > 0.5 {
            state = .inMotion
        } else if tempChange > 2.0 {
            state = .onCheek
        } else {
            state = .unknown
        }

        let confidence = min(1.0, max(0.0, 1.0 - (movementVariation / 2.0)))
        let isStabilized = movementVariation < 0.2 && confidence > 0.7

        return DeviceContext(
            state: state,
            confidence: confidence,
            isStabilized: isStabilized,
            timeInState: 60.0
        )
    }

    func clearCache() {
        cachedData.removeAll()
    }
}
