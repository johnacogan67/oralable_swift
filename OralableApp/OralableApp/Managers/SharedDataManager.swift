import Foundation
import CloudKit
import Compression

// MARK: - Data Compression Helpers

extension Data {
    /// Compress data using LZFSE algorithm
    func compressed() -> Data? {
        guard !isEmpty else { return nil }

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { destinationBuffer.deallocate() }

        let compressedSize = withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePointer = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return compression_encode_buffer(
                destinationBuffer,
                count,
                sourcePointer,
                count,
                nil,
                COMPRESSION_LZFSE
            )
        }

        guard compressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: compressedSize)
    }

    /// Decompress data using LZFSE algorithm
    func decompressed(expectedSize: Int) -> Data? {
        guard !isEmpty else { return nil }

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = withUnsafeBytes { sourceBuffer -> Int in
            guard let sourcePointer = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return compression_decode_buffer(
                destinationBuffer,
                expectedSize,
                sourcePointer,
                count,
                nil,
                COMPRESSION_LZFSE
            )
        }

        guard decompressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
}

// MARK: - Shared Data Models

struct SharedPatientData: Identifiable {
    let id: UUID
    let patientID: String          // Anonymized patient identifier
    let dentistID: String          // Professional's Apple ID (CloudKit field name is "dentistID" for compatibility)
    let shareCode: String          // 6-digit share code
    let accessGrantedDate: Date
    let expiryDate: Date?          // Optional time limit
    let permissions: SharePermission
    let isActive: Bool

    init(patientID: String, dentistID: String, shareCode: String, permissions: SharePermission = .readOnly, expiryDate: Date? = nil) {
        self.id = UUID()
        self.patientID = patientID
        self.dentistID = dentistID
        self.shareCode = shareCode
        self.accessGrantedDate = Date()
        self.expiryDate = expiryDate
        self.permissions = permissions
        self.isActive = true
    }
}

enum SharePermission: String, Codable {
    case readOnly = "read_only"
    case readWrite = "read_write"  // Future use
}

struct SharedProfessional: Identifiable {
    let id: String
    let professionalID: String
    let professionalName: String?
    let sharedDate: Date
    let expiryDate: Date?
    let isActive: Bool
}

// MARK: - Shared Data Manager

@MainActor
class SharedDataManager: ObservableObject {
    @Published var sharedProfessionals: [SharedProfessional] = []
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var errorMessage: String?
    @Published var lastSyncDate: Date?

    private let container: CKContainer
    private let publicDatabase: CKDatabase
    private let authenticationManager: AuthenticationManager
    private weak var sensorDataProcessor: SensorDataProcessor?

    init(authenticationManager: AuthenticationManager, sensorDataProcessor: SensorDataProcessor? = nil) {
        // Use shared container for both patient and professional apps
        self.container = CKContainer(identifier: "iCloud.com.jacdental.oralable.shared")

        // Use public database for data sharing between patient and professional apps
        self.publicDatabase = container.publicCloudDatabase

        // Store reference to authentication manager
        self.authenticationManager = authenticationManager

        // Store reference to sensor data processor for sensor data access
        self.sensorDataProcessor = sensorDataProcessor

        loadSharedProfessionals()
    }

    // Computed property for backward compatibility
    private var userID: String? {
        return authenticationManager.userID
    }

    // MARK: - Patient Side: Generate Share Code

    func generateShareCode() -> String {
        // Generate 6-digit code
        let code = String(format: "%06d", Int.random(in: 0...999999))
        return code
    }

    func createShareInvitation() async throws -> String {
        guard let patientID = userID else {
            throw ShareError.notAuthenticated
        }

        isLoading = true
        errorMessage = nil

        let shareCode = generateShareCode()
        
        print("📤 Creating ShareInvitation with code: \(shareCode)")
        print("📤 Patient ID: \(patientID)")
        print("📤 Database: \(publicDatabase.databaseScope == .public ? "PUBLIC" : "PRIVATE")")

        // Create CloudKit record
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: "ShareInvitation", recordID: recordID)

        record["patientID"] = patientID as CKRecordValue
        record["shareCode"] = shareCode as CKRecordValue
        record["createdDate"] = Date() as CKRecordValue
        record["expiryDate"] = Calendar.current.date(byAdding: .hour, value: 48, to: Date()) as CKRecordValue?
        record["isActive"] = 1 as CKRecordValue
        record["dentistID"] = "" as CKRecordValue

