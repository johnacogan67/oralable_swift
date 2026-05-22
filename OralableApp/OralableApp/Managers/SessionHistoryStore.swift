//
//  SessionHistoryStore.swift
//  OralableApp
//
//  Aggregates Temporalis probabilities and SASHB into 1-hour segments (relative to session
//  start) and persists them on the active RecordingSession.
//

import Foundation
import OralableCore

@MainActor
final class SessionHistoryStore: ObservableObject {
    weak var recordingManager: RecordingSessionManager?
    weak var deviceManager: DeviceManager?

    /// Segments keyed by hour index since session anchor.
    @Published private(set) var segmentByHour: [Int: HourlyTemporalisSegment] = [:]

    private var sessionAnchor: Date?
    private var activeSessionId: UUID?
    private var hourProbSumQuiet: Double = 0
    private var hourProbSumPhasic: Double = 0
    private var hourProbSumTonic: Double = 0
    private var hourProbSumRescue: Double = 0
    private var hourProbCount: Int = 0
    private var hourSashbAccumulator: Double = 0
    private var hourRescueEvents: Int = 0
    private var hourTfiSum: Double = 0
    private var hourTfiCount: Int = 0
    private var lastSpO2Timestamp: Date?
    private var currentHourIndex: Int = 0
    private var autoSessionUUID: UUID?

    private let spo2HypoxiaThreshold: Double = 90

    // MARK: - Temporalis sleep study (fit guide + 10-minute calibration)

    struct TemporalisSleepCalibrationRecord: Codable, Equatable, Sendable {
        let calibrationId: UUID
        let baselineVoltage: Double
        let completedAt: Date
        let peripheralId: UUID
        /// File name only; resolved via `researchCalibrationURL(fileName:)`.
        let rawCalibrationCSVFileName: String?

        init(
            calibrationId: UUID,
            baselineVoltage: Double,
            completedAt: Date,
            peripheralId: UUID,
            rawCalibrationCSVFileName: String? = nil
        ) {
            self.calibrationId = calibrationId
            self.baselineVoltage = baselineVoltage
            self.completedAt = completedAt
            self.peripheralId = peripheralId
            self.rawCalibrationCSVFileName = rawCalibrationCSVFileName
        }

        private enum CodingKeys: String, CodingKey {
            case calibrationId, baselineVoltage, completedAt, peripheralId, rawCalibrationCSVFileName
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            calibrationId = try c.decode(UUID.self, forKey: .calibrationId)
            baselineVoltage = try c.decode(Double.self, forKey: .baselineVoltage)
            completedAt = try c.decode(Date.self, forKey: .completedAt)
            peripheralId = try c.decode(UUID.self, forKey: .peripheralId)
            rawCalibrationCSVFileName = try c.decodeIfPresent(String.self, forKey: .rawCalibrationCSVFileName)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(calibrationId, forKey: .calibrationId)
            try c.encode(baselineVoltage, forKey: .baselineVoltage)
            try c.encode(completedAt, forKey: .completedAt)
            try c.encode(peripheralId, forKey: .peripheralId)
            try c.encodeIfPresent(rawCalibrationCSVFileName, forKey: .rawCalibrationCSVFileName)
        }
    }

    private static let researchCalibrationFolder = "Oralable/ResearchCalibration"

    static func researchCalibrationDirectoryURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(researchCalibrationFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func researchCalibrationURL(fileName: String) throws -> URL {
        try researchCalibrationDirectoryURL().appendingPathComponent(fileName)
    }

    @Published private(set) var temporalisSleepCalibration: TemporalisSleepCalibrationRecord?

    private static let sleepCalDefaultsKey = "oralable.temporalis_sleep_calibration"

    init() {
        loadSleepCalibration()
    }

    func recordTemporalisSleepCalibration(
        calibrationId: UUID,
        baselineVoltage: Double,
        peripheralId: UUID,
        rawCalibrationCSVFileName: String? = nil
    ) {
        let record = TemporalisSleepCalibrationRecord(
            calibrationId: calibrationId,
            baselineVoltage: baselineVoltage,
            completedAt: Date(),
            peripheralId: peripheralId,
            rawCalibrationCSVFileName: rawCalibrationCSVFileName
        )
        temporalisSleepCalibration = record
        persistSleepCalibration()
    }

    func clearTemporalisSleepCalibration() {
        temporalisSleepCalibration = nil
        persistSleepCalibration()
    }

    func resetLocalUserState(deleteRawCalibrationFiles: Bool = false) {
        clearTemporalisSleepCalibration()
        if deleteRawCalibrationFiles {
            Self.deleteResearchCalibrationFiles()
        }
    }

    static func clearPersistedTemporalisSleepCalibration(
        in defaults: UserDefaults = .standard,
        deleteRawCalibrationFiles: Bool = false
    ) {
        defaults.removeObject(forKey: sleepCalDefaultsKey)
        if deleteRawCalibrationFiles {
            deleteResearchCalibrationFiles()
        }
    }

    /// Call when BLE primary changes: drop stored calibration if a different peripheral is now primary.
    func applyPrimaryDeviceForSleepGate(primaryPeripheralId: UUID?) {
        guard let cal = temporalisSleepCalibration, let pid = primaryPeripheralId else { return }
        if cal.peripheralId != pid {
            temporalisSleepCalibration = nil
            persistSleepCalibration()
        }
    }

    /// Enables "Start overnight session" only for the REV10 unit that completed calibration while connected.
    func isOvernightSessionAllowed(primaryPeripheralId: UUID?, isPrimaryConnected: Bool) -> Bool {
        guard isPrimaryConnected,
              let pid = primaryPeripheralId,
              let cal = temporalisSleepCalibration,
              cal.peripheralId == pid else { return false }
        return true
    }

    private func loadSleepCalibration() {
        guard let data = UserDefaults.standard.data(forKey: Self.sleepCalDefaultsKey),
              let decoded = try? JSONDecoder().decode(TemporalisSleepCalibrationRecord.self, from: data) else {
            return
        }
        temporalisSleepCalibration = decoded
    }

    private func persistSleepCalibration() {
        if let record = temporalisSleepCalibration,
           let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: Self.sleepCalDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.sleepCalDefaultsKey)
        }
    }

    private static func deleteResearchCalibrationFiles() {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let dir = base.appendingPathComponent(researchCalibrationFolder, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    func attach(recordingManager: RecordingSessionManager, deviceManager: DeviceManager) {
        self.recordingManager = recordingManager
        self.deviceManager = deviceManager
        applyPrimaryDeviceForSleepGate(primaryPeripheralId: deviceManager.primaryDevice?.peripheralIdentifier)
    }

    func beginSession(anchor: Date, sessionId: UUID) {
        sessionAnchor = anchor
        activeSessionId = sessionId
        currentHourIndex = 0
        segmentByHour = [:]
        resetHourBucket()
        lastSpO2Timestamp = nil
    }

    func endSession(at date: Date = Date()) {
        flushCurrentHour(at: date)
        pushToRecordingSession()
        sessionAnchor = nil
        activeSessionId = nil
        autoSessionUUID = nil
        resetHourBucket()
    }

    /// Clears in-memory segment state when the device disconnects.
    func resetForDisconnect() {
        sessionAnchor = nil
        activeSessionId = nil
        autoSessionUUID = nil
        currentHourIndex = 0
        resetHourBucket()
        lastSpO2Timestamp = nil
        segmentByHour = [:]
    }

    func recordTemporalis(_ probabilities: TemporalisProbabilities, at date: Date) {
        guard isRecordingContextActive else { return }
        ensureAnchor(at: date)
        guard sessionAnchor != nil else { return }

        let idx = hourIndex(for: date)
        if idx != currentHourIndex {
            flushCurrentHour(at: date)
            currentHourIndex = idx
            resetHourBucket()
        }

        hourProbSumQuiet += probabilities.quiet
        hourProbSumPhasic += probabilities.phasic
        hourProbSumTonic += probabilities.tonic
        hourProbSumRescue += probabilities.rescue
        hourProbCount += 1
        if probabilities.dominantState == .rescue {
            hourRescueEvents += 1
        }
    }

    func recordTFI(percent: Double, at date: Date) {
        guard isRecordingContextActive else { return }
        guard percent.isFinite else { return }
        ensureAnchor(at: date)
        guard sessionAnchor != nil else { return }

        let idx = hourIndex(for: date)
        if idx != currentHourIndex {
            flushCurrentHour(at: date)
            currentHourIndex = idx
            resetHourBucket()
        }

        hourTfiSum += min(100, max(0, percent))
        hourTfiCount += 1
    }

    func recordSpO2Sample(percent: Double?, at date: Date) {
        guard isRecordingContextActive else { return }
        guard let p = percent, p > 0, p <= 100 else {
            lastSpO2Timestamp = date
            return
        }
        ensureAnchor(at: date)
        guard sessionAnchor != nil else { return }

        let idx = hourIndex(for: date)
        if idx != currentHourIndex {
            flushCurrentHour(at: date)
            currentHourIndex = idx
            resetHourBucket()
        }

        let dt: Double
        if let last = lastSpO2Timestamp {
            dt = max(0, min(date.timeIntervalSince(last), 2.0))
        } else {
            dt = 0.02
        }
        lastSpO2Timestamp = date
        if p < spo2HypoxiaThreshold, dt > 0 {
            hourSashbAccumulator += (spo2HypoxiaThreshold - p) * dt
        }
    }

    private var isRecordingContextActive: Bool {
        recordingManager?.currentSession != nil || deviceManager?.automaticRecordingSession?.isSessionActive == true
    }

    private func hourIndex(for date: Date) -> Int {
        guard let anchor = sessionAnchor else { return 0 }
        return max(0, Int(floor(date.timeIntervalSince(anchor) / 3600.0)))
    }

    private func ensureAnchor(at date: Date) {
        if sessionAnchor != nil { return }
        if let manual = recordingManager?.currentSession {
            beginSession(anchor: manual.startTime, sessionId: manual.id)
            return
        }
        if deviceManager?.automaticRecordingSession?.isSessionActive == true {
            if autoSessionUUID == nil {
                autoSessionUUID = UUID()
            }
            if let sid = autoSessionUUID {
                beginSession(anchor: date, sessionId: sid)
            }
        }
    }

    private func flushCurrentHour(at date: Date) {
        guard let anchor = sessionAnchor else { return }
        guard hourProbCount > 0 || hourSashbAccumulator > 0 || hourRescueEvents > 0 || hourTfiCount > 0 else { return }
        let start = anchor.addingTimeInterval(Double(currentHourIndex) * 3600)
        let end = min(date, anchor.addingTimeInterval(Double(currentHourIndex + 1) * 3600))
        let n = max(1, hourProbCount)
        let tfiHourly: Double = hourTfiCount > 0 ? hourTfiSum / Double(hourTfiCount) : 0
        let seg = HourlyTemporalisSegment(
            hourIndex: currentHourIndex,
            segmentStart: start,
            segmentEnd: end,
            quiet: hourProbSumQuiet / Double(n),
            phasic: hourProbSumPhasic / Double(n),
            tonic: hourProbSumTonic / Double(n),
            rescue: hourProbSumRescue / Double(n),
            sashbHypoxicBurden: hourSashbAccumulator,
            rescueEventCount: hourRescueEvents,
            tfiPercent: tfiHourly
        )
        segmentByHour[currentHourIndex] = seg
        resetHourBucket()
        pushToRecordingSession()
    }

    private func resetHourBucket() {
        hourProbSumQuiet = 0
        hourProbSumPhasic = 0
        hourProbSumTonic = 0
        hourProbSumRescue = 0
        hourProbCount = 0
        hourSashbAccumulator = 0
        hourRescueEvents = 0
        hourTfiSum = 0
        hourTfiCount = 0
    }

    private func pushToRecordingSession() {
        guard let manager = recordingManager,
              var session = manager.currentSession,
              let sid = activeSessionId,
              session.id == sid else { return }
        let sorted = segmentByHour.keys.sorted().compactMap { segmentByHour[$0] }
        session.hourlyTemporalisSegments = sorted
        manager.currentSession = session
        if let idx = manager.sessions.firstIndex(where: { $0.id == session.id }) {
            manager.sessions[idx] = session
        }
        manager.saveSessionsToDisk()
    }

    /// JSON suitable for OralableForProfessionals (hourly TFI + SASHB + `SharedSessionData`).
    func encodeProfessionalHandshakeExportJSON(
        linkUUID: UUID,
        sensorHistory: [SensorData]
    ) throws -> Data {
        let displayCode = ClinicianLinkCodeFormatter.sixCharacterCode(linkUUID: linkUUID)
        let sharedSession = SharedSessionData(from: sensorHistory)
        let hourlySorted = segmentByHour.keys.sorted().compactMap { segmentByHour[$0] }
        let rollups: [ProfessionalHourlyRollupExport] = hourlySorted.map { seg in
            ProfessionalHourlyRollupExport(
                hourIndex: seg.hourIndex,
                segmentStart: seg.segmentStart,
                segmentEnd: seg.segmentEnd,
                tfiPercent: seg.tfiPercent,
                sashbHypoxicBurden: seg.sashbHypoxicBurden,
                quiet: seg.quiet,
                phasic: seg.phasic,
                tonic: seg.tonic,
                rescue: seg.rescue,
                rescueEventCount: seg.rescueEventCount
            )
        }
        let payload = ProfessionalHandshakeExport(
            linkUUID: linkUUID,
            displayCode: displayCode,
            sharedSession: sharedSession,
            hourlyRollups: rollups
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(payload)
    }
}

