//
//  SingleProtocolAIRPreflightTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

final class SingleProtocolAIRPreflightTests: XCTestCase {

    func testPassWhenClenchDropsEightPercent() {
        let rest = Array(repeating: 1_000_000.0, count: 20)
        let clench = Array(repeating: 900_000.0, count: 10) // 10% drop
        let stats = SingleProtocolAIRPreflight.evaluate(restSamples: rest, clenchSamples: clench)
        XCTAssertTrue(stats.passed)
        XCTAssertEqual(stats.restMedian, 1_000_000, accuracy: 1)
        XCTAssertEqual(stats.clenchMin, 900_000, accuracy: 1)
        XCTAssertEqual(stats.dropFraction, 0.1, accuracy: 0.001)
    }

    func testFailWhenDropBelowGate() {
        let rest = Array(repeating: 1_000_000.0, count: 20)
        let clench = Array(repeating: 960_000.0, count: 10) // 4% drop
        let stats = SingleProtocolAIRPreflight.evaluate(restSamples: rest, clenchSamples: clench)
        XCTAssertFalse(stats.passed)
        XCTAssertEqual(stats.dropFraction, 0.04, accuracy: 0.001)
    }

    func testFailWhenEmptySamples() {
        let stats = SingleProtocolAIRPreflight.evaluate(restSamples: [], clenchSamples: [])
        XCTAssertFalse(stats.passed)
        XCTAssertEqual(stats.dropFraction, 0)
    }

    func testMedianEvenCount() {
        XCTAssertEqual(SingleProtocolAIRPreflight.median([2, 4, 6, 8]), 5, accuracy: 0.001)
    }

    func testExactlyEightPercentPasses() {
        let rest = Array(repeating: 1_000_000.0, count: 10)
        let clench = Array(repeating: 920_000.0, count: 10)
        let stats = SingleProtocolAIRPreflight.evaluate(restSamples: rest, clenchSamples: clench)
        XCTAssertTrue(stats.passed)
        XCTAssertEqual(stats.dropFraction, 0.08, accuracy: 0.0001)
    }
}

@MainActor
final class ProtocolASetupGateTests: XCTestCase {

    func testMarkProtocolASetupCompletesFitAndProtocolFlags() {
        let defaults = UserDefaults.standard
        let fitKey = "oralable.hasCompletedFirstFit"
        let protocolKey = "oralable.hasCompletedProtocolASetup"
        let trialKey = "oralable.onboardingTrialSetupMode"
        let priorFit = defaults.bool(forKey: fitKey)
        let priorProtocol = defaults.bool(forKey: protocolKey)
        let priorTrial = defaults.bool(forKey: trialKey)
        defer {
            defaults.set(priorFit, forKey: fitKey)
            defaults.set(priorProtocol, forKey: protocolKey)
            defaults.set(priorTrial, forKey: trialKey)
        }

        defaults.set(false, forKey: fitKey)
        defaults.set(false, forKey: protocolKey)
        defaults.set(true, forKey: trialKey)

        let manager = FirstLaunchManager()
        XCTAssertFalse(manager.hasCompletedProtocolASetup)
        XCTAssertFalse(manager.hasCompletedFirstFit)
        XCTAssertTrue(manager.isTrialSetupMode)

        manager.markProtocolASetupCompleted()
        XCTAssertTrue(manager.hasCompletedProtocolASetup)
        XCTAssertTrue(manager.hasCompletedFirstFit)
        XCTAssertFalse(manager.isTrialSetupMode)
    }

    func testIRDropGateConstantMatchesPlan() {
        // Dual A Mac IR optical preflight still uses 8% drop; Single Setup uses couple.
        XCTAssertEqual(SingleProtocolAIRPreflight.defaultDropGate, 0.08, accuracy: 0.0001)
    }

    func testCoupleSeatQCTimeoutMatchesMac() {
        XCTAssertEqual(SingleProtocolASessionController.couplePreflightTimeoutS, 60, accuracy: 0.001)
        XCTAssertEqual(SingleProtocolASessionController.coupleDeskAbortGraceS, 20, accuracy: 0.001)
    }

    func testRegisterCompletedProtocolASessionAppearsInHistory() {
        let manager = RecordingSessionManager()
        let before = manager.sessions.count
        let edf = FileManager.default.temporaryDirectory
            .appendingPathComponent("protocol_a_test_\(UUID().uuidString).edf")
        try? "edf".write(to: edf, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: edf) }

        var session = RecordingSession(
            startTime: Date().addingTimeInterval(-360),
            status: .completed,
            deviceID: "test",
            deviceName: "Oralable",
            deviceType: .oralable
        )
        session.endTime = Date()
        session.notes = "Protocol A Setup"
        session.tags = [RecordingSession.protocolASetupTag]
        session.dataFilePath = edf
        session.sensorDataCount = 100

        XCTAssertTrue(manager.registerCompletedSession(session))
        XCTAssertEqual(manager.sessions.count, before + 1)
        XCTAssertTrue(manager.sessions.first?.isProtocolASetup == true)
        XCTAssertFalse(manager.registerCompletedSession(session), "Duplicate path should be skipped")
        XCTAssertEqual(manager.sessions.count, before + 1)

        manager.deleteSession(session)
    }

    func testProtocolASetupExportBookmarkRoundTrip() {
        let store = SessionHistoryStore()
        let prior = store.protocolASetupExport
        defer {
            if let prior {
                store.recordProtocolASetupExport(
                    recordingSessionId: prior.recordingSessionId,
                    sessionTimestamp: prior.sessionTimestamp,
                    sampleCount: prior.sampleCount,
                    deviceID: prior.deviceID,
                    deviceName: prior.deviceName,
                    completedAt: prior.completedAt
                )
            } else {
                store.clearProtocolASetupExport()
            }
        }

        let id = UUID()
        store.recordProtocolASetupExport(
            recordingSessionId: id,
            sessionTimestamp: "20260830_120000",
            sampleCount: 18000,
            deviceID: "dev",
            deviceName: "Oralable"
        )
        XCTAssertEqual(store.protocolASetupExport?.recordingSessionId, id)
        XCTAssertEqual(store.protocolASetupExport?.sampleCount, 18000)
        XCTAssertNil(store.protocolASetupShareURLs(), "No files on disk for synthetic stamp")
    }
}
