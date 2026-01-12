//
//  LogsView.swift
//  OralableApp
//
//  Log viewer for debugging and troubleshooting.
//
//  Features:
//  - Filter logs by level (debug, info, warning, error)
//  - Search logs by text content
//  - Export logs to file for support
//  - Clear log history
//
//  Used for diagnosing device connection and data issues.
//
//  Updated: November 7, 2025 - Fixed LogLevel conflicts
//

import SwiftUI

struct LogsView: View {
    @EnvironmentObject var logsManager: LogsManager
    @EnvironmentObject var designSystem: DesignSystem
    @State private var selectedLogLevel: LogLevel = .all
    @State private var searchText = ""
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    
    var body: some View {
        VStack(spacing: 0) {
            // Filters and Controls
            controlsSection
            
            // Logs List
            if filteredLogs.isEmpty {
                emptyStateView
            } else {
                logsList
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { logsManager.refreshLogs() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    
                    Button(action: { exportLogs() }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: { clearLogs() }) {
                        Label("Clear All", systemImage: "trash")
                    }
                    .foregroundColor(.red)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search logs...")
        .sheet(isPresented: $showingExportSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .onAppear {
            logsManager.startMonitoring()
        }
        .onDisappear {
            logsManager.stopMonitoring()
        }
    }
    
    // MARK: - Controls Section
    
    private var controlsSection: some View {
        VStack(spacing: designSystem.spacing.sm) {
            // Log Level Filter
            Picker("Log Level", selection: $selectedLogLevel) {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, designSystem.spacing.md)
            
            // Stats Bar
            HStack(spacing: designSystem.spacing.lg) {
                LogStatView(
                    icon: "exclamationmark.triangle",
                    count: logsManager.errorCount,
                    color: .red
                )
                
                LogStatView(
                    icon: "exclamationmark.circle",
                    count: logsManager.warningCount,
                    color: .orange
                )
                
                LogStatView(
                    icon: "info.circle",
                    count: logsManager.infoCount,
                    color: .blue
                )
                
                LogStatView(
                    icon: "ant.circle",
                    count: logsManager.debugCount,
                    color: .purple
                )
            }
            .padding(.horizontal, designSystem.spacing.md)
            .padding(.vertical, designSystem.spacing.sm)
            .background(designSystem.colors.backgroundSecondary)
        }
    }
    
    // MARK: - Logs List
    
    private var logsList: some View {
        List {
            ForEach(filteredLogs) { log in
                LogRowView(log: log)
                    .listRowBackground(
                        log.level == .error ? Color.red.opacity(0.05) :
                        log.level == .warning ? Color.orange.opacity(0.05) :
                        Color.clear
                    )
            }
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: designSystem.spacing.lg) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(designSystem.colors.textTertiary)
            
            Text("No Logs Found")
                .font(designSystem.typography.headline)
                .foregroundColor(designSystem.colors.textPrimary)
            
            Text(searchText.isEmpty ? "No logs available" : "No logs matching '\(searchText)'")
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textSecondary)
            
            Spacer()
        }
        .padding(designSystem.spacing.xl)
    }
    
    // MARK: - Computed Properties
    
    private var filteredLogs: [LogEntry] {
        logsManager.logs
            .filter { log in
                (selectedLogLevel == .all || log.level == selectedLogLevel) &&
                (searchText.isEmpty || log.message.localizedCaseInsensitiveContains(searchText))
            }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Actions
    
    private func exportLogs() {
        let logs = filteredLogs.map { log in
            "[\(log.timestamp.formatted())] [\(log.level.rawValue)] \(log.category): \(log.message)"
        }.joined(separator: "\n")
        
        let fileName = "oralable_logs_\(Date().timeIntervalSince1970).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try logs.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showingExportSheet = true
        } catch {
            Logger.shared.error("[to export logs: \(error)")
        }
    }
    
    private func clearLogs() {
        logsManager.clearLogs()
    }
}

// MARK: - Log Row View

struct LogRowView: View {
    @EnvironmentObject var designSystem: DesignSystem
    let log: LogEntry
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
            // Header
            HStack {
                // Level Icon
                Image(systemName: log.level.icon)
                    .foregroundColor(log.level.color)
                    .frame(width: 20)
                
                // Category
                Text(log.category)
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
                
                Spacer()
                
                // Timestamp
                Text(log.timestamp, style: .time)
                    .font(designSystem.typography.caption2)
                    .foregroundColor(designSystem.colors.textTertiary)
            }
            
            // Message
            Text(log.message)
                .font(designSystem.typography.body)
                .foregroundColor(designSystem.colors.textPrimary)
                .lineLimit(isExpanded ? nil : 2)
                .onTapGesture {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
            
            // Details (if expanded and available)
            if isExpanded, let details = log.details {
                Text(details)
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
                    .padding(designSystem.spacing.sm)
                    .background(designSystem.colors.backgroundTertiary)
                    .cornerRadius(designSystem.cornerRadius.xs)
            }
        }
        .padding(.vertical, designSystem.spacing.xs)
    }
}

// MARK: - Log Stat View

struct LogStatView: View {
    @EnvironmentObject var designSystem: DesignSystem
    let icon: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text("\(count)")
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textPrimary)
        }
    }
}

// MARK: - Logs Manager

class LogsManager: ObservableObject {
    static let shared = LogsManager()
    
    @Published var logs: [LogEntry] = []
    @Published var errorCount = 0
    @Published var warningCount = 0
    @Published var infoCount = 0
    @Published var debugCount = 0
    
    private var isMonitoring = false
    private var timer: Timer?
    
    init() {
        loadMockLogs() // For preview
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // In production, this would monitor actual logs
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.checkForNewLogs()
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }
    
    func refreshLogs() {
        // Refresh logs from source
        loadMockLogs()
        updateCounts()
    }
    
    func clearLogs() {
        logs.removeAll()
        updateCounts()
    }
    
    private func checkForNewLogs() {
        // In production, check for new log entries
    }
    
    private func updateCounts() {
        errorCount = logs.filter { $0.level == .error }.count
        warningCount = logs.filter { $0.level == .warning }.count
        infoCount = logs.filter { $0.level == .info }.count
        debugCount = logs.filter { $0.level == .debug }.count
    }
    
    private func loadMockLogs() {
        // Mock data for preview
        logs = [
            LogEntry(
                timestamp: Date(),
                level: .info,
                message: "Connected to Oralable device",
                category: "BLE",
                details: nil
            ),
            LogEntry(
                timestamp: Date().addingTimeInterval(-60),
                level: .debug,
                message: "DashboardViewModel initialized",
                category: "ViewModel",
                details: "Memory usage: 45.2 MB"
            ),
            LogEntry(
                timestamp: Date().addingTimeInterval(-120),
                level: .warning,
                message: "Export request took longer than expected",
                category: "Network",
                details: "Duration: 5.2 seconds"
            ),
            LogEntry(
                timestamp: Date().addingTimeInterval(-180),
                level: .error,
                message: "Failed to parse PPG data packet",
                category: "Data",
                details: "Invalid checksum: expected 0x42, got 0x41"
            ),
            LogEntry(
                timestamp: Date().addingTimeInterval(-240),
                level: .info,
                message: "Application launched",
                category: "App",
                details: "Version 1.0.0 (Build 100)"
            )
        ]
        updateCounts()
    }
}

// MARK: - Share Sheet (keep this since it's used)

struct LogsShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

struct LogsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LogsView()
                .environmentObject(DesignSystem())
        }
    }
}
