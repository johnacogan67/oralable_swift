//
//  BLESensorRepository.swift
//  OralableApp
//
//  Created: November 8, 2025
//  Adapter that makes OralableBLE conform to SensorRepository protocol
//

import Foundation
import OralableCore

/// Repository implementation that wraps SensorDataProcessor
@MainActor
class BLESensorRepository: SensorRepository {

    private let sensorDataProcessor: SensorDataProcessor

    init(sensorDataProcessor: SensorDataProcessor) {
        self.sensorDataProcessor = sensorDataProcessor
    }
    
    // MARK: - Save Operations
    
    func save(_ reading: SensorReading) async throws {
        // OralableBLE receives data from devices, no manual save needed
        // This could be extended to persist to disk if needed
    }
    
    func save(_ readings: [SensorReading]) async throws {
        // OralableBLE receives data from devices, no manual save needed
    }
    
    // MARK: - Query Operations
    
    func readings(for sensorType: SensorType) async throws -> [SensorReading] {
        // Extract readings from sensorDataHistory based on sensor type
        let deviceId = "sensor-data-processor"
        let history = sensorDataProcessor.sensorDataHistory
        
        switch sensorType {
        case .heartRate:
            return history.compactMap { sensorData in
                guard let hrData = sensorData.heartRate else { return nil }
                return SensorReading(
                    id: UUID(),
                    sensorType: .heartRate,
                    value: hrData.bpm,
                    timestamp: sensorData.timestamp,
                    deviceId: deviceId,
                    quality: hrData.quality
                )
            }
            
        case .spo2:
            return history.compactMap { sensorData in
                guard let spo2Data = sensorData.spo2 else { return nil }
                return SensorReading(
                    id: UUID(),
                    sensorType: .spo2,
                    value: spo2Data.percentage,
                    timestamp: sensorData.timestamp,
                    deviceId: deviceId,
                    quality: spo2Data.quality
                )
            }
            
        case .temperature:
            return history.map { sensorData in
                SensorReading(
                    id: UUID(),
                    sensorType: .temperature,
                    value: sensorData.temperature.celsius,
                    timestamp: sensorData.timestamp,
                    deviceId: deviceId,
                    quality: 1.0
                )
            }
            
        case .accelerometerX:
            return history.map { sensorData in
                SensorReading(
                    id: UUID(),
                    sensorType: .accelerometerX,
                    value: Double(sensorData.accelerometer.x) / 16384.0,
                    timestamp: sensorData.timestamp,
                    deviceId: deviceId,
                    quality: 1.0
                )
            }
            
        case .accelerometerY:
            return history.map { sensorData in
                SensorReading(
                    id: UUID(),
                    sensorType: .accelerometerY,
                    value: Double(sensorData.accelerometer.y) / 16384.0,
                    timestamp: sensorData.timestamp,
                    deviceId: deviceId,
                    quality: 1.0
                )
            }
            
        case .accelerometerZ:
            return history.map { sensorData in
                SensorReading(
                    id: UUID(),
                    sensorType: .accelerometerZ,
                    value: Double(sensorData.accelerometer.z) / 16384.0,
                    timestamp: sensorData.timestamp,
                    deviceId: deviceId,
                    quality: 1.0
                )
            }
            
        case .battery:
            return history.map { sensorData in
                SensorReading(
                    id: UUID(),
                    sensorType: .battery,
                    value: Double(sensorData.battery.percentage),
                    timestamp: sensorData.timestamp,
                    deviceId: deviceId,
                    quality: 1.0
                )
            }
            
        case .ppgRed:
            return history.map { sensorData in
                SensorReading(
                    id: UUID(),
                    sensorType: .ppgRed,
                    value: Double(sensorData.ppg.red),
                    timestamp: sensorData.timestamp,
                    deviceId: deviceId,
                    quality: sensorData.ppg.signalQuality
                )
            }
            
        case .ppgInfrared:
            return history.map { sensorData in
                SensorReading(
                    id: UUID(),
                    sensorType: .ppgInfrared,
                    value: Double(sensorData.ppg.ir),
                    timestamp: sensorData.timestamp,
                    deviceId: deviceId,
                    quality: sensorData.ppg.signalQuality
                )
            }
            
        case .ppgGreen:
            return history.map { sensorData in
                SensorReading(
                    id: UUID(),
                    sensorType: .ppgGreen,
                    value: Double(sensorData.ppg.green),
                    timestamp: sensorData.timestamp,
                    deviceId: deviceId,
                    quality: sensorData.ppg.signalQuality
                )
            }
            
        // For sensor types that don't have data in SensorData, return empty
        case .emg, .muscleActivity:
            return []
        }
    }
    