        do {
            let savedRecord = try await publicDatabase.save(record)
            print("✅ ShareInvitation saved successfully: \(savedRecord.recordID)")
            isLoading = false
            return shareCode
        } catch {
            print("❌ Failed to save ShareInvitation: \(error)")
            isLoading = false
            errorMessage = "Failed to create share invitation: \(error.localizedDescription)"
            throw ShareError.cloudKitError(error)
        }
    }

    func revokeAccessForProfessional(professionalID: String) async throws {
        guard let patientID = userID else {
            throw ShareError.notAuthenticated
        }

        isLoading = true
        errorMessage = nil

        // Query for the share record
        let predicate = NSPredicate(format: "patientID == %@ AND dentistID == %@", patientID, professionalID)
        let query = CKQuery(recordType: "SharedPatientData", predicate: predicate)

        do {
            let (matchResults, _) = try await publicDatabase.records(matching: query)

            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    // Mark as inactive
                    record["isActive"] = 0 as CKRecordValue
                    try await publicDatabase.save(record)
                case .failure(let error):
                    Logger.shared.error("[SharedDataManager] Error fetching record: \(error)")
                }
            }

            // Reload shared professionals
            await loadSharedProfessionals()

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to revoke access: \(error.localizedDescription)"
            throw ShareError.cloudKitError(error)
        }
    }

    func loadSharedProfessionals() {
        guard let patientID = userID else { return }

        Task {
            isLoading = true

            let predicate = NSPredicate(format: "patientID == %@ AND isActive == 1", patientID)
            let query = CKQuery(recordType: "SharedPatientData", predicate: predicate)

            do {
                let (matchResults, _) = try await publicDatabase.records(matching: query)

                var professionals: [SharedProfessional] = []
                for (_, result) in matchResults {
                    switch result {
                    case .success(let record):
                        if let professionalID = record["dentistID"] as? String,
                           let sharedDate = record["accessGrantedDate"] as? Date {
                            let professional = SharedProfessional(
                                id: record.recordID.recordName,
                                professionalID: professionalID,
                                professionalName: record["dentistName"] as? String,
                                sharedDate: sharedDate,
                                expiryDate: record["expiryDate"] as? Date,
                                isActive: (record["isActive"] as? Int) == 1
                            )
                            professionals.append(professional)
                        }
                    case .failure(let error):
                        Logger.shared.error("[SharedDataManager] Error loading professional: \(error)")
                    }
                }

                await MainActor.run {
                    self.sharedProfessionals = professionals
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load shared professionals: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Automatic Data Sync (No Sessions Required)
    
    /// Upload current sensor data buffer to CloudKit
    /// This is called when the Share screen appears or when app goes to background
    func syncSensorDataToCloudKit() async throws {
        guard let patientID = userID else {
            Logger.shared.warning("[SharedDataManager] Cannot sync - not authenticated")
            return
        }

        guard let processor = sensorDataProcessor else {
            Logger.shared.warning("[SharedDataManager] Cannot sync - no sensor data processor")
            return
        }

        let sensorData = processor.sensorDataHistory
        guard !sensorData.isEmpty else {
            Logger.shared.info("[SharedDataManager] No sensor data to sync")
            return
        }

        await MainActor.run { self.isSyncing = true }

        // CloudKit verification logging
        Logger.shared.info("[SharedDataManager] 📤 Syncing \(sensorData.count) sensor readings to CloudKit")
        Logger.shared.info("[SharedDataManager] 📤 Patient ID: \(patientID)")
        Logger.shared.info("[SharedDataManager] 📤 Database scope: \(publicDatabase.databaseScope == .public ? "PUBLIC" : "PRIVATE")")
        Logger.shared.info("[SharedDataManager] 📤 Container: \(container.containerIdentifier ?? "unknown")")
        
        // Group data by day for manageable record sizes
        let calendar = Calendar.current
        let groupedByDay = Dictionary(grouping: sensorData) { data in
            calendar.startOfDay(for: data.timestamp)
        }
        
        var successCount = 0
        var errorCount = 0
        
        for (dayStart, dayData) in groupedByDay {
            do {
                // Check if we already have a record for this day
                let existingRecord = try await findExistingRecord(for: patientID, date: dayStart)
                
                if let existing = existingRecord {
                    // Update existing record
                    try await updateDayRecord(existing, with: dayData, patientID: patientID)
                } else {
                    // Create new record
                    try await createDayRecord(for: dayStart, with: dayData, patientID: patientID)
                }
                successCount += 1
            } catch {
                Logger.shared.error("[SharedDataManager] Failed to sync day \(dayStart): \(error)")
                errorCount += 1
            }
        }
        
        await MainActor.run {
            self.isSyncing = false
            self.lastSyncDate = Date()
        }
        
        Logger.shared.info("[SharedDataManager] ✅ Sync complete - \(successCount) days uploaded, \(errorCount) errors")
    }
    
    /// Find existing HealthDataRecord for a specific day
    private func findExistingRecord(for patientID: String, date: Date) async throws -> CKRecord? {
        let calendar = Calendar.current
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: date)!
        
        let predicate = NSPredicate(
            format: "patientID == %@ AND recordingDate >= %@ AND recordingDate < %@",
            patientID,
            date as NSDate,
            dayEnd as NSDate
        )
        let query = CKQuery(recordType: "HealthDataRecord", predicate: predicate)
        
        let (results, _) = try await publicDatabase.records(matching: query, resultsLimit: 1)
        
        if let (_, result) = results.first, case .success(let record) = result {
            return record
        }
        return nil
    }
    
    /// Create a new day record
    private func createDayRecord(for date: Date, with sensorData: [SensorData], patientID: String) async throws {
        let record = CKRecord(recordType: "HealthDataRecord", recordID: CKRecord.ID(recordName: UUID().uuidString))
        
        try await populateRecord(record, with: sensorData, patientID: patientID, date: date)
        
        try await publicDatabase.save(record)
        Logger.shared.info("[SharedDataManager] ✅ Created new day record for \(date)")
    }
    
    /// Update existing day record with new data
    private func updateDayRecord(_ record: CKRecord, with sensorData: [SensorData], patientID: String) async throws {
        let date = record["recordingDate"] as? Date ?? Date()
        
        try await populateRecord(record, with: sensorData, patientID: patientID, date: date)
        
        try await publicDatabase.save(record)
        Logger.shared.info("[SharedDataManager] ✅ Updated day record for \(date)")
    }
    
    /// Populate a record with sensor data
    private func populateRecord(_ record: CKRecord, with sensorData: [SensorData], patientID: String, date: Date) async throws {
        // Calculate metrics
        var bruxismEvents = 0
        var peakIntensity = 0.0
        let bruxismThreshold = 2.0
        var isInEvent = false
        
        for data in sensorData {
            let magnitude = data.accelerometer.magnitude
            if magnitude > bruxismThreshold {
                if !isInEvent {
                    bruxismEvents += 1
                    isInEvent = true
                }
                if magnitude > peakIntensity {
                    peakIntensity = magnitude
                }
            } else {
                isInEvent = false
            }
        }
        
        let averageIntensity = sensorData.isEmpty ? 0.0 :
            sensorData.reduce(0.0) { $0 + $1.accelerometer.magnitude } / Double(sensorData.count)
        
        // Calculate session duration from first to last reading
        let duration: TimeInterval
        if let first = sensorData.first?.timestamp, let last = sensorData.last?.timestamp {
            duration = last.timeIntervalSince(first)
        } else {
            duration = 0
        }
        
        // Set record fields
        record["patientID"] = patientID as CKRecordValue
        record["recordingDate"] = date as CKRecordValue
        record["sessionDuration"] = duration as CKRecordValue
        record["bruxismEvents"] = bruxismEvents as CKRecordValue
        record["averageIntensity"] = averageIntensity as CKRecordValue
        record["peakIntensity"] = peakIntensity as CKRecordValue
        
        // Heart rate data
        let heartRateData = sensorData.compactMap { $0.heartRate?.bpm }
        if !heartRateData.isEmpty, let hrData = try? JSONEncoder().encode(heartRateData) {
            record["heartRateData"] = hrData as CKRecordValue
        }
        
        // SpO2 data
        let spo2Data = sensorData.compactMap { $0.spo2?.percentage }
        if !spo2Data.isEmpty, let spo2JSON = try? JSONEncoder().encode(spo2Data) {
            record["oxygenSaturation"] = spo2JSON as CKRecordValue
        }
        
        // Compress and store full sensor data for time-series charts
        let bruxismSessionData = BruxismSessionData(sensorData: sensorData)
        if let jsonData = try? JSONEncoder().encode(bruxismSessionData) {
            let uncompressedSize = jsonData.count
            if let compressed = jsonData.compressed() {
                record["sensorDataCompressed"] = compressed as CKRecordValue
                record["sensorDataUncompressedSize"] = uncompressedSize as CKRecordValue
                
                let ratio = Double(uncompressedSize) / Double(compressed.count)
                Logger.shared.info("[SharedDataManager] Compressed \(uncompressedSize) -> \(compressed.count) bytes (ratio: \(String(format: "%.1f", ratio))x)")
            }
        }
    }
    
    /// Call this when the Share screen appears or when user wants to sync
    func uploadCurrentDataForSharing() async {
        do {
            try await syncSensorDataToCloudKit()
        } catch {
            Logger.shared.error("[SharedDataManager] ❌ Failed to sync data: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to sync data: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Get Patient Health Data for Sharing

    func getPatientHealthDataForSharing(from startDate: Date, to endDate: Date) async throws -> [HealthDataRecord] {
        // Get sensor data from processor
        var sensorRecords: [HealthDataRecord] = []

        if let processor = sensorDataProcessor {
            let sensorData = processor.sensorDataHistory.filter {
                $0.timestamp >= startDate && $0.timestamp <= endDate
            }

            if !sensorData.isEmpty {
                // Convert to shareable format
                let bruxismData = BruxismSessionData(sensorData: sensorData)

                if let encodedData = try? JSONEncoder().encode(bruxismData) {
                    let record = HealthDataRecord(
                        recordID: UUID().uuidString,
                        recordingDate: startDate,
                        dataType: "bruxism_session",
                        measurements: encodedData,
                        sessionDuration: endDate.timeIntervalSince(startDate)
                    )
                    sensorRecords.append(record)
                }
            }
        }

        return sensorRecords
    }

    // MARK: - Upload Recording Session to CloudKit (Legacy - kept for compatibility)

    /// Upload a completed recording session to CloudKit with full sensor data
    func uploadRecordingSession(_ session: RecordingSession) async throws {
        guard let patientID = userID else {
            Logger.shared.warning("[SharedDataManager] Cannot upload session - not authenticated")
            throw ShareError.notAuthenticated
        }

        guard session.status == .completed, let endTime = session.endTime else {
            Logger.shared.warning("[SharedDataManager] Cannot upload incomplete session")
            return
        }

        Logger.shared.info("[SharedDataManager] Uploading session \(session.id) to CloudKit with sensor data")

        // Get sensor data for the session time range
        var bruxismEvents = 0
        var averageIntensity = 0.0
        var peakIntensity = 0.0
        var heartRateData: [Double] = []
        var oxygenSaturation: [Double] = []
        var sensorDataJSON: Data? = nil
        var uncompressedSize: Int = 0

        if let processor = sensorDataProcessor {
            // Filter sensor data to this session's time range
            let sessionData = processor.sensorDataHistory.filter {
                $0.timestamp >= session.startTime && $0.timestamp <= endTime
            }

            Logger.shared.info("[SharedDataManager] Found \(sessionData.count) sensor readings for session")

            // Calculate bruxism events (simple threshold-based detection)
            let bruxismThreshold = 2.0 // g-force threshold
            var isInEvent = false

            for data in sessionData {
                let magnitude = data.accelerometer.magnitude

                if magnitude > bruxismThreshold {
                    if !isInEvent {
                        bruxismEvents += 1
                        isInEvent = true
                    }
                    if magnitude > peakIntensity {
                        peakIntensity = magnitude
                    }
                } else {
                    isInEvent = false
                }
            }

            // Calculate average intensity from all readings
            if !sessionData.isEmpty {
                let totalIntensity = sessionData.reduce(0.0) { $0 + $1.accelerometer.magnitude }
                averageIntensity = totalIntensity / Double(sessionData.count)
            }

            // Extract heart rate data
            heartRateData = sessionData.compactMap { $0.heartRate?.bpm }

            // Extract SpO2 data
            oxygenSaturation = sessionData.compactMap { $0.spo2?.percentage }

            // Create serializable sensor data for time-series sharing
            let bruxismSessionData = BruxismSessionData(sensorData: sessionData)

            // Encode and compress sensor data
            if let jsonData = try? JSONEncoder().encode(bruxismSessionData) {
                uncompressedSize = jsonData.count
                sensorDataJSON = jsonData.compressed()

                let compressionRatio = sensorDataJSON != nil
                    ? Double(uncompressedSize) / Double(sensorDataJSON!.count)
                    : 0
                Logger.shared.info("[SharedDataManager] Sensor data: \(uncompressedSize) bytes -> \(sensorDataJSON?.count ?? 0) bytes (ratio: \(String(format: "%.1f", compressionRatio))x)")
            }

            Logger.shared.info("[SharedDataManager] Calculated metrics: \(bruxismEvents) events, peak: \(peakIntensity), avg: \(averageIntensity)")
        }

        // Create CloudKit record
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: "HealthDataRecord", recordID: recordID)

        record["patientID"] = patientID as CKRecordValue
        record["recordingDate"] = session.startTime as CKRecordValue
        record["sessionDuration"] = session.duration as CKRecordValue
        record["bruxismEvents"] = bruxismEvents as CKRecordValue
        record["averageIntensity"] = averageIntensity as CKRecordValue
        record["peakIntensity"] = peakIntensity as CKRecordValue

        // Store heart rate and SpO2 arrays as JSON data
        if !heartRateData.isEmpty {
            if let hrData = try? JSONEncoder().encode(heartRateData) {
                record["heartRateData"] = hrData as CKRecordValue
            }
        }

        if !oxygenSaturation.isEmpty {
            if let spo2Data = try? JSONEncoder().encode(oxygenSaturation) {
                record["oxygenSaturation"] = spo2Data as CKRecordValue
            }
        }

        // Store compressed sensor data for time-series charts
        if let compressedData = sensorDataJSON {
            record["sensorDataCompressed"] = compressedData as CKRecordValue
            record["sensorDataUncompressedSize"] = uncompressedSize as CKRecordValue
        }

        do {
            try await publicDatabase.save(record)
            Logger.shared.info("[SharedDataManager] ✅ Successfully uploaded session \(session.id) to CloudKit with \(sensorDataJSON?.count ?? 0) bytes sensor data")
        } catch {
            Logger.shared.error("[SharedDataManager] ❌ Failed to upload session: \(error)")
            throw ShareError.cloudKitError(error)
        }
    }

    // MARK: - Account Deletion (Apple App Store Requirement)

    /// Deletes all user data from CloudKit
    /// This is required by Apple for apps that support account creation
    func deleteAllUserData() async throws {
        guard let patientID = userID else {
            Logger.shared.warning("[SharedDataManager] Cannot delete data - not authenticated")
            return
        }

        Logger.shared.info("[SharedDataManager] 🗑️ Starting CloudKit data deletion for user: \(patientID)")
        isLoading = true
        errorMessage = nil

        do {
            // Delete ShareInvitation records
            try await deleteRecords(ofType: "ShareInvitation", forPatientID: patientID)

            // Delete SharedPatientData records
            try await deleteRecords(ofType: "SharedPatientData", forPatientID: patientID)

            // Delete HealthDataRecord records
            try await deleteRecords(ofType: "HealthDataRecord", forPatientID: patientID)

            // Clear local state
            sharedProfessionals = []
            lastSyncDate = nil

            isLoading = false
            Logger.shared.info("[SharedDataManager] 🗑️ Successfully deleted all CloudKit data for user")
        } catch {
            isLoading = false
            errorMessage = "Failed to delete cloud data: \(error.localizedDescription)"
            Logger.shared.error("[SharedDataManager] ❌ Failed to delete CloudKit data: \(error)")
            throw ShareError.cloudKitError(error)
        }
    }

    private func deleteRecords(ofType recordType: String, forPatientID patientID: String) async throws {
        let predicate = NSPredicate(format: "patientID == %@", patientID)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        let (matchResults, _) = try await publicDatabase.records(matching: query)

        var recordIDsToDelete: [CKRecord.ID] = []
        for (recordID, result) in matchResults {
            switch result {
            case .success:
                recordIDsToDelete.append(recordID)
            case .failure(let error):
                Logger.shared.warning("[SharedDataManager] Error fetching \(recordType) record: \(error)")
            }
        }

        if !recordIDsToDelete.isEmpty {
            Logger.shared.info("[SharedDataManager] Deleting \(recordIDsToDelete.count) \(recordType) records")

            // Delete records in batches
            for recordID in recordIDsToDelete {
                try await publicDatabase.deleteRecord(withID: recordID)
            }

            Logger.shared.info("[SharedDataManager] ✅ Deleted \(recordIDsToDelete.count) \(recordType) records")
        } else {
            Logger.shared.info("[SharedDataManager] No \(recordType) records found to delete")
        }
    }
}

// MARK: - Share Errors

enum ShareError: LocalizedError {
    case notAuthenticated
    case cloudKitError(Error)
    case invalidShareCode
    case shareCodeExpired
    case professionalNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to share data"
        case .cloudKitError(let error):
            return "Cloud error: \(error.localizedDescription)"
        case .invalidShareCode:
            return "Invalid share code"
        case .shareCodeExpired:
            return "Share code has expired"
        case .professionalNotFound:
            return "Professional not found"
        }
    }
}

// MARK: - Health Data Record (for sharing)

struct HealthDataRecord: Codable {
    let recordID: String
    let recordingDate: Date
    let dataType: String
    let measurements: Data
    let sessionDuration: TimeInterval
}

// MARK: - Bruxism Session Data (for sharing sensor data)

/// Serializable structure containing bruxism sensor data for sharing with professionals
struct BruxismSessionData: Codable {
    let sensorReadings: [SerializableSensorData]
    let recordingCount: Int
    let startDate: Date
    let endDate: Date

    init(sensorData: [SensorData]) {
        self.sensorReadings = sensorData.map { SerializableSensorData(from: $0) }
        self.recordingCount = sensorData.count
        self.startDate = sensorData.first?.timestamp ?? Date()
        self.endDate = sensorData.last?.timestamp ?? Date()
    }
}

/// Simplified sensor data structure for serialization
struct SerializableSensorData: Codable {
    let timestamp: Date

    // Device identification
    let deviceType: String  // "Oralable" or "ANR M40"

    // PPG data (from Oralable device)
    let ppgRed: Int32
    let ppgIR: Int32
    let ppgGreen: Int32

    // EMG data (from ANR M40 device)
    let emg: Double?

    // Accelerometer data
    let accelX: Int16
    let accelY: Int16
    let accelZ: Int16
    let accelMagnitude: Double

    // Temperature
    let temperatureCelsius: Double

    // Battery
    let batteryPercentage: Int

    // Calculated metrics
    let heartRateBPM: Double?
    let heartRateQuality: Double?
    let spo2Percentage: Double?
    let spo2Quality: Double?

    init(from sensorData: SensorData) {
        self.timestamp = sensorData.timestamp

        // Device type
        self.deviceType = sensorData.deviceType == .anr ? "ANR M40" : "Oralable"

        // PPG data (only valid for Oralable device)
        self.ppgRed = sensorData.ppg.red
        self.ppgIR = sensorData.ppg.ir
        self.ppgGreen = sensorData.ppg.green

        // EMG data - for ANR device, ppg.ir contains the EMG value
        // (ANR firmware sends EMG as a single value mapped to IR channel)
        if sensorData.deviceType == .anr && sensorData.ppg.ir > 0 {
            self.emg = Double(sensorData.ppg.ir)
        } else {
            self.emg = nil
        }

        // Accelerometer data
        self.accelX = sensorData.accelerometer.x
        self.accelY = sensorData.accelerometer.y
        self.accelZ = sensorData.accelerometer.z
        self.accelMagnitude = sensorData.accelerometer.magnitude

        // Temperature
        self.temperatureCelsius = sensorData.temperature.celsius

        // Battery
        self.batteryPercentage = sensorData.battery.percentage

        // Calculated metrics
        self.heartRateBPM = sensorData.heartRate?.bpm
        self.heartRateQuality = sensorData.heartRate?.quality
        self.spo2Percentage = sensorData.spo2?.percentage
        self.spo2Quality = sensorData.spo2?.quality
    }
}
