//
//  ShareView.swift
//  OralableApp
//
//  Data export and sharing screen.
//
//  Features:
//  - Export sensor data to CSV format
//  - Export events to CSV format (event-based recording)
//  - Share via iOS share sheet (AirDrop, Files, etc.)
//  - Export file history display
//  - Data summary (record count, date range)
//
//  Export Options:
//  - Columns based on enabled dashboard cards
//  - Timestamp, PPG, Accelerometer, Temperature, HR, SpO2
//  - Filename includes user ID and timestamp
//
//  Future: Professional sharing via CloudKit (when enabled)
//
//  Updated: December 13, 2025 - Changed Export to Share terminology
//  Updated: January 12, 2026 - Added event-based export option
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers
import OralableCore

/// Export type for sharing data
enum ExportType: String, CaseIterable {
    case events = "Events Only"
    case continuous = "All Samples"

    var description: String {
        switch self {
        case .events:
            return "Export detected events (smaller file)"
        case .continuous:
            return "Export all sensor samples (larger file)"
        }
    }
}

struct ShareView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var sharedDataManager: SharedDataManager
    @EnvironmentObject var dependencies: AppDependencies
    @ObservedObject var sensorDataProcessor: SensorDataProcessor
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject private var featureFlags = FeatureFlags.shared
    @ObservedObject private var eventSettings = EventSettings.shared

    @State private var shareCode: String = ""
    @State private var isGeneratingCode = false
    @State private var showCopiedFeedback = false
    @State private var showingShareSheet = false
    @State private var shareURL: URL? = nil
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSharing = false
    @State private var shareProgress: String = ""
    @State private var exportType: ExportType = .events

    var body: some View {
        NavigationView {
            List {
                // Share CSV section - ALWAYS SHOWN
                shareCSVSection

                // Share with Professional section - CONDITIONAL (CloudKit sharing)
                if featureFlags.showCloudKitShare {
                    shareCodeSection
                    sharedWithSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingShareSheet) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .navigationViewStyle(.stack)
        .task {
            // Only generate share code if CloudKit sharing is enabled
            if featureFlags.showCloudKitShare {
                if shareCode.isEmpty {
                    await generateAndSaveShareCode()
                }
                // Refresh shared professionals list
                sharedDataManager.loadSharedProfessionals()

                // Sync current sensor data to CloudKit for professional access
                await sharedDataManager.uploadCurrentDataForSharing()
            }
        }
    }

    // MARK: - Share CSV Section
    private var shareCSVSection: some View {
        Section {
            // Export type picker
            Picker("Export Type", selection: $exportType) {
                ForEach(ExportType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

            Button(action: shareCSV) {
                HStack {
                    if isSharing {
                        ProgressView()
                            .frame(width: 20, height: 20)
                            .frame(width: 32)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                            .frame(width: 32)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isSharing ? "Sharing..." : "Share Data as CSV")
                            .font(.system(size: 17))
                            .foregroundColor(.primary)

                        if isSharing && !shareProgress.isEmpty {
                            Text(shareProgress)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if !isSharing {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isSharing)
        } header: {
            Text("Share")
        } footer: {
            exportFooterText
        }
    }

    private var exportFooterText: Text {
        switch exportType {
        case .events:
            let dashboardVM = dependencies.makeDashboardViewModel()
            let eventCount = dashboardVM.currentEventSession?.eventCount ?? 0
            return Text("Export \(eventCount) detected events (fast, small file)")
        case .continuous:
            let recordCount = sensorDataProcessor.sensorDataHistory.count
            return Text("Export \(recordCount) sensor samples (may take longer)")
        }
    }

    // MARK: - Share Code Section
    private var shareCodeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Share Code")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)

                HStack {
                    if isGeneratingCode {
                        ProgressView()
                            .frame(height: 38)
                    } else {
                        Text(shareCode.isEmpty ? "------" : shareCode)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Button(action: copyShareCode) {
                        Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 20))
                            .foregroundColor(showCopiedFeedback ? .green : .blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(shareCode.isEmpty)
                }

                Text("Give this code to your healthcare professional to share your data")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                // Regenerate button
                Button(action: {
                    Task { await generateAndSaveShareCode() }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Generate New Code")
                    }
                    .font(.system(size: 15))
                    .foregroundColor(.blue)
                }
                .disabled(isGeneratingCode)
            }
            .padding(.vertical, 8)
        } header: {
            Text("Share with Professional")
        } footer: {
            Text("Code expires in 48 hours")
        }
    }

    // MARK: - Shared With Section
    private var sharedWithSection: some View {
        Section {
            if sharedDataManager.sharedProfessionals.isEmpty {
                Text("No one has access to your data")
                    .foregroundColor(.secondary)
            } else {
                ForEach(sharedDataManager.sharedProfessionals) { professional in
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(professional.professionalName ?? professional.professionalID)
                                .font(.system(size: 17))
                                .foregroundColor(.primary)

                            Text("Has access")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Remove") {
                            removeConnection(professional)
                        }
                        .font(.system(size: 15))
                        .foregroundColor(.red)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Shared With")
        }
    }

    // MARK: - Actions
    
    private func generateAndSaveShareCode() async {
        await MainActor.run { isGeneratingCode = true }
        
        do {
            let code = try await sharedDataManager.createShareInvitation()
            await MainActor.run {
                shareCode = code
                isGeneratingCode = false
            }
            Logger.shared.info("[ShareView] ✅ Share code created and saved to CloudKit: \(code)")
        } catch {
            Logger.shared.error("[ShareView] ❌ Failed to create share invitation: \(error)")
            await MainActor.run {
                isGeneratingCode = false
                errorMessage = "Failed to create share code: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func copyShareCode() {
        UIPasteboard.general.string = shareCode
        showCopiedFeedback = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedFeedback = false
        }
    }

    private func removeConnection(_ professional: SharedProfessional) {
        Task {
            try? await sharedDataManager.revokeAccessForProfessional(professionalID: professional.professionalID)
        }
    }

    // MARK: - Share CSV (Optimized)
    private func shareCSV() {
        Task {
            await MainActor.run {
                isSharing = true
                shareProgress = "Preparing..."
            }

            var url: URL? = nil

            switch exportType {
            case .events:
                // Export cached events (fast, small file)
                url = await generateEventCSVFile()
            case .continuous:
                // Legacy export (all samples)
                url = await generateCSVFileOptimized()
            }

            if let url = url {
                await MainActor.run {
                    isSharing = false
                    shareProgress = ""
                    shareURL = url
                    showingShareSheet = true
                }
            } else {
                await MainActor.run {
                    isSharing = false
                    shareProgress = ""
                }
            }
        }
    }

    /// Generate CSV file from cached events (fast export)
    private func generateEventCSVFile() async -> URL? {
        let dashboardVM = dependencies.makeDashboardViewModel()

        guard let session = dashboardVM.currentEventSession,
              !session.events.isEmpty else {
            await MainActor.run {
                errorMessage = "No events to export. Start a recording to detect events."
                showError = true
            }
            return nil
        }

        let events = session.events
        Logger.shared.info("[ShareView] 📊 Starting event CSV export with \(events.count) events")

        // Build export options based on feature flags
        let options = EventCSVExporter.ExportOptions(
            includeTemperature: featureFlags.showTemperatureCard,
            includeHR: featureFlags.showHeartRateCard,
            includeSpO2: featureFlags.showSpO2Card,
            includeSleep: false
        )

        // Export to file
        if let url = CSVExportManager.shared.exportEvents(events, options: options) {
            Logger.shared.info("[ShareView] ✅ Event CSV export complete: \(url.lastPathComponent)")
            return url
        } else {
            await MainActor.run {
                errorMessage = "Failed to export events"
                showError = true
            }
            return nil
        }
    }

    /// Optimized CSV generation using array join instead of string concatenation
    /// This is O(n) instead of O(n²) for string operations
    /// Only exports columns for metrics that have visible dashboard cards
    private func generateCSVFileOptimized() async -> URL? {
        let sensorData = sensorDataProcessor.sensorDataHistory
        let totalCount = sensorData.count

        guard totalCount > 0 else {
            await MainActor.run {
                errorMessage = "No data to share"
                showError = true
            }
            return nil
        }

        Logger.shared.info("[ShareView] 📊 Starting CSV share with \(totalCount) records")
        let startTime = Date()

        // Get current feature flag settings for conditional columns
        let includeMovement = featureFlags.showMovementCard
        let includeTemperature = featureFlags.showTemperatureCard
        let includeHeartRate = featureFlags.showHeartRateCard
        let includeBattery = featureFlags.showBatteryCard

        // Pre-allocate array capacity for performance
        var lines: [String] = []
        lines.reserveCapacity(totalCount + 1)

        // Build header based on enabled features
        var headerParts = ["Timestamp", "Device_Type", "EMG", "PPG_IR", "PPG_Red", "PPG_Green"]
        if includeMovement {
            headerParts.append(contentsOf: ["Accel_X", "Accel_Y", "Accel_Z"])
        }
        if includeTemperature {
            headerParts.append("Temperature")
        }
        if includeBattery {
            headerParts.append("Battery")
        }
        if includeHeartRate {
            headerParts.append("Heart_Rate")
        }
        lines.append(headerParts.joined(separator: ","))

        let dateFormatter = ISO8601DateFormatter()

        // Process in batches for UI updates
        let batchSize = 1000
        var processedCount = 0

        for data in sensorData {
            let timestamp = dateFormatter.string(from: data.timestamp)

            // Device type determines which columns get data
            let deviceTypeName: String
            let emgValue: Int32
            let ppgIRValue: Int32

            switch data.deviceType {
            case .anr:
                deviceTypeName = "ANR M40"
                emgValue = data.ppg.ir
                ppgIRValue = 0
            case .oralable:
                deviceTypeName = "Oralable"
                emgValue = 0
                ppgIRValue = data.ppg.ir
            case .demo:
                deviceTypeName = "Demo"
                emgValue = 0
                ppgIRValue = data.ppg.ir
            }

            // Build line with only enabled columns
            var rowParts: [String] = [
                timestamp,
                deviceTypeName,
                String(emgValue),
                String(ppgIRValue),
                String(data.ppg.red),
                String(data.ppg.green)
            ]

            if includeMovement {
                rowParts.append(contentsOf: [
                    String(data.accelerometer.x),
                    String(data.accelerometer.y),
                    String(data.accelerometer.z)
                ])
            }
            if includeTemperature {
                rowParts.append(String(data.temperature.celsius))
            }
            if includeBattery {
                rowParts.append(String(data.battery.percentage))
            }
            if includeHeartRate {
                let heartRate = data.heartRate?.bpm ?? 0
                rowParts.append(String(heartRate))
            }

            lines.append(rowParts.joined(separator: ","))

            processedCount += 1

            // Update progress every batch
            if processedCount % batchSize == 0 {
                let progress = Double(processedCount) / Double(totalCount) * 100
                await MainActor.run {
                    shareProgress = "Processing \(processedCount)/\(totalCount) (\(Int(progress))%)"
                }
                // Yield to allow UI updates
                await Task.yield()
            }
        }

        await MainActor.run {
            shareProgress = "Writing file..."
        }

        // Join all lines at once (O(n) operation)
        let csvString = lines.joined(separator: "\n")

        // Get user identifier (first 8 chars of Apple ID for brevity)
        // User ID is persisted in UserDefaults by AuthenticationManager
        let userIdentifier: String
        if let userID = UserDefaults.standard.string(forKey: "userID"), !userID.isEmpty {
            // Use first 8 characters of the Apple ID user identifier
            userIdentifier = String(userID.prefix(8))
        } else {
            // Fallback for guest users or unauthenticated state
            userIdentifier = "guest"
        }

        let fileName = "oralable_data_\(userIdentifier)_\(Int(Date().timeIntervalSince1970)).csv"

        // Save to Documents directory (for History view to find)
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileName)

        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)

            let elapsed = Date().timeIntervalSince(startTime)
            let columnCount = headerParts.count
            Logger.shared.info("[ShareView] ✅ CSV share complete: \(fileName) | \(totalCount) records | \(columnCount) columns | \(String(format: "%.2f", elapsed))s")

            return fileURL
        } catch {
            Logger.shared.error("[ShareView] ❌ Failed to create CSV: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "Failed to save CSV: \(error.localizedDescription)"
                showError = true
            }
            return nil
        }
    }
}

// MARK: - Share Sheet (UIKit wrapper)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - CSV Document for File Export
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var csvContent: String

    init(csvContent: String) {
        self.csvContent = csvContent
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        csvContent = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = csvContent.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
