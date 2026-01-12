//
//  ProfessionalDataManager.swift
//  OralableForProfessionals
//
//  Manages patient data storage and retrieval.
//
//  Responsibilities:
//  - Patient record management
//  - Session data storage
//  - CloudKit sync for shared data
//  - Local cache management
//
//  Data Sources:
//  - CloudKit shared database
//  - Local CSV imports
//  - Demo data for testing
//

import Foundation
import CloudKit
import Combine
import OralableCore

// MARK: - Patient Models

struct ProfessionalPatient: Identifiable, Codable {
    let id: String
    let patientID: String
    let patientName: String?  // Optional - patient may choose anonymity
    let shareCode: String
    let accessGrantedDate: Date
    let lastDataUpdate: Date?
    let recordID: String  // CloudKit record ID
    let isLocalImport: Bool  // true for CSV imports, false for CloudKit links
    let dataPointCount: Int?  // Number of data points for imported participants

    // Default initializer with isLocalImport = false for backwards compatibility
    init(id: String, patientID: String, patientName: String?, shareCode: String,
         accessGrantedDate: Date, lastDataUpdate: Date?, recordID: String,
         isLocalImport: Bool = false, dataPointCount: Int? = nil) {
        self.id = id
        self.patientID = patientID
        self.patientName = patientName
        self.shareCode = shareCode
        self.accessGrantedDate = accessGrantedDate
        self.lastDataUpdate = lastDataUpdate
        self.recordID = recordID
        self.isLocalImport = isLocalImport
        self.dataPointCount = dataPointCount
    }

    var anonymizedID: String {
        // Show only last 4 characters of patient ID for privacy
        let suffix = String(patientID.suffix(4))
        return "Participant-****\(suffix)"
    }

    var displayName: String {
        return patientName ?? anonymizedID
    }

    var displayInitials: String {
        if let name = patientName, !name.isEmpty {
            let components = name.components(separatedBy: " ")
            if components.count >= 2 {
                let firstInitial = components[0].prefix(1)
                let lastInitial = components[1].prefix(1)
                return "\(firstInitial)\(lastInitial)".uppercased()
            } else {
                return String(name.prefix(2)).uppercased()
            }
        } else {
            // For anonymized participants, use "P" + last 2 digits
            let suffix = String(patientID.suffix(2))
            return "P\(suffix)"
        }
    }

    /// Connection type description
    var connectionType: String {
        isLocalImport ? "CSV Import" : "Live Sync"
    }

    /// Icon for the connection type
    var connectionIcon: String {
        isLocalImport ? "doc.text" : "icloud"
    }
}

struct PatientHealthSummary {
    let patientID: String
    let recordingDate: Date
    let sessionDuration: TimeInterval
    let bruxismEvents: Int
    let averageIntensity: Double
    let peakIntensity: Double
    let heartRateData: [Double]
    let oxygenSaturation: [Double]

