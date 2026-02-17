//
//  SessionHistoryView.swift
//  OralableApp
//
//  Created: December 6, 2025
//  Updated: December 6, 2025 - Restructured with 4-segment picker (EMG/IR/Movement/Temperature)
//  Purpose: History view with segmented control to filter data by type and device source
//

import SwiftUI

/// Filter options for session history - 4 segments showing data type and device source
enum HistoryFilter: String, CaseIterable {
    case emg = "EMG"
    case ir = "IR"
    case movement = "Move"
    case temperature = "Temp"

    /// Device that produces this data type
    var deviceSource: String {
        switch self {
        case .emg: return "ANR M40"
        case .ir, .movement, .temperature: return "Oralable"
        }
    }

    /// Icon for this data type
    var icon: String {
        switch self {
        case .emg: return "bolt.horizontal.circle.fill"
        case .ir: return "waveform.path.ecg"
        case .movement: return "figure.walk"
        case .temperature: return "thermometer.medium"
        }
    }

    /// Color for this data type
    var color: Color {
        switch self {
        case .emg: return .blue
        case .ir: return .purple
        case .movement: return .green
        case .temperature: return .orange
        }
    }

    /// Empty state title
    var emptyTitle: String {
        switch self {
        case .emg: return "No EMG Data"
        case .ir: return "No IR Data"
        case .movement: return "No Movement Data"
        case .temperature: return "No Temperature Data"
        }
    }

    /// Empty state message
    var emptyMessage: String {
        switch self {
        case .emg: return "Connect an ANR M40 device and start recording to capture EMG data."
        case .ir: return "Connect an Oralable device and start recording to capture IR/PPG data."
        case .movement: return "Connect an Oralable device and start recording to capture movement data."
        case .temperature: return "Connect an Oralable device and start recording to capture temperature data."
        }
    }

    /// Detailed description for section header
    var description: String {
        switch self {
        case .emg: return "Electromyography (Muscle Electrical Activity)"
        case .ir: return "Infrared PPG (Photoplethysmography)"
        case .movement: return "Accelerometer (Motion Detection)"
        case .temperature: return "Skin Temperature"
        }
    }
}

struct SessionHistoryView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @ObservedObject var sessionManager: RecordingSessionManager

    @State private var selectedFilter: HistoryFilter = .ir

    /// Filtered sessions based on selected filter
    private var filteredSessions: [RecordingSession] {
        switch selectedFilter {
        case .emg:
            return sessionManager.sessions.filter { $0.deviceType == .anr }
        case .ir:
            return sessionManager.sessions.filter { $0.deviceType == .oralable }
        case .movement:
            // Movement data comes from Oralable device (accelerometer)
            return sessionManager.sessions.filter { $0.deviceType == .oralable && $0.hasAccelerometerData }
        case .temperature:
            // Temperature data comes from Oralable device
            return sessionManager.sessions.filter { $0.deviceType == .oralable && $0.hasTemperatureData }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 4-segment picker
                filterPicker
                    .padding(.horizontal)
                    .padding(.top, designSystem.spacing.sm)

                // Source label with description
                sourceInfo
                    .padding(.horizontal)
                    .padding(.vertical, designSystem.spacing.sm)

                // Session count
                if !filteredSessions.isEmpty {
                    sessionCount
                        .padding(.horizontal)
                        .padding(.bottom, designSystem.spacing.xs)
                }

                // Session list or empty state
                if filteredSessions.isEmpty {
                    emptyStateView
                } else {
                    sessionList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Subviews

    private var filterPicker: some View {
        Picker("Data Type", selection: $selectedFilter) {
            ForEach(HistoryFilter.allCases, id: \.self) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private var sourceInfo: some View {
        HStack(spacing: designSystem.spacing.sm) {
            Image(systemName: selectedFilter.icon)
                .foregroundColor(selectedFilter.color)
                .font(designSystem.typography.labelSmall)

            VStack(alignment: .leading, spacing: designSystem.spacing.xxs) {
                Text(selectedFilter.description)
                    .font(designSystem.typography.bodySmall)
                    .foregroundColor(designSystem.colors.textPrimary)

                Text("Source: \(selectedFilter.deviceSource)")
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.textSecondary)
            }

            Spacer()
        }
        .padding(designSystem.spacing.buttonPadding)
        .background(designSystem.colors.backgroundSecondary)
        .cornerRadius(designSystem.cornerRadius.medium)
    }

    private var sessionCount: some View {
        HStack {
            Text("\(filteredSessions.count) session\(filteredSessions.count == 1 ? "" : "s")")
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)
            Spacer()
        }
    }

    private var sessionList: some View {
        List {
            ForEach(filteredSessions) { session in
                SessionRowView(session: session, highlightColor: selectedFilter.color)
            }
            .onDelete(perform: deleteSession)
        }
        .listStyle(.insetGrouped)
    }

    private var emptyStateView: some View {
        VStack(spacing: designSystem.spacing.md) {
            Spacer()

            Image(systemName: selectedFilter.icon)
                .font(.system(size: 60))
                .foregroundColor(selectedFilter.color.opacity(0.5))

            Text(selectedFilter.emptyTitle)
                .font(designSystem.typography.headline)
                .foregroundColor(designSystem.colors.textPrimary)

            Text(selectedFilter.emptyMessage)
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, designSystem.spacing.xl + designSystem.spacing.sm)

            Spacer()
        }
    }

    // MARK: - Actions

    private func deleteSession(at offsets: IndexSet) {
        for index in offsets {
            let session = filteredSessions[index]
            sessionManager.deleteSession(session)
        }
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: RecordingSession
    var highlightColor: Color = .blue

    private var dataTypeColor: Color {
        switch session.deviceType {
        case .anr: return .blue
        case .oralable: return .purple
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Data type indicator
            Image(systemName: session.dataTypeIcon)
                .font(.title2)
                .foregroundColor(highlightColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                // Device name and type badge
                HStack {
                    Text(session.deviceName ?? "Unknown Device")
                        .font(.headline)

                    Text(session.dataTypeLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(dataTypeColor)
                        .cornerRadius(4)
                }

                // Date and duration
                HStack {
                    Text(session.startTime, style: .date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(session.formattedDuration)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Data counts
                HStack(spacing: 8) {
                    if session.sensorDataCount > 0 {
                        Label("\(session.sensorDataCount)", systemImage: "waveform")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if session.heartRateDataCount > 0 {
                        Label("\(session.heartRateDataCount)", systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            Spacer()

            // Status indicator
            Image(systemName: session.status.icon)
                .foregroundColor(statusColor)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch session.status {
        case .recording: return .red
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}

#Preview {
    SessionHistoryView(sessionManager: RecordingSessionManager())
        .environmentObject(DesignSystem())
}
