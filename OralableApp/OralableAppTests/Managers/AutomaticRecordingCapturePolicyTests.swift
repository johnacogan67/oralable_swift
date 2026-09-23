//
//  AutomaticRecordingCapturePolicyTests.swift
//  OralableAppTests
//
//  Guards multi-device disconnect from pausing overnight automatic recording
// while a ready Oralable clinical source remains connected.
//

import XCTest
import OralableCore
@testable import OralableApp

final class AutomaticRecordingCapturePolicyTests: XCTestCase {

    private func oralable(id: UUID, name: String = "Oralable") -> DeviceInfo {
        DeviceInfo(type: .oralable, name: name, peripheralIdentifier: id)
    }

    private func anr(id: UUID) -> DeviceInfo {
        DeviceInfo(type: .anr, name: "ANR M40", peripheralIdentifier: id)
    }

    func testSecondaryANRDisconnectKeepsSessionWhenOralableReady() {
        let oralableId = UUID()
        let anrId = UUID()
        // After ANR is removed from connectedDevices, only Oralable remains ready.
        let remaining = [oralable(id: oralableId)]
        let readiness: [UUID: ConnectionReadiness] = [
            oralableId: .ready,
            anrId: .disconnected
        ]

        XCTAssertTrue(
            AutomaticRecordingCapturePolicy.hasReadyOralable(
                connectedDevices: remaining,
                readiness: readiness
            ),
            "Secondary ANR drop must not pause while Oralable is ready"
        )
    }

    func testLastOralableDisconnectPausesSessionEvenIfANRRemains() {
        let anrId = UUID()
        let remaining = [anr(id: anrId)]
        let readiness: [UUID: ConnectionReadiness] = [anrId: .ready]

        XCTAssertFalse(
            AutomaticRecordingCapturePolicy.hasReadyOralable(
                connectedDevices: remaining,
                readiness: readiness
            ),
            "ANR-only readiness is not clinical Oralable capture"
        )
    }

    func testSecondaryOralableDisconnectKeepsSessionWhenPrimaryOralableReady() {
        let primaryId = UUID()
        let secondaryId = UUID()
        let remaining = [oralable(id: primaryId, name: "Oralable-A")]
        let readiness: [UUID: ConnectionReadiness] = [
            primaryId: .ready,
            secondaryId: .disconnected
        ]

        XCTAssertTrue(
            AutomaticRecordingCapturePolicy.hasReadyOralable(
                connectedDevices: remaining,
                readiness: readiness
            )
        )
    }

    func testNoConnectedDevicesPausesSession() {
        XCTAssertFalse(
            AutomaticRecordingCapturePolicy.hasReadyOralable(
                connectedDevices: [],
                readiness: [:]
            )
        )
    }

    func testOralableConnectedButNotReadyDoesNotCount() {
        let oralableId = UUID()
        let remaining = [oralable(id: oralableId)]
        let readiness: [UUID: ConnectionReadiness] = [
            oralableId: .discoveringServices
        ]

        XCTAssertFalse(
            AutomaticRecordingCapturePolicy.hasReadyOralable(
                connectedDevices: remaining,
                readiness: readiness
            )
        )
    }

    func testOnlyOralableDeviceTypeStartsOrResumesSession() {
        XCTAssertTrue(AutomaticRecordingCapturePolicy.shouldStartOrResume(for: .oralable))
        XCTAssertFalse(AutomaticRecordingCapturePolicy.shouldStartOrResume(for: .anr))
    }

    @MainActor
    func testSyncAutomaticRecordingAfterDisconnectSkipsPauseWhenOralableReady() {
        let manager = DeviceManager()
        let session = manager.automaticRecordingSession
        XCTAssertNotNil(session)

        session?.onDeviceConnected()
        XCTAssertEqual(session?.isSessionActive, true)
        XCTAssertEqual(session?.isSessionPaused, false)

        let oralableId = UUID()
        manager.connectedDevices = [oralable(id: oralableId)]
        manager.deviceReadiness = [oralableId: .ready]

        manager.syncAutomaticRecordingAfterDisconnect()

        XCTAssertEqual(session?.isSessionActive, true)
        XCTAssertEqual(session?.isSessionPaused, false, "Must not pause while Oralable remains ready")
    }

    @MainActor
    func testSyncAutomaticRecordingAfterDisconnectPausesWhenNoOralableReady() {
        let manager = DeviceManager()
        let session = manager.automaticRecordingSession
        XCTAssertNotNil(session)

        session?.onDeviceConnected()
        XCTAssertEqual(session?.isSessionActive, true)
        XCTAssertEqual(session?.isSessionPaused, false)

        let anrId = UUID()
        manager.connectedDevices = [anr(id: anrId)]
        manager.deviceReadiness = [anrId: .ready]

        manager.syncAutomaticRecordingAfterDisconnect()

        XCTAssertEqual(session?.isSessionActive, true)
        XCTAssertEqual(session?.isSessionPaused, true, "Must pause when last Oralable is gone")
    }
}
