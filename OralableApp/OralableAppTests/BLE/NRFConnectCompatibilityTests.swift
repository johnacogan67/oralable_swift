//
//  NRFConnectCompatibilityTests.swift
//  OralableAppTests
//
//  Validates iOS BLE surface matches pcb00003 / nRF Connect baseline (FW 1.0.36+).
//

import XCTest
@testable import OralableApp
import OralableCore

final class NRFConnectCompatibilityTests: XCTestCase {

    func testFirmwareGateRequires136() {
        XCTAssertEqual(FirmwareGate.minimumOralableSemanticVersion, "1.0.36")
        XCTAssertFalse(FirmwareGate.isOralableVersionOutdated("1.0.36-nrfconnect"))
        XCTAssertFalse(FirmwareGate.isOralableVersionOutdated("1.0.37"))
        XCTAssertTrue(FirmwareGate.isOralableVersionOutdated("1.0.35-nrfconnect"))
    }

    func testTGMBaselineCharacteristicUUIDs() {
        XCTAssertEqual(BLEConstants.TGM.serviceUUID, "3A0FF000-98C4-46B2-94AF-1AEE0FD4C48E")
        XCTAssertEqual(BLEConstants.TGM.statusCharUUID, "3A0FF009-98C4-46B2-94AF-1AEE0FD4C48E")
        XCTAssertTrue(BLEConstants.TGM.nrfConnectCharacteristicUUIDs.contains(BLEConstants.TGM.statusCharUUID))
        XCTAssertTrue(BLEConstants.TGM.allCharacteristicUUIDs.contains(BLEConstants.TGM.statusCharUUID))
    }

    func testParseFirmwareStatusNotify() {
        let payload = Data([0, 1, 2, 75])
        let status = BLEDataParser.parseDeviceStatusPacket(payload)
        XCTAssertNotNil(status)
        XCTAssertFalse(status!.charging)
        XCTAssertTrue(status!.worn)
        XCTAssertEqual(status!.deviceState, 2)
        XCTAssertEqual(status!.batteryPercent, 75)
    }

    func testAutomaticRecordingSessionPauseResumeWindow() {
        let session = AutomaticRecordingSession()
        session.resumeWithinSeconds = 60
        session.onDeviceConnected()
        XCTAssertTrue(session.isSessionActive)
        XCTAssertFalse(session.isSessionPaused)

        session.onDeviceDisconnected()
        XCTAssertTrue(session.isSessionActive)
        XCTAssertTrue(session.isSessionPaused)

        session.onDeviceConnected()
        XCTAssertTrue(session.isSessionActive)
        XCTAssertFalse(session.isSessionPaused)
    }

    func testNRFConnectLoggerMatchesExportHeader() {
        let logger = NRFConnectBLELogger.shared
        logger.clear()
        logger.scannerOn()
        logger.connected()
        XCTAssertTrue(logger.csvContent().hasPrefix("Timestamp,Source,Level,Line\n"))
        logger.clear()
    }

    func testAutomaticRecordingSessionSkipsInferenceOffBody() {
        let session = AutomaticRecordingSession()
        session.onDeviceConnected()
        session.updateFirmwareWornState(false)
        session.processSensorData(irValue: 1_000_000, timestamp: Date())
        XCTAssertEqual(session.eventCount, 1, "Only initial DataStreaming event expected off-body")
    }
}
