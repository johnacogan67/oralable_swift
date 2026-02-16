//
//  DemoParticipantDetailView.swift
//  OralableForProfessionals
//
//  Detail view for demo participant showing sessions
//  Allows Apple reviewers to explore sample data
//

import SwiftUI
import Charts

struct DemoParticipantDetailView: View {
    let participant: DemoDataManager.DemoParticipant
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSession: DemoDataManager.DemoSession?
    @State private var sessionData: [SerializableSensorData] = []
    @State private var isLoadingData = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Demo Banner
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.orange)
                        Text("Demo Mode - Sample Data")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)

                    // Participant Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(participant.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("ID: \(participant.id)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(12)

                    // Sessions List
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recorded Sessions")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(participant.sessions) { session in
                            DemoSessionRow(session: session)
                                .onTapGesture {
                                    loadSessionData(session)
                                }
                        }
                    }

                    // Session Data Preview (when selected)
                    if let session = selectedSession {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Session \(session.id.suffix(1))")
                                    .font(.headline)

                                Spacer()

                                if isLoadingData {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding(.horizontal)

                            if !sessionData.isEmpty {
                                // PPG Chart Preview
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("PPG IR Signal")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)

                                    Chart {
                                        ForEach(Array(sessionData.prefix(500).enumerated()), id: \.offset) { index, point in
                                            LineMark(
                                                x: .value("Sample", index),
                                                y: .value("PPG IR", point.ppgIR)
                                            )
                                            .foregroundStyle(Color.purple.opacity(0.7))
                                        }
                                    }
                                    .frame(height: 150)
                                    .chartXAxis(.hidden)
                                    .padding(.horizontal)
                                }
                                .padding(.vertical, 8)
                                .background(Color(UIColor.systemBackground))
                                .cornerRadius(12)

                                // Stats
                                HStack(spacing: 16) {
                                    StatCard(
                                        title: "Data Points",
                                        value: "\(sessionData.count)",
                                        icon: "chart.bar"
                                    )

                                    StatCard(
                                        title: "Duration",
                                        value: formatDuration(session.duration),
                                        icon: "clock"
                                    )

                                    StatCard(
                                        title: "Avg HR",
                                        value: "\(averageHeartRate)",
                                        icon: "heart.fill"
                                    )
                                }
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Demo Participant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func loadSessionData(_ session: DemoDataManager.DemoSession) {
        selectedSession = session
        isLoadingData = true

        DispatchQueue.global(qos: .userInitiated).async {
            let data = DemoDataManager.shared.getSessionData(for: session) ?? []

            DispatchQueue.main.async {
                sessionData = data
                isLoadingData = false
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private var averageHeartRate: Int {
        guard !sessionData.isEmpty else { return 0 }
        let total = sessionData.compactMap { $0.heartRateBPM }.reduce(0, +)
        return Int(total / Double(sessionData.count))
    }
}

// MARK: - Demo Session Row

struct DemoSessionRow: View {
    let session: DemoDataManager.DemoSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Session \(session.id.suffix(1))")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(formattedDate(session.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(formatDuration(session.duration))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(6)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.headline)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(8)
    }
}
