//
//  ShareViewModel.swift
//  OralableApp
//
//  ViewModel for data export and sharing functionality.
//
//  Responsibilities:
//  - Manages export configuration (format, date range)
//  - Triggers CSV/JSON export via CSVExportManager
//  - Handles share sheet presentation
//  - Tracks export progress
//
//  Export Formats:
//  - CSV: Primary format for data analysis
//  - JSON: Alternative structured format
//  - PDF: Future feature (when enabled)
//
//  Export Options:
//  - Quick export presets (today, this week, all)
//  - Custom date range selection
//  - Data type inclusion toggles
//
//  Created by John A Cogan on 04/11/2025.
//

import Foundation
import SwiftUI
import Combine

/// View model for the Share screen using modern architecture
@MainActor
class ShareViewModel: ObservableObject {
    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case pdf = "PDF"
        case json = "JSON"

        /// Returns only export formats enabled via feature flags
        static var availableCases: [ExportFormat] {
            var cases: [ExportFormat] = [.csv, .json]
            if FeatureFlags.shared.showPDFExport {
                cases.append(.pdf)
            }
            return cases
        }
    }
    
    // MARK: - Published Properties
    
    @Published var connectionStatus: String = "Disconnected"
    @Published var isConnected: Bool = false
    @Published var dataSummary: DataSummary?
    @Published var recentLogs: [LogEntry] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    
    // Export/Import states
    @Published var isExporting: Bool = false
    @Published var isImporting: Bool = false
    @Published var exportProgress: Double = 0.0
    @Published var importResult: CSVImportResult?
    @Published var showImportResults: Bool = false
    
    // Export configuration
    @Published var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @Published var endDate: Date = Date()
    @Published var selectedFormat: ExportFormat = .csv
    @Published var quickExportOption: QuickExportOption = .thisWeek
    
    // Data type selections
    @Published var includeHeartRate: Bool = true
    @Published var includeSpO2: Bool = true
    @Published var includeTemperature: Bool = true
    @Published var includeAccelerometer: Bool = true
    @Published var includeNotes: Bool = true
    
    // Export results
    @Published var exportedFileURL: URL?
    @Published var showExportSuccess: Bool = false
    @Published var showError: Bool = false
    
    // Data counts
    @Published var heartRateDataCount: Int = 0
    @Published var spo2DataCount: Int = 0
    @Published var temperatureDataCount: Int = 0
    @Published var accelerometerDataCount: Int = 0
    @Published var notesCount: Int = 0
    
    enum QuickExportOption {
        case today
        case thisWeek
        case thisMonth
        case custom
    }
    
    // MARK: - Dependencies
    
    private let deviceManager: DeviceManager
    private let repository: SensorRepository
    private let csvService: CSVService
    private let loggingService: LoggingService
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(
        deviceManager: DeviceManager,
        repository: SensorRepository,
        csvService: CSVService = CSVService(),
        loggingService: LoggingService = AppLoggingService()
    ) {
        self.deviceManager = deviceManager
        self.repository = repository
        self.csvService = csvService
        self.loggingService = loggingService
        
        setupSubscriptions()
        loadInitialData()
    }
    
    // MARK: - Setup
    
    private func setupSubscriptions() {
        // Subscribe to device connection state via connectedDevices
        deviceManager.$connectedDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self else { return }
                let connected = !devices.isEmpty
                self.isConnected = connected
                if connected {
                    if let primary = self.deviceManager.primaryDevice {
                        self.connectionStatus = "Connected to \(primary.name)"
                    } else if let first = devices.first {
                        self.connectionStatus = "Connected to \(first.name)"
                    } else {
                        self.connectionStatus = "Connected"
                    }
                } else {
                    self.connectionStatus = "Disconnected"
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to log updates
        loggingService.logPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRecentLogs()
            }
            .store(in: &cancellables)
        
        // Refresh data summary periodically
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.refreshDataSummary() }
            }
            .store(in: &cancellables)
    }
    
    private func loadInitialData() {
        Task {
            await refreshDataSummary()
            await MainActor.run {
                updateRecentLogs()
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Refresh the data summary
    func refreshDataSummary() async {
        do {
            let summary = try await repository.dataSummary()
            await MainActor.run {
                self.dataSummary = summary
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load data summary: \(error.localizedDescription)"
                self.loggingService.error("Failed to load data summary", source: "ShareViewModel")
            }
        }
    }
    
    /// Update recent logs
    func updateRecentLogs() {
        let logs = Array(loggingService.recentLogs.suffix(20)).reversed()
        recentLogs = Array(logs)
    }
    
    /// Export data to CSV
    func exportData() async {
        await MainActor.run {
            isExporting = true
            exportProgress = 0.0
            errorMessage = nil
            successMessage = nil
        }
        
        do {
            loggingService.info("Starting CSV export", source: "ShareViewModel")
            
            // Get date range (last 7 days or all data)
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
            
            await MainActor.run {
                exportProgress = 0.3
            }
            
            // Export readings and logs
            let logs = loggingService.logs(from: startDate, to: endDate)
            let fileURL = try await csvService.exportReadings(
                from: startDate,
                to: endDate,
                repository: repository,
                logs: logs
            )
            
            await MainActor.run {
                exportProgress = 1.0
                successMessage = "Data exported successfully"
                loggingService.info("CSV export completed: \(fileURL.lastPathComponent)", source: "ShareViewModel")
            }
            
            // Share the file
            await MainActor.run {
                shareFile(fileURL)
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Export failed: \(error.localizedDescription)"
                loggingService.error("CSV export failed: \(error)", source: "ShareViewModel")
            }
        }
        
        await MainActor.run {
            isExporting = false
            exportProgress = 0.0
        }
    }
    
    /// Import data from CSV file
    func importData(from url: URL) async {
        await MainActor.run {
            isImporting = true
            errorMessage = nil
            successMessage = nil
            importResult = nil
        }
        
        do {
            loggingService.info("Starting CSV import from: \(url.lastPathComponent)", source: "ShareViewModel")
            
            // Import readings
            let result = try await csvService.importReadings(from: url)
            
            if result.isSuccessful {
                // Save imported readings to repository
                try await repository.save(result.readings)
                
                await MainActor.run {
                    importResult = result
                    successMessage = result.summaryText
                    showImportResults = true
                    loggingService.info("CSV import completed: \(result.readings.count) readings", source: "ShareViewModel")
                }
                
                // Refresh data summary after import
                await refreshDataSummary()
            } else {
                await MainActor.run {
                    errorMessage = "Import failed: No valid readings found"
                    loggingService.warning("CSV import failed: No valid readings", source: "ShareViewModel")
                }
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Import failed: \(error.localizedDescription)"
                loggingService.error("CSV import failed: \(error)", source: "ShareViewModel")
            }
        }
        
        await MainActor.run {
            isImporting = false
        }
    }
    
    /// Clear all sensor data
    func clearAllData() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            successMessage = nil
        }
        
        do {
            loggingService.warning("Clearing all sensor data", source: "ShareViewModel")
            
            try await repository.clearAllData()
            
            await MainActor.run {
                successMessage = "All data cleared successfully"
                dataSummary = nil
                loggingService.info("All sensor data cleared", source: "ShareViewModel")
            }
            
            // Refresh data summary
            await refreshDataSummary()
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to clear data: \(error.localizedDescription)"
                loggingService.error("Failed to clear data: \(error)", source: "ShareViewModel")
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    /// Clear logs
    func clearLogs() {
        loggingService.clearLogs()
        updateRecentLogs()
        successMessage = "Logs cleared successfully"
    }
    
    /// Export logs only
    func exportLogs() async {
        do {
            let fileURL = try await loggingService.exportLogs()
            await MainActor.run {
                successMessage = "Logs exported successfully"
                shareFile(fileURL)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to export logs: \(error.localizedDescription)"
            }
        }
    }
    
    /// Dismiss messages
    func dismissMessages() {
        errorMessage = nil
        successMessage = nil
    }
    
    /// Dismiss import results
    func dismissImportResults() {
        showImportResults = false
        importResult = nil
    }
    
    // MARK: - Private Methods
    
    private func shareFile(_ url: URL) {
        #if canImport(UIKit)
        // iOS implementation would go here
        // For now, just log the file location
        loggingService.info("File ready for sharing: \(url.path)", source: "ShareViewModel")
        #elseif canImport(AppKit)
        // macOS implementation
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        #endif
    }
    
    // MARK: - Export Configuration Methods
    
    func selectQuickExport(_ option: QuickExportOption) {
        quickExportOption = option
        let calendar = Calendar.current
        let now = Date()
        
        switch option {
        case .today:
            startDate = calendar.startOfDay(for: now)
            endDate = now
        case .thisWeek:
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
            startDate = weekStart ?? calendar.date(byAdding: .day, value: -7, to: now) ?? now
            endDate = now
        case .thisMonth:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
            startDate = monthStart ?? calendar.date(byAdding: .month, value: -1, to: now) ?? now
            endDate = now
        case .custom:
            // User will set dates manually
            break
        }
        
        // Update data counts
        Task {
            await updateDataCounts()
        }
    }
    
    func selectAllDataTypes() {
        includeHeartRate = true
        includeSpO2 = true
        includeTemperature = true
        includeAccelerometer = true
        includeNotes = true
    }
    
    func deselectAllDataTypes() {
        includeHeartRate = false
        includeSpO2 = false
        includeTemperature = false
        includeAccelerometer = false
        includeNotes = false
    }
    
    func dismissError() {
        showError = false
        errorMessage = nil
    }
    
    private func updateDataCounts() async {
        do {
            // In a real implementation, query the repository for counts
            // For now, using mock data
            await MainActor.run {
                heartRateDataCount = 150
                spo2DataCount = 120
                temperatureDataCount = 100
                accelerometerDataCount = 500
                notesCount = 5
            }
        }
    }
    
    var dateRangeDays: Int {
        let components = Calendar.current.dateComponents([.day], from: startDate, to: endDate)
        return max(1, components.day ?? 1)
    }
    
    var hasDataToExport: Bool {
        includeHeartRate || includeSpO2 || includeTemperature || includeAccelerometer || includeNotes
    }
    
    var exportFileName: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        return "Oralable_Export_\(dateString).\(selectedFormat.fileExtension)"
    }
    
    var estimatedFileSize: String {
        let totalPoints = heartRateDataCount + spo2DataCount + temperatureDataCount + accelerometerDataCount
        let estimatedBytes = totalPoints * 50 // Rough estimate
        return ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file)
    }
    
    var totalDataPointsText: String {
        let total = (includeHeartRate ? heartRateDataCount : 0) +
                    (includeSpO2 ? spo2DataCount : 0) +
                    (includeTemperature ? temperatureDataCount : 0) +
                    (includeAccelerometer ? accelerometerDataCount : 0) +
                    (includeNotes ? notesCount : 0)
        return "\(total) data points"
    }
}