    var formattedDuration: String {
        let hours = Int(sessionDuration) / 3600
        let minutes = Int(sessionDuration) % 3600 / 60
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Professional Data Manager

@MainActor
class ProfessionalDataManager: ObservableObject {
    static let shared = ProfessionalDataManager()

    // MARK: - Published Properties

    @Published var patients: [ProfessionalPatient] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    // MARK: - Private Properties

    private let container: CKContainer
    private let publicDatabase: CKDatabase

    // Computed property that reads from Keychain (where ProfessionalAuthenticationManager stores it)
    private var professionalID: String? {
        // Read from Keychain using the same key as ProfessionalAuthenticationManager
        let keychainKey = "com.oralable.professional.userID"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let userID = String(data: data, encoding: .utf8) {
            return userID
        }

        // Fallback: check UserDefaults for migration (legacy support)
        return UserDefaults.standard.string(forKey: "professionalAppleID")
    }

    // MARK: - Initialization

    private init() {
        // Use same shared container as patient app
        self.container = CKContainer(identifier: "iCloud.com.jacdental.oralable.shared")

        // For development/testing, use private database which auto-creates schemas
        // In production, switch to publicCloudDatabase after setting up schema
        self.publicDatabase = container.publicCloudDatabase
        // Load existing patients when initialized
        loadPatients()
    }

    // MARK: - Share Code Entry

    func addPatientWithShareCode(_ shareCode: String) async throws {
        guard let professionalID = professionalID else {
            throw ProfessionalDataError.notAuthenticated
        }

        // Validate share code format (6 digits)
        guard shareCode.count == 6, Int(shareCode) != nil else {
            throw ProfessionalDataError.invalidShareCode
        }

        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            // Step 1: Find the share invitation with this code
            let predicate = NSPredicate(format: "shareCode == %@ AND isActive == 1", shareCode)
            let query = CKQuery(recordType: "ShareInvitation", predicate: predicate)

            let (matchResults, _) = try await publicDatabase.records(matching: query)

            guard let (_, result) = matchResults.first else {
                throw ProfessionalDataError.shareCodeNotFound
            }

            guard case .success(let invitationRecord) = result else {
                throw ProfessionalDataError.shareCodeNotFound
            }

            // Step 2: Check if code is expired
            if let expiryDate = invitationRecord["expiryDate"] as? Date,
               expiryDate < Date() {
                throw ProfessionalDataError.shareCodeExpired
            }

            // Step 3: Get patient ID from invitation
            guard let patientID = invitationRecord["patientID"] as? String else {
                throw ProfessionalDataError.invalidShareCode
            }

            // Step 4: Check if professional already has access to this patient
            if patients.contains(where: { $0.patientID == patientID }) {
                throw ProfessionalDataError.patientAlreadyAdded
            }

            // Step 5: Create SharedPatientData record
            let sharedDataID = CKRecord.ID(recordName: UUID().uuidString)
            let sharedDataRecord = CKRecord(recordType: "SharedPatientData", recordID: sharedDataID)

            // Note: CloudKit field names use "dentistID" for backwards compatibility
            sharedDataRecord["patientID"] = patientID as CKRecordValue
            sharedDataRecord["dentistID"] = professionalID as CKRecordValue
            sharedDataRecord["shareCode"] = shareCode as CKRecordValue
            sharedDataRecord["accessGrantedDate"] = Date() as CKRecordValue
            sharedDataRecord["isActive"] = 1 as CKRecordValue
            sharedDataRecord["dentistName"] = getCurrentProfessionalName() as CKRecordValue?

            try await publicDatabase.save(sharedDataRecord)

            // Step 6: Update the invitation to mark it as used
            invitationRecord["dentistID"] = professionalID as CKRecordValue
            invitationRecord["isActive"] = 0 as CKRecordValue
            try await publicDatabase.save(invitationRecord)

            // Step 7: Add to local patient list
            let newPatient = ProfessionalPatient(
                id: sharedDataID.recordName,
                patientID: patientID,
                patientName: nil,  // Will be updated if patient provides name
                shareCode: shareCode,
                accessGrantedDate: Date(),
                lastDataUpdate: nil,
                recordID: sharedDataID.recordName
            )

            await MainActor.run {
                self.patients.append(newPatient)
                self.isLoading = false
                self.successMessage = "Participant added successfully"
            }

        } catch let error as ProfessionalDataError {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
            throw error
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Failed to add participant: \(error.localizedDescription)"
            }
            throw error
        }
    }

    // MARK: - Patient Management

