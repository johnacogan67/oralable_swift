//
//  SessionHistoryStoreDisconnectTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

@MainActor
final class SessionHistoryStoreDisconnectTests: XCTestCase {

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
}
