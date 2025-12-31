//
//  SensorModels.swift
//  OralableApp
//
//  Re-exports sensor models from OralableCore for backwards compatibility
//  Updated: December 31, 2025
//

import Foundation
@_exported import OralableCore

// MARK: - Note on Model Types
//
// All sensor data types are now defined in OralableCore and automatically
// available via the @_exported import above. This includes:
//
// - PPGData
// - AccelerometerData
// - TemperatureData
// - BatteryData
// - HeartRateData
// - SpO2Data
// - SensorData
// - HistoricalDataPoint
//
// Supporting types:
// - QualityLevel
// - HeartRateZone
// - SpO2HealthStatus
// - TemperatureStatus
// - BatteryStatus
//
// No typealiases needed - types are directly available from OralableCore.
