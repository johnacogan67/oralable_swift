//
//  AutomaticRecordingExpiredPauseReconnectTests.swift
//  OralableAppTests
//
//  Regression: late reconnect after the auto-session pause window must start a
//  fresh session (DeviceManager.notifyAutomaticRecordingDeviceReady ordering).
//

import XCTest
@testable import OralableApp
import OralableCore

final class AutomaticRecordingExpiredPauseReconnectTests: XCTestCase {

    func testNotifyOrderingEndsExpiredPauseAndStartsFreshSession() {
        let session = AutomaticRecordingSession()
        session.resumeWithinSeconds = 0.05
        session.onDeviceConnected()
        let firstStart = session.sessionStartTime
        XCTAssertNotNil(firstStart)

        session.onDeviceDisconnected()
        XCTAssertTrue(session.isSessionPaused)

        let expired = expectation(description: "pause window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { expired.fulfill() }
        wait(for: [expired], timeout: 1.0)

        // Same ordering as DeviceManager.notifyAutomaticRecordingDeviceReady()
        session.endSessionIfPauseExpired()
        session.onDeviceConnected()

        XCTAssertTrue(session.isSessionActive)
        XCTAssertFalse(session.isSessionPaused)
        XCTAssertNotNil(session.sessionStartTime)
        XCTAssertNotEqual(
            session.sessionStartTime,
            firstStart,
            "Fresh session after expired pause should replace the prior start time"
        )
    }

    func testNotifyOrderingStillResumesInsidePauseWindow() {
        let session = AutomaticRecordingSession()
        session.resumeWithinSeconds = 30
        session.onDeviceConnected()
        let firstStart = session.sessionStartTime

        session.onDeviceDisconnected()
        XCTAssertTrue(session.isSessionPaused)

        session.endSessionIfPauseExpired()
        session.onDeviceConnected()

        XCTAssertTrue(session.isSessionActive)
        XCTAssertFalse(session.isSessionPaused)
        XCTAssertEqual(session.sessionStartTime, firstStart, "In-window reconnect should resume, not restart")
    }
}
