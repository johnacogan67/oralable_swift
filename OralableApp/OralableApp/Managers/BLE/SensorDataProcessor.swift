import Foundation
import CoreBluetooth
import Combine

/// Responsible for parsing raw BLE packets and distributing them to the calculator.
@MainActor
final class SensorDataProcessor: ObservableObject {

    // MARK: - Singleton
    static let shared: SensorDataProcessor = {
        // Provide a default calculator for the shared instance
        let calculator = BioMetricCalculator()
        return SensorDataProcessor(calculator: calculator)
    }()

    // MARK: - Dependencies
    private let calculator: BioMetricCalculator

    // MARK: - Published Data Buffer
    /// Rolling history of processed sensor frames for aggregation/sharing
    @Published private(set) var sensorDataHistory: [SensorData] = []

    // Optional: cap history size to avoid unbounded growth (tune as needed)
    private let maxHistoryCount: Int = 50_000

    // MARK: - Init
    init(calculator: BioMetricCalculator) {
        self.calculator = calculator
    }

    // MARK: - Public API

    /// Clear all stored sensor data history
    func clearHistory() {
        sensorDataHistory.removeAll()
    }

    #if DEBUG
    /// Populate history with mock data (for testing only)
    func populateHistory(with data: [SensorData]) {
        sensorDataHistory = data
        Logger.shared.info("[SensorDataProcessor] Populated history with \(data.count) mock data points")
    }
    #endif

    /// Inject demo data readings (for demo mode simulation)
    func injectDemoReading(ir: Double, red: Double, green: Double) {
        // Use a default accelerometer magnitude (simulating at rest)
        let accelerometerMagnitude = 1.0  // ~1g

        // Pass to calculator for processing
        calculator.processFrame(
            red: red,
            ir: ir,
            green: green,
            accelerometer: accelerometerMagnitude
        )

        // Build a SensorData frame for history
        let now = Date()
        let ppg = PPGData(
            red: Int32(red),
            ir: Int32(ir),
            green: Int32(green),
            timestamp: now
        )

        // Default accelerometer values (at rest, ~1g in Z axis)
        let accel = AccelerometerData(
            x: 0,
            y: 0,
            z: 16384,  // ~1g in Z axis
            timestamp: now
        )

        // Default temperature and battery
        let temp = TemperatureData(celsius: 36.5, timestamp: now)
        let batt = BatteryData(percentage: 85, timestamp: now)

        let frame = SensorData(
            timestamp: now,
            ppg: ppg,
            accelerometer: accel,
            temperature: temp,
            battery: batt,
            heartRate: nil,
            spo2: nil,
            deviceType: .oralable
        )

        sensorDataHistory.append(frame)
        if sensorDataHistory.count > maxHistoryCount {
            sensorDataHistory.removeFirst(sensorDataHistory.count - maxHistoryCount)
        }
    }

    /// Entry point for raw BLE characteristic data
    func handleDataUpdate(characteristic: CBCharacteristic) {
        guard let data = characteristic.value else { return }

        // Assuming a packet structure for the Oralable custom characteristic:
        // [Red(4B), IR(4B), Green(4B), AccX(2B), AccY(2B), AccZ(2B)]
        if data.count >= 18 {
            let red = extractUint32(from: data, offset: 0)
            let ir = extractUint32(from: data, offset: 4)
            let green = extractUint32(from: data, offset: 8)

            let accX = extractInt16(from: data, offset: 12)
            let accY = extractInt16(from: data, offset: 14)
            let accZ = extractInt16(from: data, offset: 16)

            // Calculate Accelerometer Magnitude
            // This is our "Noise Reference" for the LMS filter.
            let mag = sqrt(pow(Double(accX), 2) + pow(Double(accY), 2) + pow(Double(accZ), 2)) / 16384.0 // Assuming +/- 2g scale

            // Pass all channels to the calculator for synchronized processing
            calculator.processFrame(
                red: Double(red),
                ir: Double(ir),
                green: Double(green),
                accelerometer: mag
            )

            // Build a SensorData frame for history (using available fields)
            let now = Date()
            let ppg = PPGData(red: Int32(bitPattern: red),
                              ir: Int32(bitPattern: ir),
                              green: Int32(bitPattern: green),
                              timestamp: now)

            let accel = AccelerometerData(x: accX,
                                          y: accY,
                                          z: accZ,
                                          timestamp: now)

            // We don't have temperature/battery in this packet; fill with defaults
            let temp = TemperatureData(celsius: 0.0, timestamp: now)
            let batt = BatteryData(percentage: 0, timestamp: now)

            // If BioMetricCalculator publishes HR/SpO2 separately, we can optionally read them here.
            // For now, leave them nil; downstream code handles optionals.
            let frame = SensorData(
                timestamp: now,
                ppg: ppg,
                accelerometer: accel,
                temperature: temp,
                battery: batt,
                heartRate: nil,
                spo2: nil,
                deviceType: .oralable
            )

            sensorDataHistory.append(frame)
            if sensorDataHistory.count > maxHistoryCount {
                sensorDataHistory.removeFirst(sensorDataHistory.count - maxHistoryCount)
            }
        }
    }

    // MARK: - Helpers

    private func extractUint32(from data: Data, offset: Int) -> UInt32 {
        return data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    private func extractInt16(from data: Data, offset: Int) -> Int16 {
        return data.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: Int16.self) }
    }
}
