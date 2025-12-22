//
//  HistoricalMockDataGenerator.swift
//  OralableApp
//
//  Created: November 20, 2025
//  Purpose: Generate realistic mock sensor data for testing historical views
//

import Foundation

/// Generates realistic mock sensor data spanning various time ranges for testing
struct HistoricalMockDataGenerator {

    /// Generate mock sensor data spanning a specified duration
    /// - Parameters:
    ///   - duration: Time span to generate data for (in seconds)
    ///   - endDate: End date for the data (defaults to now)
    ///   - samplingInterval: Time between data points (defaults to 10 seconds)
    /// - Returns: Array of SensorData with realistic values
    static func generateMockData(
        duration: TimeInterval,
        endDate: Date = Date(),
        samplingInterval: TimeInterval = 10.0
    ) -> [SensorData] {
        var data: [SensorData] = []
        let startDate = endDate.addingTimeInterval(-duration)
        var currentTime = startDate

        Logger.shared.info("[MockDataGenerator] Generating mock data from \(startDate) to \(endDate)")
        Logger.shared.info("[MockDataGenerator] Duration: \(duration)s (\(duration/3600) hours), Interval: \(samplingInterval)s")

        // Calculate number of data points
        let pointCount = Int(duration / samplingInterval)
        Logger.shared.info("[MockDataGenerator] Will generate \(pointCount) data points")

        while currentTime <= endDate {
            let sensorData = generateSingleDataPoint(at: currentTime)
            data.append(sensorData)
            currentTime = currentTime.addingTimeInterval(samplingInterval)
        }

        Logger.shared.info("[MockDataGenerator] ✅ Generated \(data.count) mock sensor data points")
        return data
    }

    /// Generate a single realistic sensor data point
    private static func generateSingleDataPoint(at timestamp: Date) -> SensorData {
        // Simulate realistic variations over time
        let timeOffset = timestamp.timeIntervalSinceReferenceDate
        let hourOfDay = Calendar.current.component(.hour, from: timestamp)

        // Temperature varies slightly (36.0-37.5°C) with circadian rhythm
        let baseTemp = 36.5
        let circadianOffset = sin(Double(hourOfDay) * .pi / 12.0) * 0.5
        let randomVariation = Double.random(in: -0.2...0.2)
        let temperature = baseTemp + circadianOffset + randomVariation

        // Battery drains slowly over time (100% to ~85%)
        let hoursSinceStart = timeOffset.truncatingRemainder(dividingBy: 86400) / 3600
        let batteryLevel = max(85, 100 - Int(hoursSinceStart * 0.6))

        // Heart rate varies (60-85 bpm) with some activity peaks
        let baseHR = 70.0
        let activityVariation = sin(timeOffset / 3600) * 10.0
        let heartRate = baseHR + activityVariation + Double.random(in: -5...5)

        // SpO2 stays high (95-100%)
        let spO2 = Double.random(in: 96...99)

        // Accelerometer shows movement patterns
        let movement = sin(timeOffset / 600) * 2.0  // Periodic movement
        let accelX = Int16(movement * 1000 + Double.random(in: -100...100))
        let accelY = Int16(Double.random(in: -200...200))
        let accelZ = Int16(1000 + Double.random(in: -100...100))  // Mostly gravity

        // PPG values with realistic ranges
        let ppgBase: Int32 = 100000
        let ppgVariation = Int32(Double.random(in: -10000...10000))

        return SensorData(
            timestamp: timestamp,
            ppg: PPGData(
                red: Int32(ppgBase + ppgVariation),
                ir: Int32(ppgBase * 2 + ppgVariation),
                green: Int32(ppgBase / 2 + ppgVariation),
                timestamp: timestamp
            ),
            accelerometer: AccelerometerData(
                x: accelX,
                y: accelY,
                z: accelZ,
                timestamp: timestamp
            ),
            temperature: TemperatureData(celsius: temperature, timestamp: timestamp),
            battery: BatteryData(percentage: batteryLevel, timestamp: timestamp),
            heartRate: HeartRateData(bpm: heartRate, quality: 0.9, timestamp: timestamp),
            spo2: SpO2Data(percentage: spO2, quality: 0.9, timestamp: timestamp)
        )
    }

    /// Generate mock data for the last hour
    static func lastHourMockData() -> [SensorData] {
        generateMockData(duration: 3600, samplingInterval: 30)  // 1 hour, 30s intervals
    }

    /// Generate mock data for today
    static func todayMockData() -> [SensorData] {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let duration = now.timeIntervalSince(startOfDay)
        return generateMockData(duration: duration, samplingInterval: 60)  // 1 min intervals
    }

    /// Generate mock data for the last week
    static func lastWeekMockData() -> [SensorData] {
        generateMockData(duration: 7 * 24 * 3600, samplingInterval: 600)  // 1 week, 10 min intervals
    }

    /// Generate mock data for the last month
    static func lastMonthMockData() -> [SensorData] {
        generateMockData(duration: 30 * 24 * 3600, samplingInterval: 3600)  // 30 days, 1 hour intervals
    }
}

// MARK: - Extension for Testing

#if DEBUG
extension HistoricalMockDataGenerator {
    /// Populate a SensorDataProcessor instance with mock historical data
    static func populateMockData(into sensorDataProcessor: SensorDataProcessor, timeRange: TimeRange = .day) {
        Logger.shared.info("[MockDataGenerator] Populating SensorDataProcessor with mock data for range: \(timeRange)")

        let mockData: [SensorData]
        switch timeRange {
        case .minute:
            mockData = lastHourMockData() // Use hour data for minute range
        case .hour:
            mockData = lastHourMockData()
        case .day:
            mockData = todayMockData()
        case .week:
            mockData = lastWeekMockData()
        case .month:
            mockData = lastMonthMockData()
        }

        // Populate using the public method
        Task { @MainActor in
            sensorDataProcessor.populateHistory(with: mockData)
            Logger.shared.info("[MockDataGenerator] ✅ Populated \(mockData.count) mock data points into SensorDataProcessor")
        }
    }
}
#endif
