//
//  SessionHistoryStoreTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

@MainActor
final class SessionHistoryStoreTests: XCTestCase {

    func testDisconnectFlushesCurrentHourBeforeReset() throws {
        // Given
        let store = SessionHistoryStore()
        let recordingManager = RecordingSessionManager()
        recordingManager.sessionHistoryStore = store
        store.recordingManager = recordingManager

        let session = try recordingManager.startSession(
            deviceID: "REV10",
            deviceName: "Oralable",
            deviceType: .oralable
        )
        let sampleTime = session.startTime.addingTimeInterval(10)
        store.recordTFI(percent: 73, at: sampleTime)

        // When
        store.resetForDisconnect(at: sampleTime.addingTimeInterval(5))

        // Then
        XCTAssertEqual(store.segmentByHour.count, 1)
        let persisted = try XCTUnwrap(recordingManager.sessions.first { $0.id == session.id })
        let segment = try XCTUnwrap(persisted.hourlyTemporalisSegments?.first)
        XCTAssertEqual(segment.hourIndex, 0)
        XCTAssertEqual(segment.tfiPercent, 73, accuracy: 0.001)
    }
}
