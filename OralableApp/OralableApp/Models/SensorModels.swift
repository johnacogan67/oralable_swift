//
//  SensorModels.swift
//  OralableApp
//
//  Updated: October 28, 2025
//  Added: SpO2 measurement support
//

import Foundation
import OralableCore

// MARK: - Main Sensor Data Container

/// Container for all sensor data from the Oralable device
struct SensorData: Identifiable, Codable {
    let id: UUID
    let timestamp: Date

    // Raw sensor data
    let ppg: PPGData
    let accelerometer: AccelerometerData
    let temperature: TemperatureData
    let battery: BatteryData

    // Calculated metrics
    let heartRate: HeartRateData?
    let spo2: SpO2Data?  // Blood oxygen saturation

    // Device identification
    let deviceType: DeviceType

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        ppg: PPGData,
        accelerometer: AccelerometerData,
        temperature: TemperatureData,
        battery: BatteryData,
        heartRate: HeartRateData? = nil,
        spo2: SpO2Data? = nil,
        deviceType: DeviceType = .oralable
    ) {
        self.id = id
        self.timestamp = timestamp
        self.ppg = ppg
        self.accelerometer = accelerometer
        self.temperature = temperature
        self.battery = battery
        self.heartRate = heartRate
        self.spo2 = spo2
        self.deviceType = deviceType
    }
    
    // MARK: - Mock Data
    
    /// Generate a batch of mock sensor data for testing
    static func mockBatch() -> [[String: Any]] {
        let now = Date()
        var batch: [[String: Any]] = []
        
        // Generate 10 mock data points
        for i in 0..<10 {
            let timestamp = now.addingTimeInterval(TimeInterval(-i * 5))
            
            let mockData: [String: Any] = [
                "id": UUID().uuidString,
                "timestamp": timestamp,
                "ppg": [
                    "red": Int32.random(in: 50000...250000),
                    "ir": Int32.random(in: 50000...250000),
                    "green": Int32.random(in: 50000...250000),
                    "timestamp": timestamp
                ],
                "accelerometer": [
                    "x": Int16.random(in: -100...100),
                    "y": Int16.random(in: -100...100),
                    "z": Int16.random(in: -100...100),
                    "timestamp": timestamp
                ],
                "temperature": [
                    "celsius": Double.random(in: 36.0...37.5),
                    "timestamp": timestamp
                ],
                "battery": [
                    "percentage": Int.random(in: 50...100),
                    "timestamp": timestamp
                ],
                "heartRate": [
                    "bpm": Double.random(in: 60...90),
                    "quality": Double.random(in: 0.7...1.0),
                    "timestamp": timestamp
                ],
                "spo2": [
                    "percentage": Double.random(in: 95...100),
                    "quality": Double.random(in: 0.7...1.0),
                    "timestamp": timestamp
                ]
            ]
            
            batch.append(mockData)
        }
        
        return batch
    }
}

// MARK: - PPG Data

/// PPG (Photoplethysmography) sensor data with three wavelengths
struct PPGData: Codable {
    let red: Int32
    let ir: Int32      // Infrared
    let green: Int32
    let timestamp: Date
    
    /// Signal quality indicator (0.0 to 1.0)
    var signalQuality: Double {
        // Simple quality check based on reasonable value ranges
        let redValid = (10000...500000).contains(red)
        let irValid = (10000...500000).contains(ir)
        let greenValid = (10000...500000).contains(green)
        
        let validCount = [redValid, irValid, greenValid].filter { $0 }.count
        return Double(validCount) / 3.0
    }
}

// MARK: - Accelerometer Data

/// 3-axis accelerometer data
struct AccelerometerData: Codable {
    let x: Int16
    let y: Int16
    let z: Int16
    let timestamp: Date
    
    /// Calculate magnitude of acceleration vector
    var magnitude: Double {
        let xD = Double(x)
        let yD = Double(y)
        let zD = Double(z)
        return sqrt(xD * xD + yD * yD + zD * zD)
    }
    
    /// Simple movement detection
    var isMoving: Bool {
        // Threshold for movement detection (adjust based on calibration)
        return magnitude > 100
    }
}

// MARK: - Temperature Data

/// Body temperature measurement
struct TemperatureData: Codable {
    let celsius: Double
    let timestamp: Date
    
    /// Convert to Fahrenheit
    var fahrenheit: Double {
        return celsius * 9.0 / 5.0 + 32.0
    }
    
    /// Temperature status indicator
    var status: String {
        switch celsius {
        case ..<34.0:
            return "Low"
        case 34.0..<36.0:
            return "Below Normal"
        case 36.0...37.5:
            return "Normal"
        case 37.5..<38.5:
            return "Slightly Elevated"
        case 38.5...:
            return "Elevated"
        default:
            return "Unknown"
        }
    }
}

// MARK: - Battery Data

/// Device battery level
struct BatteryData: Codable {
    let percentage: Int
    let timestamp: Date
    
    /// Battery status indicator
    var status: String {
        switch percentage {
        case 0..<10:
            return "Critical"
        case 10..<20:
            return "Low"
        case 20..<50:
            return "Medium"
        case 50..<80:
            return "Good"
        case 80...100:
            return "Excellent"
        default:
            return "Unknown"
        }
    }
    
