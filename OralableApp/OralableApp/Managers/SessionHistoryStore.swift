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
    private var lastSpO2Timestamp: Date?
    private var currentHourIndex: Int = 0
    private var autoSessionUUID: UUID?

    private let spo2HypoxiaThreshold: Double = 90

    init() {}

    func attach(recordingManager: RecordingSessionManager, deviceManager: DeviceManager) {
        self.recordingManager = recordingManager
        self.deviceManager = deviceManager
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
        guard hourProbCount > 0 || hourSashbAccumulator > 0 || hourRescueEvents > 0 else { return }
        let start = anchor.addingTimeInterval(Double(currentHourIndex) * 3600)
        let end = min(date, anchor.addingTimeInterval(Double(currentHourIndex + 1) * 3600))
        let n = max(1, hourProbCount)
        let seg = HourlyTemporalisSegment(
            hourIndex: currentHourIndex,
            segmentStart: start,
            segmentEnd: end,
            quiet: hourProbSumQuiet / Double(n),
            phasic: hourProbSumPhasic / Double(n),
            tonic: hourProbSumTonic / Double(n),
            rescue: hourProbSumRescue / Double(n),
            sashbHypoxicBurden: hourSashbAccumulator,
            rescueEventCount: hourRescueEvents
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
}

