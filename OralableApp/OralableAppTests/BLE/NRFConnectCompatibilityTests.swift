//
//  NRFConnectCompatibilityTests.swift
//  OralableAppTests
//
//  Validates iOS BLE surface matches pcb00003 / nRF Connect baseline (FW 1.0.36+).
//

import XCTest
@testable import OralableApp
import struct OralableCore.BLEDataParser
import enum OralableCore.BLEConstants

final class NRFConnectCompatibilityTests: XCTestCase {

    func testFirmwareGateRequires163() {
        XCTAssertEqual(FirmwareGate.minimumOralableSemanticVersion, "1.0.63")
        XCTAssertEqual(FirmwareGate.recommendedOralableSemanticVersion, "1.0.84")
        XCTAssertFalse(FirmwareGate.isOralableVersionOutdated("1.0.63-nrfconnect"))
        XCTAssertFalse(FirmwareGate.isOralableVersionOutdated("1.0.64"))
        XCTAssertFalse(FirmwareGate.isOralableVersionOutdated("1.0.65-nrfconnect"))
        XCTAssertTrue(FirmwareGate.isOralableVersionOutdated("1.0.62-nrfconnect"))
        XCTAssertTrue(FirmwareGate.supportsPlacementMode("1.0.63-nrfconnect"))
        XCTAssertFalse(FirmwareGate.supportsPlacementMode("1.0.61"))
        XCTAssertFalse(FirmwareGate.supportsAutomaticDockDetect("1.0.66"))
        XCTAssertTrue(FirmwareGate.supportsAutomaticDockDetect("1.0.70-nrfconnect"))
        XCTAssertTrue(FirmwareGate.isBelowRecommendedOralableVersion("1.0.66"))
        XCTAssertTrue(FirmwareGate.isBelowRecommendedOralableVersion("1.0.70"))
        XCTAssertTrue(FirmwareGate.isBelowRecommendedOralableVersion("1.0.71"))
        XCTAssertTrue(FirmwareGate.isBelowRecommendedOralableVersion("1.0.72"))
        XCTAssertTrue(FirmwareGate.isBelowRecommendedOralableVersion("1.0.73"))
        XCTAssertTrue(FirmwareGate.isBelowRecommendedOralableVersion("1.0.82"))
        XCTAssertFalse(FirmwareGate.isBelowRecommendedOralableVersion("1.0.84"))
        XCTAssertFalse(FirmwareGate.isBelowRecommendedOralableVersion("1.0.62"))
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
        XCTAssertFalse(status!.onDock)
        XCTAssertFalse(status!.chargeActive)
        XCTAssertTrue(status!.worn)
        XCTAssertEqual(status!.deviceState, 2)
        XCTAssertEqual(status!.batteryPercent, 75)
    }

    func testParseFirmwareStatusNotifyWithChargeActive() {
        // 5-byte layout: on_dock, worn, device_state, battery_pct, charge_active
        let payload = Data([1, 0, 1, 42, 1])
        let status = BLEDataParser.parseDeviceStatusPacket(payload)
        XCTAssertNotNil(status)
        XCTAssertTrue(status!.onDock)
        XCTAssertTrue(status!.chargeActive)
        XCTAssertFalse(status!.worn)
        XCTAssertEqual(status!.batteryPercent, 42)
    }

    func testValidationLogNotClearedOnScanWhenRecordingActive() {
        let central = BLECentralManager()
        NRFConnectBLELogger.shared.clear()
        NRFConnectBLELogger.shared.connected()
        XCTAssertEqual(NRFConnectBLELogger.shared.lineCount(), 1)

        central.shouldPreserveValidationLog = { true }
        central.startScanning()
        XCTAssertEqual(NRFConnectBLELogger.shared.lineCount(), 1, "Log preserved while recording")

        central.shouldPreserveValidationLog = { false }
        central.startScanning()
        XCTAssertEqual(NRFConnectBLELogger.shared.lineCount(), 0, "Log cleared when not recording")
        NRFConnectBLELogger.shared.clear()
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

    @MainActor
    func testPrepareProtocolBSessionSetsWorn() {
        let flags = FeatureFlags.shared
        flags.devicePlacementMode = .offDockIdle
        flags.protocolBSessionPrepared = false
        let manager = DeviceManager()
        manager.prepareProtocolBSession()
        XCTAssertEqual(flags.devicePlacementMode, .worn)
        XCTAssertTrue(flags.protocolBSessionPrepared)
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