    func loadPatients() {
        guard let professionalID = professionalID else {
            // Still load local participants even if not authenticated
            let localParticipants = loadLocalParticipants()
            if !localParticipants.isEmpty {
                self.patients = localParticipants.sorted { $0.accessGrantedDate > $1.accessGrantedDate }
            }
            return
        }

        Task {
            isLoading = true
            errorMessage = nil

            // Note: CloudKit field name is "dentistID" for backwards compatibility
            let predicate = NSPredicate(format: "dentistID == %@ AND isActive == 1", professionalID)
            let query = CKQuery(recordType: "SharedPatientData", predicate: predicate)

            do {
                let (matchResults, _) = try await publicDatabase.records(matching: query)

                var loadedPatients: [ProfessionalPatient] = []

                for (_, result) in matchResults {
                    switch result {
                    case .success(let record):
                        if let patientID = record["patientID"] as? String,
                           let shareCode = record["shareCode"] as? String,
                           let accessDate = record["accessGrantedDate"] as? Date {

                            let patient = ProfessionalPatient(
                                id: record.recordID.recordName,
                                patientID: patientID,
                                patientName: record["patientName"] as? String,
                                shareCode: shareCode,
                                accessGrantedDate: accessDate,
                                lastDataUpdate: record["lastDataUpdate"] as? Date,
                                recordID: record.recordID.recordName,
                                isLocalImport: false
                            )

                            loadedPatients.append(patient)
                        }
                    case .failure(let error):
                        Logger.shared.error("[ProfessionalDataManager] Error loading patient record: \(error)")
                    }
                }

                // Merge with local participants
                let localParticipants = loadLocalParticipants()
                loadedPatients.append(contentsOf: localParticipants)

                await MainActor.run {
                    self.patients = loadedPatients.sorted { $0.accessGrantedDate > $1.accessGrantedDate }
                    self.isLoading = false
                }

            } catch {
                // Check if this is a "record type not found" error
                // This happens when no patients have been added yet in Development mode
                let nsError = error as NSError
                if nsError.domain == CKErrorDomain && nsError.code == CKError.unknownItem.rawValue {
                    Logger.shared.info("[ProfessionalDataManager] Record type doesn't exist yet - loading local participants only")
                    let localParticipants = loadLocalParticipants()
                    await MainActor.run {
                        self.patients = localParticipants.sorted { $0.accessGrantedDate > $1.accessGrantedDate }
                        self.isLoading = false
                    }
                } else {
                    Logger.shared.error("[ProfessionalDataManager] Failed to load patients: \(error)")
                    // Still load local participants on error
                    let localParticipants = loadLocalParticipants()
                    await MainActor.run {
                        self.patients = localParticipants.sorted { $0.accessGrantedDate > $1.accessGrantedDate }
                        self.errorMessage = "Failed to load participants: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                }
            }
        }
    }

    func removePatient(_ patient: ProfessionalPatient) async throws {
        isLoading = true
        errorMessage = nil

        // Handle local imports differently
        if patient.isLocalImport {
            removeLocalParticipant(patient)
            await MainActor.run {
                self.isLoading = false
                self.successMessage = "Participant removed"
            }
            return
        }

        // CloudKit removal
        do {
            // Find and update the SharedPatientData record
            let recordID = CKRecord.ID(recordName: patient.recordID)
            let record = try await publicDatabase.record(for: recordID)

            record["isActive"] = 0 as CKRecordValue
            try await publicDatabase.save(record)

            await MainActor.run {
                self.patients.removeAll { $0.id == patient.id }
                self.isLoading = false
                self.successMessage = "Participant removed"
            }

        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Failed to remove participant: \(error.localizedDescription)"
            }
            throw error
        }
    }

    // MARK: - Patient Data Fetching

    func fetchPatientHealthData(for patient: ProfessionalPatient, from startDate: Date, to endDate: Date) async throws -> [PatientHealthSummary] {
        isLoading = true
        errorMessage = nil

        do {
            // Query HealthDataRecord CloudKit records for this patient
            let predicate = NSPredicate(
                format: "patientID == %@ AND recordingDate >= %@ AND recordingDate <= %@",
                patient.patientID,
                startDate as NSDate,
                endDate as NSDate
            )
            let query = CKQuery(recordType: "HealthDataRecord", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "recordingDate", ascending: false)]

            let (matchResults, _) = try await publicDatabase.records(matching: query)

            var healthSummaries: [PatientHealthSummary] = []

            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    // Parse health data from record
                    // This is a simplified example - actual implementation would parse sensor data
                    if let recordDate = record["recordingDate"] as? Date,
                       let duration = record["sessionDuration"] as? Double {

                        let summary = PatientHealthSummary(
                            patientID: patient.patientID,
                            recordingDate: recordDate,
                            sessionDuration: duration,
                            bruxismEvents: record["bruxismEvents"] as? Int ?? 0,
                            averageIntensity: record["averageIntensity"] as? Double ?? 0.0,
                            peakIntensity: record["peakIntensity"] as? Double ?? 0.0,
                            heartRateData: [],  // Would parse from measurements data
                            oxygenSaturation: []  // Would parse from measurements data
                        )

                        healthSummaries.append(summary)
                    }
                case .failure(let error):
                    Logger.shared.error("[ProfessionalDataManager] Error loading health record: \(error)")
                }
            }