    func readings(
        for sensorType: SensorType,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [SensorReading] {
        let allReadings = try await readings(for: sensorType)
        return allReadings.filter { reading in
            reading.timestamp >= startDate && reading.timestamp <= endDate
        }
    }
    
    func readings(from deviceId: String) async throws -> [SensorReading] {
        // Get all sensor readings from all types for this device
        var allReadings: [SensorReading] = []
        
        for sensorType in SensorType.allCases {
            let readings = try await self.readings(for: sensorType)
            allReadings.append(contentsOf: readings.filter { $0.deviceId == deviceId })
        }
        
        return allReadings.sorted { $0.timestamp < $1.timestamp }
    }
    
    func latestReading(for sensorType: SensorType) async throws -> SensorReading? {
        let readings = try await self.readings(for: sensorType)
        return readings.max { $0.timestamp < $1.timestamp }
    }
    
    func readingsCount(for sensorType: SensorType) async throws -> Int {
        let readings = try await self.readings(for: sensorType)
        return readings.count
    }
    
    func allReadings(from startDate: Date, to endDate: Date) async throws -> [SensorReading] {
        var allReadings: [SensorReading] = []
        
        for sensorType in SensorType.allCases {
            let readings = try await self.readings(for: sensorType, from: startDate, to: endDate)
            allReadings.append(contentsOf: readings)
        }
        
        return allReadings.sorted { $0.timestamp < $1.timestamp }
    }
    
    // MARK: - Summary Operations
    
    func dataSummary() async throws -> DataSummary {
        var readingsBySensor: [SensorType: Int] = [:]
        var latestReadings: [SensorType: SensorReading] = [:]
        var allReadings: [SensorReading] = []
        var totalReadings = 0
        var earliestDate: Date?
        var latestDate: Date?
        var deviceIds: Set<String> = []
        
        for sensorType in SensorType.allCases {
            let readings = try await self.readings(for: sensorType)
            readingsBySensor[sensorType] = readings.count
            totalReadings += readings.count
            allReadings.append(contentsOf: readings)
            
            // Collect device IDs
            readings.forEach { 
                if let deviceId = $0.deviceId {
                    deviceIds.insert(deviceId)
                }
            }
            
            if let latest = readings.max(by: { $0.timestamp < $1.timestamp }) {
                latestReadings[sensorType] = latest
                
                if latestDate == nil || latest.timestamp > latestDate! {
                    latestDate = latest.timestamp
                }
            }
            
            if let earliest = readings.min(by: { $0.timestamp < $1.timestamp }) {
                if earliestDate == nil || earliest.timestamp < earliestDate! {
                    earliestDate = earliest.timestamp
                }
            }
        }
        
        let dateRange: DateInterval?
        if let start = earliestDate, let end = latestDate {
            dateRange = DateInterval(start: start, end: end)
        } else {
            dateRange = nil
        }
        
        // Calculate quality metrics
        let qualityMetrics = calculateQualityMetrics(from: allReadings)
        
        return DataSummary(
            totalReadings: totalReadings,
            dateRange: dateRange,
            readingsBySensor: readingsBySensor,
            latestReadings: latestReadings,
            connectedDevices: deviceIds,
            qualityMetrics: qualityMetrics
        )
    }
    
    // MARK: - Private Helper Methods
    
    private func calculateQualityMetrics(from readings: [SensorReading]) -> DataQualityMetrics {
        let readingsWithQuality = readings.filter { $0.quality != nil }
        let readingsWithQualityPercentage = readings.isEmpty ? 0.0 : 
            Double(readingsWithQuality.count) / Double(readings.count)
        
        let averageQuality = readingsWithQuality.isEmpty ? 0.0 :
            readingsWithQuality.compactMap { $0.quality }.reduce(0.0, +) / Double(readingsWithQuality.count)
        
        let invalidReadings = readings.filter { !$0.isValid }.count
        let validReadingsPercentage = readings.isEmpty ? 0.0 :
            Double(readings.count - invalidReadings) / Double(readings.count)
        
        // Simple data gap detection (gaps > 1 minute)
        let dataGaps = detectDataGaps(in: readings)
        
        return DataQualityMetrics(
            readingsWithQuality: readingsWithQualityPercentage,
            averageQuality: averageQuality,
            invalidReadings: invalidReadings,
            validReadingsPercentage: validReadingsPercentage,
            dataGaps: dataGaps
        )
    }
    
    private func detectDataGaps(in readings: [SensorReading]) -> [DateInterval] {
        guard !readings.isEmpty else { return [] }
        
        let sortedReadings = readings.sorted { $0.timestamp < $1.timestamp }
        var gaps: [DateInterval] = []
        
        for i in 0..<(sortedReadings.count - 1) {
            let current = sortedReadings[i]
            let next = sortedReadings[i + 1]
            let timeDifference = next.timestamp.timeIntervalSince(current.timestamp)
            
            // Consider a gap if more than 1 minute between readings
            if timeDifference > 60 {
                gaps.append(DateInterval(start: current.timestamp, end: next.timestamp))
            }
        }
        
        return gaps
    }
    
    func recentReadings(limit: Int) async throws -> [SensorReading] {
        // Get recent readings from all sensor types
        var allReadings: [SensorReading] = []
        
        for sensorType in SensorType.allCases {
            let readings = try await self.readings(for: sensorType)
            allReadings.append(contentsOf: readings)
        }
        
        // Sort by timestamp descending and take limit
        return Array(allReadings.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }
    
    // MARK: - Maintenance Operations
    
    func clearAllData() async throws {
        // Clear the sensor data history
        sensorDataProcessor.clearHistory()
    }
    
    func clearData(olderThan date: Date) async throws {
        // Note: SensorDataProcessor doesn't expose a method to filter history
        // This would require adding a method to SensorDataProcessor to support this
        // For now, we clear all data if implementation is needed
        // TODO: Add a filterHistory(olderThan:) method to SensorDataProcessor
    }
    
    func storageSize() async throws -> Int64 {
        // Rough estimate based on number of readings
        let summary = try await dataSummary()
        // Assume ~100 bytes per reading on average
        return Int64(summary.totalReadings * 100)
    }
}
