//
//  PrimaryDeviceSlotPolicyTests.swift
//  OralableAppTests
//

import XCTest
import OralableCore
@testable import OralableApp

@MainActor
final class PrimaryDeviceSlotPolicyTests: XCTestCase {

    func testDisconnectDoesNotPromoteANRToPrimary() {
        let oralableId = UUID()
        let anrId = UUID()
        let oralable = device(id: oralableId, type: .oralable, name: "Oralable")
        let anr = device(id: anrId, type: .anr, name: "ANR M40")

        let next = PrimaryDeviceSlotPolicy.primaryAfterDisconnect(
            disconnectedPeripheralId: oralableId,
            connectedDevices: [anr],
            currentPrimary: oralable
        )

        XCTAssertNil(next)
        XCTAssertFalse(
            PrimaryDeviceSlotPolicy.shouldClearSleepCalibration(
                storedPeripheralId: oralableId,
                primary: next
            )
        )
    }

    func testDisconnectKeepsOtherOralableAsPrimary() {
        let droppedId = UUID()
        let otherId = UUID()
        let dropped = device(id: droppedId, type: .oralable, name: "Oralable A")
        let other = device(id: otherId, type: .oralable, name: "Oralable B")
        let anr = device(id: UUID(), type: .anr, name: "ANR M40")

        let next = PrimaryDeviceSlotPolicy.primaryAfterDisconnect(
            disconnectedPeripheralId: droppedId,
            connectedDevices: [anr, other],
            currentPrimary: dropped
        )

        XCTAssertEqual(next?.peripheralIdentifier, otherId)
        XCTAssertTrue(
            PrimaryDeviceSlotPolicy.shouldClearSleepCalibration(
                storedPeripheralId: droppedId,
                primary: next
            )
        )
    }

    func testSecondaryDisconnectLeavesPrimaryUntouched() {
        let oralableId = UUID()
        let anrId = UUID()
        let oralable = device(id: oralableId, type: .oralable, name: "Oralable")
        let anr = device(id: anrId, type: .anr, name: "ANR M40")

        let next = PrimaryDeviceSlotPolicy.primaryAfterDisconnect(
            disconnectedPeripheralId: anrId,
            connectedDevices: [oralable],
            currentPrimary: oralable
        )

        XCTAssertEqual(next?.peripheralIdentifier, oralableId)
    }

    func testOralableConnectReclaimsSlotFromANR() {
        let anr = device(id: UUID(), type: .anr, name: "ANR M40")
        let oralableId = UUID()
        let oralable = device(id: oralableId, type: .oralable, name: "Oralable")

        let next = PrimaryDeviceSlotPolicy.primaryAfterConnect(
            candidate: oralable,
            currentPrimary: anr
        )

        XCTAssertEqual(next?.peripheralIdentifier, oralableId)
        XCTAssertFalse(
            PrimaryDeviceSlotPolicy.shouldClearSleepCalibration(
                storedPeripheralId: oralableId,
                primary: anr
            )
        )
    }

    func testANRConnectDoesNotReplaceOralablePrimary() {
        let oralableId = UUID()
        let oralable = device(id: oralableId, type: .oralable, name: "Oralable")
        let anr = device(id: UUID(), type: .anr, name: "ANR M40")

        let next = PrimaryDeviceSlotPolicy.primaryAfterConnect(
            candidate: anr,
            currentPrimary: oralable
        )

        XCTAssertEqual(next?.peripheralIdentifier, oralableId)
    }

    func testSleepGateKeepsCalibrationWhenPrimaryIsANR() {
        let store = SessionHistoryStore()
        let oralableId = UUID()
        store.recordTemporalisSleepCalibration(
            calibrationId: UUID(),
            baselineVoltage: 1.2,
            peripheralId: oralableId
        )
        defer { store.clearTemporalisSleepCalibration() }

        store.applyPrimaryDeviceForSleepGate(
            primary: device(id: UUID(), type: .anr, name: "ANR M40")
        )
        XCTAssertEqual(store.temporalisSleepCalibration?.peripheralId, oralableId)

        store.applyPrimaryDeviceForSleepGate(primary: nil)
        XCTAssertEqual(store.temporalisSleepCalibration?.peripheralId, oralableId)

        store.applyPrimaryDeviceForSleepGate(
            primary: device(id: UUID(), type: .oralable, name: "Other Oralable")
        )
        XCTAssertNil(store.temporalisSleepCalibration)
    }

    private func device(id: UUID, type: DeviceType, name: String) -> DeviceInfo {
        DeviceInfo(
            id: id,
            type: type,
            name: name,
            peripheralIdentifier: id,
            connectionState: .connected
        )
    }
}
