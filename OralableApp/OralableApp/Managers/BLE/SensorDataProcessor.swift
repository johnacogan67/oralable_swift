import Foundation
import Combine

class SensorDataProcessor: ObservableObject {
    @MainActor static let shared = SensorDataProcessor(calculator: BioMetricCalculator())

    private let calculator: BioMetricCalculator
    
    // History of sensor data for logging and sharing
    @Published private(set) var sensorDataHistory: [SensorData] = []
    private let maxHistoryCount = 10000

    init(calculator: BioMetricCalculator) {
        self.calculator = calculator
    }
    
    /// Clear the sensor data history
    func clearHistory() {
        sensorDataHistory.removeAll()
    }

    /// Populate history with external data (e.g. mock data)
    func populateHistory(with data: [SensorData]) {
        sensorDataHistory.append(contentsOf: data)

        // Trim history if needed
        if sensorDataHistory.count > maxHistoryCount {
            sensorDataHistory.removeFirst(sensorDataHistory.count - maxHistoryCount)
        }
    }

    /// Append a single SensorData reading to history (called from DeviceManagerAdapter)
    func appendToHistory(_ data: SensorData) {
        sensorDataHistory.append(data)

        // Trim history if needed
        if sensorDataHistory.count > maxHistoryCount {
            sensorDataHistory.removeFirst()
        }
    }

    /// Inject a demo reading directly (for demo mode)
    func injectDemoReading(ir: Double, red: Double, green: Double) {
        Task { @MainActor in
            let timestamp = Date()
            let accelData = AccelerometerData(x: 0, y: 0, z: 16384, timestamp: timestamp)
            
            calculator.processFrame(ir: ir, red: red, green: green, accelerometer: accelData)
            
            // Store sensor data in history
            let ppgData = PPGData(red: Int32(red), ir: Int32(ir), green: Int32(green), timestamp: timestamp)
            let tempData = TemperatureData(celsius: 37.0, timestamp: timestamp)
            let batteryData = BatteryData(percentage: 100, timestamp: timestamp)
            
            let sensorData = SensorData(
                timestamp: timestamp,
                ppg: ppgData,
                accelerometer: accelData,
                temperature: tempData,
                battery: batteryData,
                heartRate: nil,
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

    func handleDataUpdate(data: Data) {
        // Expecting 18 bytes: Red(4), IR(4), Green(4), AccX(2), AccY(2), AccZ(2)
        guard data.count >= 18 else { return }

        let (red, ir, green, accX, accY, accZ) = data.withUnsafeBytes { rawBufferPointer -> (Double, Double, Double, Int16, Int16, Int16) in
            // Parse Optical Data (UInt32)
            let red = rawBufferPointer.load(fromByteOffset: 0, as: UInt32.self)
            let ir = rawBufferPointer.load(fromByteOffset: 4, as: UInt32.self)
            let green = rawBufferPointer.load(fromByteOffset: 8, as: UInt32.self)

            // Parse Accelerometer Data (Int16)
            let accX = rawBufferPointer.load(fromByteOffset: 12, as: Int16.self)
            let accY = rawBufferPointer.load(fromByteOffset: 14, as: Int16.self)
            let accZ = rawBufferPointer.load(fromByteOffset: 16, as: Int16.self)

            return (Double(red), Double(ir), Double(green), accX, accY, accZ)
        }

        Task { @MainActor in
            let timestamp = Date()
            let accelData = AccelerometerData(x: accX, y: accY, z: accZ, timestamp: timestamp)
            
            calculator.processFrame(ir: Double(ir), red: Double(red), green: Double(green), accelerometer: accelData)
            
            // Store sensor data in history
            let ppgData = PPGData(red: Int32(red), ir: Int32(ir), green: Int32(green), timestamp: timestamp)
            let tempData = TemperatureData(celsius: 0.0, timestamp: timestamp)
            let batteryData = BatteryData(percentage: 100, timestamp: timestamp)
            
            let sensorData = SensorData(
                timestamp: timestamp,
                ppg: ppgData,
                accelerometer: accelData,
                temperature: tempData,
                battery: batteryData,
                heartRate: nil,
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
