import Foundation
import UIKit
import CloudKit

class LogExportManager {
    static let shared = LogExportManager()
    
    // Device ID (unique per device)
    var deviceID: String {
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
    
    // Apple User ID (from CloudKit)
    private var appleUserID: String? {
        return UserDefaults.standard.string(forKey: "appleUserID")
    }
    
    init() {
        fetchAppleUserID { _ in }
    }
    
    func fetchAppleUserID(completion: @escaping (String?) -> Void) {
        CKContainer.default().fetchUserRecordID { recordID, error in
            if let recordID = recordID {
                let userID = recordID.recordName
                UserDefaults.standard.set(userID, forKey: "appleUserID")
                completion(userID)
            } else {
                Logger.shared.error("[LogExportManager] CloudKit error: \(error?.localizedDescription ?? "unknown")")
                completion(nil)
            }
        }
    }
    
    // Export logs as CSV
    func exportLogsAsCSV(logs: [String], historicalData: [SensorData]) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        var csvContent = "Timestamp,DeviceID,AppleID,Message,PPG_IR,PPG_Red,PPG_Green,Accel_X,Accel_Y,Accel_Z,Temp_C,Battery_%,HeartRate,SpO2\n"
        
        // Export historical sensor data with logs
        for (index, log) in logs.enumerated() {
            let sensorData = index < historicalData.count ? historicalData[index] : createDefaultSensorData()
            
            let timestamp = index < historicalData.count ? sensorData.timestamp : Date()
            let heartRate = sensorData.heartRate?.bpm ?? 0
            let spo2 = sensorData.spo2?.percentage ?? 0
            
            let row = "\(dateFormatter.string(from: timestamp)),\(deviceID),\(appleUserID ?? "none"),\"\(log)\",\(sensorData.ppg.ir),\(sensorData.ppg.red),\(sensorData.ppg.green),\(sensorData.accelerometer.x),\(sensorData.accelerometer.y),\(sensorData.accelerometer.z),\(sensorData.temperature.celsius),\(sensorData.battery.percentage),\(heartRate),\(spo2)\n"
            
            csvContent.append(row)
        }
        
        return saveToFile(content: csvContent, filename: "mam_logs_\(Int(Date().timeIntervalSince1970)).csv")
    }
    
    private func createDefaultSensorData() -> SensorData {
        return SensorData(
            ppg: PPGData(red: 0, ir: 0, green: 0, timestamp: Date()),
            accelerometer: AccelerometerData(x: 0, y: 0, z: 0, timestamp: Date()),
            temperature: TemperatureData(celsius: 0, timestamp: Date()),
            battery: BatteryData(percentage: 0, timestamp: Date())
        )
    }
    
    // Export logs as JSON
    func exportLogsAsJSON(logs: [String], historicalData: [SensorData]) -> URL? {
        let exportData = LogExportData(
            deviceID: deviceID,
            appleID: appleUserID,
            deviceModel: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion,
            exportDate: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            logs: logs,
            sensorDataHistory: historicalData
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            
            let jsonData = try encoder.encode(exportData)
            let filename = "mam_logs_\(Int(Date().timeIntervalSince1970)).json"


            return saveToFile(content: String(data: jsonData, encoding: .utf8) ?? "", filename: filename)
        } catch {
            Logger.shared.error("[LogExportManager] JSON encoding failed: \(error)")
            return nil
        }
    }
    
    private func saveToFile(content: String, filename: String) -> URL? {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            Logger.shared.error("[LogExportManager] Failed to save file: \(error)")
            return nil
        }
    }
}

// Data structures for JSON export
struct LogExportData: Codable {
    let deviceID: String
    let appleID: String?
    let deviceModel: String
    let systemVersion: String
    let exportDate: Date
    let appVersion: String
    let logs: [String]
    let sensorDataHistory: [SensorData]
}