            await MainActor.run {
                self.isLoading = false
            }

            return healthSummaries

        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Failed to load participant data: \(error.localizedDescription)"
            }
            throw error
        }
    }

    // MARK: - Fetch Sensor Time-Series Data

    /// Fetch detailed sensor data for a patient session (for time-series charts)
    func fetchPatientSensorData(for patient: ProfessionalPatient, sessionDate: Date) async throws -> BruxismSessionData? {
        isLoading = true
        errorMessage = nil

        do {
            // Query for the specific session
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: sessionDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

            let predicate = NSPredicate(
                format: "patientID == %@ AND recordingDate >= %@ AND recordingDate < %@",
                patient.patientID,
                startOfDay as NSDate,
                endOfDay as NSDate
            )
            let query = CKQuery(recordType: "HealthDataRecord", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "recordingDate", ascending: false)]

            let (matchResults, _) = try await publicDatabase.records(matching: query, resultsLimit: 1)

            guard let (_, result) = matchResults.first,
                  case .success(let record) = result else {
                await MainActor.run { self.isLoading = false }
                return nil
            }

            // Extract and decompress sensor data
            guard let compressedData = record["sensorDataCompressed"] as? Data,
                  let uncompressedSize = record["sensorDataUncompressedSize"] as? Int else {
                await MainActor.run { self.isLoading = false }
                return nil
            }

            guard let decompressedData = compressedData.decompressed(expectedSize: uncompressedSize) else {
                Logger.shared.error("[ProfessionalDataManager] Failed to decompress sensor data")
                await MainActor.run { self.isLoading = false }
                return nil
            }

            let sessionData = try JSONDecoder().decode(BruxismSessionData.self, from: decompressedData)

            await MainActor.run { self.isLoading = false }
            return sessionData

        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Failed to load sensor data: \(error.localizedDescription)"
            }
            throw error
        }
    }

    /// Fetch all sensor data for a patient within a date range (for historical charts)
    func fetchAllPatientSensorData(for patient: ProfessionalPatient, from startDate: Date, to endDate: Date) async throws -> [SerializableSensorData] {
        isLoading = true
        errorMessage = nil

        // CloudKit verification logging
        Logger.shared.info("[ProfessionalDataManager] 📥 Fetching sensor data from CloudKit")
        Logger.shared.info("[ProfessionalDataManager] 📥 Patient ID: \(patient.patientID)")
        Logger.shared.info("[ProfessionalDataManager] 📥 Date range: \(startDate) to \(endDate)")
        Logger.shared.info("[ProfessionalDataManager] 📥 Database scope: \(publicDatabase.databaseScope == .public ? "PUBLIC" : "PRIVATE")")
        Logger.shared.info("[ProfessionalDataManager] 📥 Container: \(container.containerIdentifier ?? "unknown")")

        var allSensorData: [SerializableSensorData] = []

        do {
            let predicate = NSPredicate(
                format: "patientID == %@ AND recordingDate >= %@ AND recordingDate <= %@",
                patient.patientID,
                startDate as NSDate,
                endDate as NSDate
            )
            let query = CKQuery(recordType: "HealthDataRecord", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "recordingDate", ascending: true)]

            Logger.shared.info("[ProfessionalDataManager] 📥 Querying HealthDataRecord...")
            let (matchResults, _) = try await publicDatabase.records(matching: query)
            Logger.shared.info("[ProfessionalDataManager] 📥 Found \(matchResults.count) HealthDataRecord records")

            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    // Extract and decompress sensor data
                    if let compressedData = record["sensorDataCompressed"] as? Data,
                       let uncompressedSize = record["sensorDataUncompressedSize"] as? Int,
                       let decompressedData = compressedData.decompressed(expectedSize: uncompressedSize) {

                        if let sessionData = try? JSONDecoder().decode(BruxismSessionData.self, from: decompressedData) {
                            allSensorData.append(contentsOf: sessionData.sensorReadings)
                        }
                    }
                case .failure(let error):
                    Logger.shared.error("[ProfessionalDataManager] Error loading record: \(error)")
                }
            }

            await MainActor.run { self.isLoading = false }

            // Sort by timestamp
            return allSensorData.sorted { $0.timestamp < $1.timestamp }

        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Failed to load sensor data: \(error.localizedDescription)"
            }
            throw error
        }
    }

    // MARK: - CSV Import

    /// Import a participant from CSV data (local storage, not CloudKit)
    func importParticipantFromCSV(name: String, data: [ImportedSensorData]) async throws {
        isLoading = true
        errorMessage = nil

        // Generate unique IDs for local import
        let participantID = UUID().uuidString
        let recordID = "local_\(participantID)"

        // Create participant record
        let participant = ProfessionalPatient(
            id: recordID,
            patientID: participantID,
            patientName: name,
            shareCode: "CSV",  // Marker for CSV imports
            accessGrantedDate: Date(),
            lastDataUpdate: data.last?.timestamp,
            recordID: recordID,
            isLocalImport: true,
            dataPointCount: data.count
        )

        // Save participant to local storage
        saveLocalParticipant(participant)

        // Save imported sensor data to local storage
        saveImportedSensorData(data, forParticipantID: participantID)

        await MainActor.run {
            // Add to patients list
            self.patients.append(participant)
            self.patients.sort { $0.accessGrantedDate > $1.accessGrantedDate }
            self.isLoading = false
            self.successMessage = "Imported \(data.count) data points for \(name)"
        }

        Logger.shared.info("[ProfessionalDataManager] ✅ CSV import complete: \(name) with \(data.count) data points")
    }

    /// Fetch sensor data for a locally imported participant
    func fetchImportedSensorData(for patient: ProfessionalPatient) -> [SerializableSensorData] {
        guard patient.isLocalImport else { return [] }

        let key = "importedData_\(patient.patientID)"
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }

        do {
            let importedData = try JSONDecoder().decode([ImportedSensorDataCodable].self, from: data)
            return importedData.map { $0.toSerializableSensorData() }
        } catch {
            Logger.shared.error("[ProfessionalDataManager] Failed to decode imported data: \(error)")
            return []
        }
    }

    // MARK: - Local Storage

    private let localParticipantsKey = "localImportedParticipants"

    /// Save a locally imported participant to UserDefaults
    private func saveLocalParticipant(_ participant: ProfessionalPatient) {
        var localParticipants = loadLocalParticipants()
        localParticipants.removeAll { $0.id == participant.id }
        localParticipants.append(participant)

        if let data = try? JSONEncoder().encode(localParticipants) {
            UserDefaults.standard.set(data, forKey: localParticipantsKey)
        }
    }

    /// Load locally imported participants from UserDefaults
    private func loadLocalParticipants() -> [ProfessionalPatient] {
        guard let data = UserDefaults.standard.data(forKey: localParticipantsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([ProfessionalPatient].self, from: data)
        } catch {
            Logger.shared.error("[ProfessionalDataManager] Failed to decode local participants: \(error)")
            return []
        }
    }

    /// Save imported sensor data to UserDefaults
    private func saveImportedSensorData(_ data: [ImportedSensorData], forParticipantID participantID: String) {
        let codableData = data.map { ImportedSensorDataCodable(from: $0) }
        let key = "importedData_\(participantID)"

        if let encoded = try? JSONEncoder().encode(codableData) {
            UserDefaults.standard.set(encoded, forKey: key)
            Logger.shared.info("[ProfessionalDataManager] Saved \(data.count) data points for participant \(participantID)")
        }
    }

    /// Remove locally imported participant
    func removeLocalParticipant(_ patient: ProfessionalPatient) {
        // Remove from local storage
        var localParticipants = loadLocalParticipants()
        localParticipants.removeAll { $0.id == patient.id }

        if let data = try? JSONEncoder().encode(localParticipants) {
            UserDefaults.standard.set(data, forKey: localParticipantsKey)
        }

        // Remove sensor data
        let dataKey = "importedData_\(patient.patientID)"
        UserDefaults.standard.removeObject(forKey: dataKey)

        // Remove from patients list
        patients.removeAll { $0.id == patient.id }

        Logger.shared.info("[ProfessionalDataManager] Removed local participant: \(patient.displayName)")
    }

    // MARK: - Helper Methods

    private func getCurrentProfessionalID() -> String? {
        // This would get the professional's Apple ID from Sign in with Apple
        // For now, return a placeholder - will be implemented with actual auth
        return UserDefaults.standard.string(forKey: "professionalAppleID")
    }

    private func getCurrentProfessionalName() -> String? {
        // Get professional's name from authentication
        return UserDefaults.standard.string(forKey: "professionalName")
    }

    // MARK: - Account Deletion (Apple App Store Requirement)

    /// Deletes all professional's data from CloudKit
    /// This is required by Apple for apps that support account creation
    func deleteAllUserData() async throws {
        guard let professionalID = professionalID else {
            Logger.shared.warning("[ProfessionalDataManager] Cannot delete data - not authenticated")
            return
        }

        Logger.shared.info("[ProfessionalDataManager] 🗑️ Starting CloudKit data deletion for professional: \(professionalID)")
        isLoading = true
        errorMessage = nil

        do {
            // Delete SharedPatientData records (professional's patient connections)
            try await deleteRecords(ofType: "SharedPatientData", forProfessionalID: professionalID)

            // Clear local state
            patients = []

            isLoading = false
            Logger.shared.info("[ProfessionalDataManager] 🗑️ Successfully deleted all CloudKit data for professional")
        } catch {
            isLoading = false
            errorMessage = "Failed to delete cloud data: \(error.localizedDescription)"
            Logger.shared.error("[ProfessionalDataManager] ❌ Failed to delete CloudKit data: \(error)")
            throw ProfessionalDataError.cloudKitError(error)
        }
    }

    private func deleteRecords(ofType recordType: String, forProfessionalID professionalID: String) async throws {
        // Note: CloudKit field name is "dentistID" for backwards compatibility
        let predicate = NSPredicate(format: "dentistID == %@", professionalID)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        do {
            let (matchResults, _) = try await publicDatabase.records(matching: query)

            var recordIDsToDelete: [CKRecord.ID] = []
            for (recordID, result) in matchResults {
                switch result {
                case .success:
                    recordIDsToDelete.append(recordID)
                case .failure(let error):
                    Logger.shared.warning("[ProfessionalDataManager] Error fetching \(recordType) record: \(error)")
                }
            }

            if !recordIDsToDelete.isEmpty {
                Logger.shared.info("[ProfessionalDataManager] Deleting \(recordIDsToDelete.count) \(recordType) records")

                // Delete records
                for recordID in recordIDsToDelete {
                    try await publicDatabase.deleteRecord(withID: recordID)
                }

                Logger.shared.info("[ProfessionalDataManager] ✅ Deleted \(recordIDsToDelete.count) \(recordType) records")
            } else {
                Logger.shared.info("[ProfessionalDataManager] No \(recordType) records found to delete")
            }
        } catch {
            // Handle "record type not found" error gracefully
            let nsError = error as NSError
            if nsError.domain == CKErrorDomain && nsError.code == CKError.unknownItem.rawValue {
                Logger.shared.info("[ProfessionalDataManager] Record type \(recordType) doesn't exist - nothing to delete")
            } else {
                throw error
            }
        }
    }
}