    /// Whether battery needs charging soon
    var needsCharging: Bool {
        return percentage < 20
    }
}

// MARK: - Heart Rate Data

/// Heart rate measurement with quality assessment
struct HeartRateData: Codable {
    /// Beats per minute
    let bpm: Double
    
    /// Signal quality score (0.0 to 1.0)
    let quality: Double
    
    /// Timestamp of measurement
    let timestamp: Date
    
    /// Whether this measurement is considered valid
    var isValid: Bool {
        return (40...200).contains(bpm) && quality >= 0.6
    }
    
    /// Quality level description
    var qualityLevel: String {
        switch quality {
        case 0.9...1.0:
            return "Excellent"
        case 0.8..<0.9:
            return "Good"
        case 0.7..<0.8:
            return "Fair"
        case 0.6..<0.7:
            return "Acceptable"
        default:
            return "Poor"
        }
    }
    
    /// Color for quality indicator
    var qualityColor: String {
        switch quality {
        case 0.85...1.0:
            return "green"
        case 0.7..<0.85:
            return "yellow"
        case 0.6..<0.7:
            return "orange"
        default:
            return "red"
        }
    }
    
    /// Heart rate zone
    var zone: String {
        switch bpm {
        case 40..<60:
            return "Resting"
        case 60..<100:
            return "Normal"
        case 100..<120:
            return "Elevated"
        case 120..<160:
            return "Exercise"
        case 160...:
            return "High Intensity"
        default:
            return "Unknown"
        }
    }
}

// MARK: - SpO2 Data

/// Blood oxygen saturation measurement with quality assessment
struct SpO2Data: Codable {
    /// Blood oxygen saturation percentage (70-100%)
    let percentage: Double
    
    /// Signal quality score (0.0 to 1.0)
    let quality: Double
    
    /// Timestamp of measurement
    let timestamp: Date
    
    /// Whether this measurement is considered valid
    var isValid: Bool {
        return (70...100).contains(percentage) && quality >= 0.6
    }
    
    /// Quality level description
    var qualityLevel: String {
        switch quality {
        case 0.9...1.0:
            return "Excellent"
        case 0.8..<0.9:
            return "Good"
        case 0.7..<0.8:
            return "Fair"
        case 0.6..<0.7:
            return "Acceptable"
        default:
            return "Poor"
        }
    }
    
    /// Color for quality indicator
    var qualityColor: String {
        switch quality {
        case 0.85...1.0:
            return "green"
        case 0.7..<0.85:
            return "yellow"
        case 0.6..<0.7:
            return "orange"
        default:
            return "red"
        }
    }
    
    /// Health status based on SpO2 value
    var healthStatus: String {
        switch percentage {
        case 95...100:
            return "Normal"
        case 90..<95:
            return "Borderline"
        case 85..<90:
            return "Low"
        default:
            return "Very Low"
        }
    }
    
    /// Color for health status
    var healthStatusColor: String {
        switch percentage {
        case 95...100:
            return "green"
        case 90..<95:
            return "yellow"
        case 85..<90:
            return "orange"
        default:
            return "red"
        }
    }
}

// MARK: - Historical Data

/// Aggregated sensor data for historical analysis
struct HistoricalDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    
    // Aggregated metrics
    let averageHeartRate: Double?
    let heartRateQuality: Double?
    
    let averageSpO2: Double?        // NEW
    let spo2Quality: Double?        // NEW
    
    let averageTemperature: Double
    let averageBattery: Int
    
    // Activity metrics
    let movementIntensity: Double
    let movementVariability: Double  // Standard deviation of accelerometer magnitude
    let grindingEvents: Int?
    let averagePPGIR: Double?
    let averagePPGRed: Double?
    let averagePPGGreen: Double?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        averageHeartRate: Double? = nil,
        heartRateQuality: Double? = nil,
        averageSpO2: Double? = nil,
        spo2Quality: Double? = nil,
        averageTemperature: Double,
        averageBattery: Int,
        movementIntensity: Double,
        movementVariability: Double = 0,
        grindingEvents: Int? = nil,
        averagePPGIR: Double? = nil,
        averagePPGRed: Double? = nil,
        averagePPGGreen: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.averageHeartRate = averageHeartRate
        self.heartRateQuality = heartRateQuality
        self.averageSpO2 = averageSpO2
        self.spo2Quality = spo2Quality
        self.averageTemperature = averageTemperature
        self.averageBattery = averageBattery
        self.movementIntensity = movementIntensity
        self.movementVariability = movementVariability
        self.grindingEvents = grindingEvents
        self.averagePPGIR = averagePPGIR
        self.averagePPGRed = averagePPGRed
        self.averagePPGGreen = averagePPGGreen
    }

    // MARK: - G-Unit Conversions

    /// Movement intensity converted to g units
    /// Note: movementIntensity is the raw magnitude from accelerometer
    var movementIntensityInG: Double {
        // The raw magnitude is sqrt(x² + y² + z²) where x, y, z are Int16 values
        // We use the fixed-point conversion: raw / 16384 = g (for ±2g at 14-bit)
        return movementIntensity / 16384.0
    }

    /// Whether this data point represents a rest state (magnitude ~1g)
    var isAtRest: Bool {
        let mag = movementIntensityInG
        return abs(mag - 1.0) < AccelerometerConversion.restTolerance
    }
}
