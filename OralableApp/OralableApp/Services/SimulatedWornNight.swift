//
//  SimulatedWornNight.swift
//  OralableApp
//
//  Developer-only 4 h worn night. Written as a research CSV and a completed
//  local session. Not a recorded night and not uploaded.
//

import Foundation
import OralableCore

enum SimulatedWornNightError: LocalizedError {
    case empty
    case notRegistered

    var errorDescription: String? {
        switch self {
        case .empty:
            return "The simulated night had no samples."
        case .notRegistered:
            return "The simulated night was not saved."
        }
    }
}

enum SimulatedWornNight {
    static let sessionTag = "simulated"
    static let sampleHz = 10.0
    static let durationSeconds = 4.0 * 3600.0
    static let fileName = "simulated_worn_night.csv"

    private static let quietIR: Int32 = 200_000
    private static let tonicIR: Int32 = 100_000
    private static let rescueIR: Int32 = 80_000
    /// Mild IR drop (about 7% after the classifier’s scaling) so the following
    /// quiet samples are marked recovery.
    private static let settleIR: Int32 = 185_000
    private static let stillZ: Int16 = 16_384
    private static let grindX: Int16 = 12_000

    private enum Kind {
        case tonic
        case phasic
        case rescue
        case settle
    }

    private struct Span {
        var start: Double
        var end: Double
        var kind: Kind
    }

    /// Holds and bursts sit after the first minute so the IR baseline stays high.
    private static let spans: [Span] = [
        Span(start: 30 * 60, end: 30 * 60 + 90, kind: .tonic),
        Span(start: 30 * 60 + 90, end: 30 * 60 + 110, kind: .settle),
        Span(start: 70 * 60, end: 70 * 60 + 12, kind: .phasic),
        Span(start: 110 * 60, end: 110 * 60 + 75, kind: .tonic),
        Span(start: 110 * 60 + 75, end: 110 * 60 + 95, kind: .settle),
        Span(start: 150 * 60, end: 150 * 60 + 25, kind: .rescue),
        Span(start: 150 * 60 + 25, end: 150 * 60 + 45, kind: .settle),
        Span(start: 190 * 60, end: 190 * 60 + 10, kind: .phasic),
        Span(start: 210 * 60, end: 210 * 60 + 30, kind: .rescue),
        Span(start: 210 * 60 + 30, end: 210 * 60 + 50, kind: .settle)
    ]

    static func samples(endingAt end: Date = Date()) -> [SensorData] {
        let count = Int(durationSeconds * sampleHz)
        let start = end.addingTimeInterval(-Double(count - 1) / sampleHz)
        var out: [SensorData] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let t = Double(i) / sampleHz
            let stamp = start.addingTimeInterval(t)
            out.append(sample(at: t, timestamp: stamp))
        }
        return out
    }

    static func destinationURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents
            .appendingPathComponent("RecordingSessions", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Replaces any earlier simulated session, writes the CSV, and registers a completed local session.
    @MainActor
    static func load(using manager: RecordingSessionManager) async throws -> RecordingSession {
        let url = destinationURL()
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocking = manager.sessions.filter {
            $0.tags.contains(sessionTag) || $0.dataFilePath == url
        }
        for session in blocking {
            manager.deleteSession(session)
        }

        let prepared = try await Task.detached(priority: .userInitiated) {
            try prepare(at: url)
        }.value

        var session = RecordingSession(
            startTime: prepared.start,
            status: .completed,
            deviceID: "SIMULATED",
            deviceName: "Simulated Oralable",
            deviceType: .oralable
        )
        session.endTime = prepared.end
        session.dataFilePath = url
        session.tags = [sessionTag]
        session.notes = "Simulated 4 h worn night. Not a recorded night."
        session.sensorDataCount = prepared.sampleCount
        session.ppgDataCount = prepared.sampleCount
        session.spo2DataCount = prepared.sampleCount
        guard manager.registerCompletedSession(session) else {
            throw SimulatedWornNightError.notRegistered
        }
        return session
    }

    private struct Prepared: Sendable {
        var start: Date
        var end: Date
        var sampleCount: Int
    }

    private static func prepare(at url: URL) throws -> Prepared {
        let rows = samples()
        guard let start = rows.first?.timestamp, let end = rows.last?.timestamp else {
            throw SimulatedWornNightError.empty
        }
        try ResearchRawDataExport.writeOralableRaw50HzCSV(samples: rows, to: url)
        return Prepared(start: start, end: end, sampleCount: rows.count)
    }

    private static func sample(at t: Double, timestamp: Date) -> SensorData {
        let kind = spans.first { t >= $0.start && t < $0.end }?.kind
        let ir: Int32
        let spo2: Double
        let ax: Int16
        switch kind {
        case .tonic:
            ir = tonicIR
            spo2 = 96
            ax = 0
        case .phasic:
            ir = quietIR
            spo2 = 96
            ax = grindX
        case .rescue:
            ir = rescueIR
            spo2 = 88
            ax = 0
        case .settle:
            ir = settleIR
            spo2 = 96
            ax = 0
        case nil:
            ir = quietIR
            spo2 = 97
            ax = 0
        }
        return SensorData(
            timestamp: timestamp,
            ppg: PPGData(red: ir / 2, ir: ir, green: ir / 3, timestamp: timestamp),
            accelerometer: AccelerometerData(x: ax, y: 0, z: stillZ, timestamp: timestamp),
            temperature: TemperatureData(celsius: 36.5, timestamp: timestamp),
            battery: BatteryData(percentage: 80, timestamp: timestamp),
            heartRate: nil,
            spo2: SpO2Data(percentage: spo2, quality: 0.9, timestamp: timestamp),
            deviceType: .oralable
        )
    }
}
