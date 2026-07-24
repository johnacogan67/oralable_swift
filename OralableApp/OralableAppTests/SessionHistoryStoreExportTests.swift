//
//  SessionHistoryStoreExportTests.swift
//  OralableAppTests
//
//  Guards clinician export / disconnect paths that previously dropped the
//  in-progress hourly TFI/SASHB bucket.
//

import XCTest
@testable import OralableApp
import OralableCore

@MainActor
final class SessionHistoryStoreExportTests: XCTestCase {

    func testHourlySegmentsIncludeInProgressHourBeforeRollover() throws {
        let store = SessionHistoryStore()
        let recordingManager = RecordingSessionManager()
        recordingManager.sessionHistoryStore = store
        store.recordingManager = recordingManager

        let session = try recordingManager.startSession(
            deviceID: "REV10",
            deviceName: "Oralable",
            deviceType: .oralable
        )
        let sampleTime = session.startTime.addingTimeInterval(120)
        store.recordTFI(percent: 42, at: sampleTime)

        XCTAssertTrue(
            store.segmentByHour.isEmpty,
            "In-progress hour should not be committed until rollover/end/export snapshot"
        )

        let segments = store.hourlySegmentsIncludingInProgress(at: sampleTime.addingTimeInterval(30))
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].hourIndex, 0)
        XCTAssertEqual(segments[0].tfiPercent, 42, accuracy: 0.0001)

        let exportData = try store.encodeProfessionalHandshakeExportJSON(
            linkUUID: UUID(),
            sensorHistory: [],
            at: sampleTime.addingTimeInterval(30)
        )
        let json = try XCTUnwrap(String(data: exportData, encoding: .utf8))
        XCTAssertTrue(
            json.contains("tfiPercent") && (json.contains(":42") || json.contains(":42.0")),
            "Clinician handshake JSON must include in-progress TFI; payload=\(json)"
        )
        XCTAssertTrue(
            store.segmentByHour.isEmpty,
            "Export snapshot must not commit/reset the live hour bucket"
        )
    }

    func testResetForDisconnectPreservesAutomaticSessionRollupsWhilePaused() {
        let deviceManager = DeviceManager(bleService: MockBLEService())
        let recordingManager = RecordingSessionManager()
        let store = SessionHistoryStore()
        store.attach(recordingManager: recordingManager, deviceManager: deviceManager)

        let start = Date(timeIntervalSince1970: 1_000)
        deviceManager.automaticRecordingSession?.onDeviceConnected()
        store.recordTFI(percent: 20, at: start)

        deviceManager.automaticRecordingSession?.onDeviceDisconnected()
        store.resetForDisconnect()
        store.recordTFI(percent: 40, at: start.addingTimeInterval(3_601))

        guard let firstHour = store.segmentByHour[0] else {
            XCTFail("Expected first hour rollup to survive automatic-session disconnect")
            return
        }
        XCTAssertEqual(firstHour.tfiPercent, 20, accuracy: 0.0001)
    }

    func testResetForDisconnectFlushesCurrentHourWhenSessionInactive() {
        let deviceManager = DeviceManager(bleService: MockBLEService())
        let store = SessionHistoryStore()
        store.attach(recordingManager: RecordingSessionManager(), deviceManager: deviceManager)

        let start = Date(timeIntervalSince1970: 5_000)
        deviceManager.automaticRecordingSession?.onDeviceConnected()
        store.recordTFI(percent: 55, at: start)
        deviceManager.automaticRecordingSession?.endSession()
        XCTAssertEqual(deviceManager.automaticRecordingSession?.isSessionActive, false)

        store.resetForDisconnect(at: start.addingTimeInterval(40))

        XCTAssertEqual(store.segmentByHour.count, 1)
        XCTAssertEqual(store.segmentByHour[0]?.tfiPercent, 55, accuracy: 0.001)
    }
}
