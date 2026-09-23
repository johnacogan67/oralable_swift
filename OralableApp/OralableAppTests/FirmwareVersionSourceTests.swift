//
//  FirmwareVersionSourceTests.swift
//  OralableAppTests
//
//  Settings labels a remembered GATT string as the last connection.
//

import XCTest
import CoreBluetooth
@testable import OralableApp

@MainActor
final class FirmwareVersionSourceTests: XCTestCase {

    func testRememberedFirmwareIsMarkedFromLastConnection() {
        let sut = DeviceManager(bleService: MockBLEService(bluetoothState: .poweredOn))

        XCTAssertNil(sut.primaryFirmwareVersion())
        XCTAssertFalse(sut.firmwareVersionIsFromLastConnection)

        sut.setPrimaryDevice(
            DeviceInfo(
                type: .oralable,
                name: "MAM",
                peripheralIdentifier: UUID(),
                firmwareVersion: "  1.0.84  "
            )
        )

        XCTAssertEqual(sut.primaryFirmwareVersion(), "1.0.84")
        XCTAssertTrue(
            sut.firmwareVersionIsFromLastConnection,
            "No live Oralable GATT read — Settings must label this as the last connection"
        )

        sut.setPrimaryDevice(
            DeviceInfo(
                type: .oralable,
                name: "MAM",
                peripheralIdentifier: UUID(),
                firmwareVersion: "   "
            )
        )
        XCTAssertNil(sut.primaryFirmwareVersion())
        XCTAssertFalse(sut.firmwareVersionIsFromLastConnection)
    }
}
