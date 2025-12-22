import Foundation
import Combine

class SensorDataProcessor: ObservableObject {
    static let shared = SensorDataProcessor(calculator: BioMetricCalculator())
    
    private let calculator: BioMetricCalculator
    
    // History of sensor data for logging and sharing
    private(set) var sensorDataHistory: [SensorData] = []
    private let maxHistoryCount = 10000

    init(calculator: BioMetricCalculator) {
        self.calculator = calculator
    }
    
    /// Clear the sensor data history
    func clearHistory() {
        sensorDataHistory.removeAll()
    }
    
    /// Populate sensor data history with an array of data (typically for testing/mock data)
    @MainActor
    func populateHistory(with data: [SensorData]) {
        sensorDataHistory = data
        
        // Trim if exceeding max history count
        if sensorDataHistory.count > maxHistoryCount {
            let excessCount = sensorDataHistory.count - maxHistoryCount
            sensorDataHistory.removeFirst(excessCount)
        }
    }

    /// Inject demo data reading (for demo mode)
    @MainActor
    func injectDemoReading(ir: Double, red: Double, green: Double) {
        // Default accelerometer values (simulating device at rest)
        let accX: Int16 = 0
        let accY: Int16 = 0
        let accZ: Int16 = 16384 // ~1g in Z axis
        let accMagnitude = 1.0 // Normalized magnitude at rest
        
        // Process through calculator
        calculator.processFrame(red: red, ir: ir, green: green, accelerometer: accMagnitude)
        
        // Store sensor data in history
        let timestamp = Date()
        let ppgData = PPGData(red: Int32(red), ir: Int32(ir), green: Int32(green), timestamp: timestamp)
        let accelData = AccelerometerData(x: accX, y: accY, z: accZ, timestamp: timestamp)
        let tempData = TemperatureData(celsius: 36.5, timestamp: timestamp) // Static temperature for demo
        let batteryData = BatteryData(percentage: 85, timestamp: timestamp) // Static battery for demo
        
        let sensorData = SensorData(
            timestamp: timestamp,
            ppg: ppgData,
            accelerometer: accelData,
            temperature: tempData,
            battery: batteryData,
            heartRate: nil, // Will be calculated by BioMetricCalculator
            spo2: nil,
            deviceType: .oralable
        )
        
        sensorDataHistory.append(sensorData)
        
        // Trim history if needed
        if sensorDataHistory.count > maxHistoryCount {
            sensorDataHistory.removeFirst(sensorDataHistory.count - maxHistoryCount)
        }
    }

    func handleDataUpdate(data: Data) {
        // Expecting 18 bytes: Red(4), IR(4), Green(4), AccX(2), AccY(2), AccZ(2)
        guard data.count >= 18 else { return }

        let (red, ir, green, accX, accY, accZ, accMagnitude) = data.withUnsafeBytes { rawBufferPointer -> (Double, Double, Double, Int16, Int16, Int16, Double) in
            // Parse Optical Data (UInt32)
            let red = rawBufferPointer.load(fromByteOffset: 0, as: UInt32.self)
            let ir = rawBufferPointer.load(fromByteOffset: 4, as: UInt32.self)
            let green = rawBufferPointer.load(fromByteOffset: 8, as: UInt32.self)

            // Parse Accelerometer Data (Int16)
            let accX = rawBufferPointer.load(fromByteOffset: 12, as: Int16.self)
            let accY = rawBufferPointer.load(fromByteOffset: 14, as: Int16.self)
            let accZ = rawBufferPointer.load(fromByteOffset: 16, as: Int16.self)

            // Normalize Accelerometer (16384.0 = 1g range typically)
            let normX = Double(accX) / 16384.0
            let normY = Double(accY) / 16384.0
            let normZ = Double(accZ) / 16384.0

            let accMagnitude = sqrt(normX * normX + normY * normY + normZ * normZ)

            return (Double(red), Double(ir), Double(green), accX, accY, accZ, accMagnitude)
        }

        Task { @MainActor in
            calculator.processFrame(red: red, ir: ir, green: green, accelerometer: accMagnitude)
            
            // Store sensor data in history
            let timestamp = Date()
            let ppgData = PPGData(red: Int32(red), ir: Int32(ir), green: Int32(green), timestamp: timestamp)
            let accelData = AccelerometerData(x: accX, y: accY, z: accZ, timestamp: timestamp)
            let tempData = TemperatureData(celsius: 0.0, timestamp: timestamp) // Temperature not in this packet
            let batteryData = BatteryData(percentage: 100, timestamp: timestamp) // Battery not in this packet
            
            let sensorData = SensorData(
                timestamp: timestamp,
                ppg: ppgData,
                accelerometer: accelData,
                temperature: tempData,
                battery: batteryData,
                heartRate: nil, // Will be calculated by BioMetricCalculator
                spo2: nil,
                deviceType: .oralable
            )
            
            sensorDataHistory.append(sensorData)
            
            // Trim history if needed
            if sensorDataHistory.count > maxHistoryCount {
                sensorDataHistory.removeFirst(sensorDataHistory.count - maxHistoryCount)
            }
        }
    }
}
