//
//  PatientHistoricalViewModel.swift
//  OralableForProfessionals
//
//  ViewModel for patient historical charts - simplified to match patient app
//  Updated: December 9, 2025 - Removed time range selectors, loads all available data
//  Updated: December 9, 2025 - Added device type filtering to match patient app data processing
//

import Foundation
import Combine
import OralableCore

@MainActor
class PatientHistoricalViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var dataPoints: [HistoricalDataPoint] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedMetricType: String = "IR Activity"

    // MARK: - Private Properties

    private let patient: ProfessionalPatient
    private let dataManager: ProfessionalDataManager

    /// All sensor data loaded from source (CloudKit or local CSV)
    /// Made internal for tab availability checking in the view
    private(set) var allSensorData: [SerializableSensorData] = []

    // MARK: - Constants

    /// LIS2DTW12 accelerometer conversion factor (±2g range, 14-bit resolution)
    /// 1g = 16384 LSB
    private let accelLSBPerG: Double = 16384.0

    // MARK: - Initialization

    init(patient: ProfessionalPatient, dataManager: ProfessionalDataManager = .shared) {
        self.patient = patient
        self.dataManager = dataManager
    }

    // MARK: - Computed Properties

    /// Date range of the loaded data
    var dataDateRange: String? {
        guard let first = dataPoints.first?.timestamp,
              let last = dataPoints.last?.timestamp else {
            return nil
        }

        let formatter = DateFormatter()

        // Check if same day
        if Calendar.current.isDate(first, inSameDayAs: last) {
            formatter.dateFormat = "MMM d, yyyy"
            let dateStr = formatter.string(from: first)

            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            let startTime = timeFormatter.string(from: first)
            let endTime = timeFormatter.string(from: last)

            return "\(dateStr) \(startTime) - \(endTime)"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
        }
    }

    // MARK: - Data Loading

    /// Load all available data for the patient (no time filtering)
    func loadAllData() async {
        isLoading = true
        errorMessage = nil

        Logger.shared.info("[PatientHistoricalViewModel] Loading data for patient: \(patient.patientID)")
        Logger.shared.info("[PatientHistoricalViewModel] isLocalImport: \(patient.isLocalImport), connectionType: \(patient.connectionType)")

        // Load all data from the past month (sufficient for max 10-hour sessions)
        // This ensures professionals can always see the most recent patient data
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .month, value: -1, to: endDate) ?? endDate

        do {
            // Check if this is a local CSV import vs CloudKit sync
            if patient.isLocalImport {
                // Load from local storage
                allSensorData = dataManager.fetchImportedSensorData(for: patient)
                Logger.shared.info("[PatientHistoricalViewModel] Loaded \(allSensorData.count) data points from local storage (CSV import)")
            } else {
                // Load from CloudKit
                allSensorData = try await dataManager.fetchAllPatientSensorData(
                    for: patient,
                    from: startDate,
                    to: endDate
                )
                Logger.shared.info("[PatientHistoricalViewModel] Fetched \(allSensorData.count) data points from CloudKit")
            }

            // Log date range of data
            if let first = allSensorData.first {
                Logger.shared.info("[PatientHistoricalViewModel] First record date: \(first.timestamp)")
            }
            if let last = allSensorData.last {
                Logger.shared.info("[PatientHistoricalViewModel] Last record date: \(last.timestamp)")
            }

            // Process data based on current metric type
            updateDataPointsForMetricType()

        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
            Logger.shared.error("[PatientHistoricalViewModel] Failed to load data: \(error)")
        }

        isLoading = false
    }

    /// Update data points when metric type changes
    func updateMetricType(_ metricType: String) {
        selectedMetricType = metricType
        updateDataPointsForMetricType()
    }

    // MARK: - Private Methods

    /// Filter and process sensor data based on the selected metric type
    /// This mirrors the patient app's SessionDataLoader behavior
    private func updateDataPointsForMetricType() {
        // Filter data based on metric type (matches patient app logic)
        let filteredData: [SerializableSensorData]

        switch selectedMetricType {
        case "EMG Activity":
            // EMG only comes from ANR M40 device
            filteredData = allSensorData.filter { $0.isANRDevice }
            Logger.shared.info("[PatientHistoricalViewModel] EMG: \(filteredData.count) ANR M40 data points")

        case "IR Activity":
            // IR (PPG) only comes from Oralable device
            filteredData = allSensorData.filter { $0.isOralableDevice }
            Logger.shared.info("[PatientHistoricalViewModel] IR: \(filteredData.count) Oralable data points")

        case "Movement":
            // Both devices have accelerometer data, but typically use Oralable
            filteredData = allSensorData.filter { $0.isOralableDevice }
            Logger.shared.info("[PatientHistoricalViewModel] Movement: \(filteredData.count) data points")

        case "Temperature":
            // Only Oralable has temperature sensor
            filteredData = allSensorData.filter { $0.isOralableDevice && $0.temperatureCelsius > 0 }
            Logger.shared.info("[PatientHistoricalViewModel] Temperature: \(filteredData.count) data points")

        default:
            filteredData = allSensorData
        }

        // Convert to historical data points
        dataPoints = filteredData.map { sensorData in
            createHistoricalDataPoint(from: sensorData)
        }

        Logger.shared.info("[PatientHistoricalViewModel] Created \(dataPoints.count) data points for \(selectedMetricType)")
    }

    /// Create a HistoricalDataPoint from sensor data
    /// Mirrors the patient app's SessionDataLoader.createDataPointFromExport logic
    private func createHistoricalDataPoint(from sensorData: SerializableSensorData) -> HistoricalDataPoint {
        // Calculate movement intensity in g units (same as patient app)
        // accelMagnitude is raw value, needs conversion: raw / 16384 = g
        let movementInG = sensorData.accelMagnitude / accelLSBPerG

        // Determine primary value based on device type and metric
        let primaryValue: Double?
        switch selectedMetricType {
        case "EMG Activity":
            // Use EMG value (from dedicated field or inferred from legacy data)
            primaryValue = sensorData.emgValue
        case "IR Activity":
            // Use PPG IR value (only valid for Oralable)
            primaryValue = sensorData.ppgIRValue
        default:
            // Default to PPG IR if available, otherwise EMG
            primaryValue = sensorData.ppgIRValue ?? sensorData.emgValue
        }

        return HistoricalDataPoint(
            timestamp: sensorData.timestamp,
            movementIntensity: movementInG,
            averageHeartRate: sensorData.heartRateBPM,
            averageSpO2: sensorData.spo2Percentage,
            averagePPGIR: primaryValue,
            averagePPGRed: sensorData.isOralableDevice ? Double(sensorData.ppgRed) : nil,
            averagePPGGreen: sensorData.isOralableDevice ? Double(sensorData.ppgGreen) : nil,
            averageTemperature: sensorData.temperatureCelsius > 0 ? sensorData.temperatureCelsius : nil,
            sampleCount: 1
        )
    }
}