// MARK: - Export Format Extension

extension ShareViewModel.ExportFormat {
    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        case .pdf: return "pdf"
        }
    }
    
    var icon: String {
        switch self {
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        case .pdf: return "doc.text"
        }
    }
    
    var color: Color {
        switch self {
        case .csv: return .green
        case .json: return .blue
        case .pdf: return .red
        }
    }
    
    var displayName: String {
        switch self {
        case .csv: return "CSV"
        case .json: return "JSON"
        case .pdf: return "PDF Report"
        }
    }
    
    var description: String {
        switch self {
        case .csv: return "Spreadsheet format, compatible with Excel"
        case .json: return "Structured data format for developers"
        case .pdf: return "Visual report with charts and summaries"
        }
    }
}

// MARK: - Computed Properties

extension ShareViewModel {
    
    /// Summary text for current data
    var dataSummaryText: String {
        guard let summary = dataSummary else {
            return "No data available"
        }
        
        if summary.totalReadings == 0 {
            return "No data available"
        }
        
        let readingsText = "\(summary.totalReadings) reading\(summary.totalReadings == 1 ? "" : "s")"
        let devicesText = "\(summary.connectedDevices.count) device\(summary.connectedDevices.count == 1 ? "" : "s")"
        let qualityText = summary.qualityMetrics.qualityRating.displayName.lowercased()
        
        return "\(readingsText) from \(devicesText) (\(qualityText) quality)"
    }
    