// MARK: - Codable Helper for ImportedSensorData

/// Codable wrapper for ImportedSensorData (for UserDefaults storage)
struct ImportedSensorDataCodable: Codable {
    let timestamp: Date
    let deviceType: String
    let emg: Double?
    let ppgIR: Double?
    let ppgRed: Double?
    let ppgGreen: Double?
    let accelX: Double?
    let accelY: Double?
    let accelZ: Double?
    let temperature: Double?
    let battery: Double?
    let heartRate: Double?

    init(from imported: ImportedSensorData) {
        self.timestamp = imported.timestamp
        self.deviceType = imported.deviceType
        self.emg = imported.emg
        self.ppgIR = imported.ppgIR
        self.ppgRed = imported.ppgRed
        self.ppgGreen = imported.ppgGreen
        self.accelX = imported.accelX
        self.accelY = imported.accelY
        self.accelZ = imported.accelZ
        self.temperature = imported.temperature
        self.battery = imported.battery
        self.heartRate = imported.heartRate
    }

    /// Convert to SerializableSensorData for chart display
    func toSerializableSensorData() -> SerializableSensorData {
        // Pre-calculate values to help compiler type-check
        let aX: Double = accelX ?? 0
        let aY: Double = accelY ?? 0
        let aZ: Double = accelZ ?? 0
        let magnitude: Double = sqrt(aX * aX + aY * aY + aZ * aZ)
        let hrQuality: Double? = heartRate != nil ? 1.0 : nil

        return SerializableSensorData(
            timestamp: timestamp,
            deviceType: deviceType,
            ppgRed: Int32(ppgRed ?? 0),
            ppgIR: Int32(ppgIR ?? 0),
            ppgGreen: Int32(ppgGreen ?? 0),
            emg: emg,
            accelX: Int16(aX),
            accelY: Int16(aY),
            accelZ: Int16(aZ),
            accelMagnitude: magnitude,
            temperatureCelsius: temperature ?? 0,
            batteryPercentage: Int(battery ?? 0),
            heartRateBPM: heartRate,
            heartRateQuality: hrQuality,
            spo2Percentage: nil,
            spo2Quality: nil
        )
    }
}

// MARK: - Errors

enum ProfessionalDataError: LocalizedError {
    case notAuthenticated
    case invalidShareCode
    case shareCodeNotFound
    case shareCodeExpired
    case patientAlreadyAdded
    case patientLimitReached
    case cloudKitError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to add participants"
        case .invalidShareCode:
            return "Invalid share code format. Please enter a 6-digit code."
        case .shareCodeNotFound:
            return "Share code not found or has been deactivated"
        case .shareCodeExpired:
            return "This share code has expired. Please request a new code from the participant."
        case .patientAlreadyAdded:
            return "You already have access to this participant's data"
        case .patientLimitReached:
            return "You've reached your participant limit. Please upgrade to add more participants."
        case .cloudKitError(let error):
            return "Cloud error: \(error.localizedDescription)"
        }
    }
}
