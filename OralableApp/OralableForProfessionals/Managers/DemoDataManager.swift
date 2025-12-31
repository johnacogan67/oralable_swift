//
//  DemoDataManager.swift
//  OralableForProfessionals
//
//  Manages demo participant data for testing without real imports
//  Allows Apple reviewers to explore the app with sample data
//

import Foundation
import Combine
import OralableCore

class DemoDataManager: ObservableObject {
    static let shared = DemoDataManager()

    // MARK: - Demo Participant
    struct DemoParticipant: Identifiable {
        let id: String
        let name: String
        let sessions: [DemoSession]
    }

    struct DemoSession: Identifiable {
        let id: String
        let date: Date
        let duration: TimeInterval
        let csvFileName: String
    }

    // MARK: - Properties
    @Published var demoParticipant: DemoParticipant?
    @Published var isLoaded = false

    // MARK: - Initialization
    private init() {
        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDemoModeChanged),
            name: .demoModeChanged,
            object: nil
        )
    }

    @objc private func handleDemoModeChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }

        if enabled {
            loadDemoParticipant()
        } else {
            clearDemoData()
        }
    }

    // MARK: - Load Demo Data
    func loadDemoParticipant() {
        let sessions = [
            DemoSession(
                id: "demo-session-1",
                date: Date().addingTimeInterval(-5 * 24 * 60 * 60), // 5 days ago
                duration: 8 * 60, // 8 minutes
                csvFileName: "demo_participant_session_1"
            ),
            DemoSession(
                id: "demo-session-2",
                date: Date().addingTimeInterval(-3 * 24 * 60 * 60), // 3 days ago
                duration: 10 * 60, // 10 minutes
                csvFileName: "demo_participant_session_2"
            ),
            DemoSession(
                id: "demo-session-3",
                date: Date().addingTimeInterval(-1 * 24 * 60 * 60), // 1 day ago
                duration: 12 * 60, // 12 minutes
                csvFileName: "demo_participant_session_3"
            )
        ]

        demoParticipant = DemoParticipant(
            id: "DEMO-PARTICIPANT-001",
            name: "Demo Participant",
            sessions: sessions
        )

        isLoaded = true
        Logger.shared.info("[DemoDataManager] Loaded demo participant with \(sessions.count) sessions")
    }

    // MARK: - Get Session Data
    func getSessionData(for session: DemoSession) -> [SerializableSensorData]? {
        guard let csvURL = Bundle.main.url(forResource: session.csvFileName, withExtension: "csv") else {
            Logger.shared.error("[DemoDataManager] CSV not found: \(session.csvFileName)")
            return nil
        }

        do {
            let content = try String(contentsOf: csvURL, encoding: .utf8)
            return parseCSV(content)
        } catch {
            Logger.shared.error("[DemoDataManager] Failed to load CSV: \(error)")
            return nil
        }
    }

    // MARK: - Parse CSV
    private func parseCSV(_ content: String) -> [SerializableSensorData] {
        let lines = content.components(separatedBy: .newlines)
        guard lines.count > 1 else { return [] }

        let header = lines[0].components(separatedBy: ",")
        let columns = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var points: [SerializableSensorData] = []

        for i in 1..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let values = line.components(separatedBy: ",")
            guard values.count >= 11 else { continue }

            guard let timestamp = dateFormatter.date(from: values[columns["timestamp"] ?? 0]) else { continue }

            let ppgIR = Int32(values[columns["ppg_ir"] ?? 1]) ?? 0
            let ppgRed = Int32(values[columns["ppg_red"] ?? 2]) ?? 0
            let ppgGreen = Int32(values[columns["ppg_green"] ?? 3]) ?? 0
            let accelX = Int16(values[columns["accel_x"] ?? 4]) ?? 0
            let accelY = Int16(values[columns["accel_y"] ?? 5]) ?? 0
            let accelZ = Int16(values[columns["accel_z"] ?? 6]) ?? 0
            let temperature = Double(values[columns["temperature"] ?? 7]) ?? 0
            let heartRate = Double(values[columns["heart_rate"] ?? 8]) ?? 0
            let spo2 = Double(values[columns["spo2"] ?? 9]) ?? 0
            let battery = Int(values[columns["battery"] ?? 10]) ?? 0

            // Calculate accelerometer magnitude
            let accelMagnitude = sqrt(Double(accelX * accelX + accelY * accelY + accelZ * accelZ))

            let point = SerializableSensorData(
                timestamp: timestamp,
                deviceType: "Oralable",
                ppgRed: ppgRed,
                ppgIR: ppgIR,
                ppgGreen: ppgGreen,
                emg: nil,
                accelX: accelX,
                accelY: accelY,
                accelZ: accelZ,
                accelMagnitude: accelMagnitude,
                temperatureCelsius: temperature,
                batteryPercentage: battery,
                heartRateBPM: heartRate,
                heartRateQuality: 0.8,
                spo2Percentage: spo2,
                spo2Quality: 0.8
            )

            points.append(point)
        }

        return points
    }

    // MARK: - Get All Sessions Data
    func getAllSessionsData() -> [SerializableSensorData]? {
        guard let csvURL = Bundle.main.url(forResource: "demo_participant_all_sessions", withExtension: "csv") else {
            Logger.shared.error("[DemoDataManager] Combined CSV not found")
            return nil
        }

        do {
            let content = try String(contentsOf: csvURL, encoding: .utf8)
            return parseCSV(content)
        } catch {
            Logger.shared.error("[DemoDataManager] Failed to load combined CSV: \(error)")
            return nil
        }
    }

    // MARK: - Clear Demo Data
    func clearDemoData() {
        demoParticipant = nil
        isLoaded = false
        Logger.shared.info("[DemoDataManager] Demo data cleared")
    }
}