    /// Storage size text
    var storageSizeText: String {
        // This would be computed from repository.storageSize() in a real implementation
        "~2.3 MB"
    }
    
    /// Most recent log message
    var latestLogMessage: String? {
        recentLogs.first?.message
    }
    
    /// Connection status color
    var connectionStatusColor: String {
        isConnected ? "systemGreen" : "systemRed"
    }
}

// MARK: - Preview Mock

#if DEBUG
extension ShareViewModel {
    static func mock() -> ShareViewModel {
        let mockDeviceManager = MockDeviceManager()
        let mockRepository = InMemorySensorRepository()
        let mockLoggingService = MockLoggingService()
        
        let viewModel = ShareViewModel(
            deviceManager: mockDeviceManager,
            repository: mockRepository,
            csvService: CSVService(),
            loggingService: mockLoggingService
        )
        
        // Setup mock data
        Task {
            // Add some mock readings
            let mockReadings = [
                SensorReading.mock(sensorType: .heartRate),
                SensorReading.mock(sensorType: .spo2),
                SensorReading.mock(sensorType: .temperature),
                SensorReading.mock(sensorType: .battery)
            ]
            
            try? await mockRepository.save(mockReadings)
            await viewModel.refreshDataSummary()
        }
        
        return viewModel
    }
}

/// Mock device manager for preview purposes
class MockDeviceManager: DeviceManager {
    
    override init() {
        super.init()
        
        // Set up a connected mock device state without real BLE
        let mock = DeviceInfo.demo()
        self.connectedDevices = [mock]
        self.primaryDevice = mock
        self.discoveredDevices = [mock]
    }
}
#endif
