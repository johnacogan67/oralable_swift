//
//  OralableDeviceContinuationTests.swift
//  OralableAppTests
//

import CoreBluetooth
import XCTest
@testable import OralableApp

@MainActor
final class OralableDeviceContinuationTests: XCTestCase {

    func testCancelPendingContinuationsResumesFirmwareConfigStateRead() async {
        let device = OralableDevice(peripheral: MockCBPeripheral())
        let continuationStored = expectation(description: "Firmware config-state continuation stored")

        let pendingRead = Task { @MainActor in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                device.firmwareConfigStateReadContinuation = continuation
                continuationStored.fulfill()
            }
        }

        await fulfillment(of: [continuationStored], timeout: 1.0)
        device.cancelPendingContinuations()

        do {
            _ = try await pendingRead.value
            XCTFail("Expected cancelPendingContinuations to fail the pending config-state read")
        } catch DeviceError.connectionFailed(let reason) {
            XCTAssertTrue(reason.contains("disconnected"))
            XCTAssertNil(device.firmwareConfigStateReadContinuation)
        } catch {
            XCTFail("Expected connectionFailed, got \(error)")
        }
    }

    func testEnableAccelerometerNotificationsThrowsWhenCharacteristicMissing() async {
        let device = OralableDevice(peripheral: MockCBPeripheral())

        do {
            try await device.enableAccelerometerNotifications()
            XCTFail("Accelerometer notifications are required and should fail when the characteristic is missing")
        } catch DeviceError.characteristicNotFound(let reason) {
            XCTAssertTrue(reason.contains("Accelerometer"))
        } catch {
            XCTFail("Expected characteristicNotFound, got \(error)")
        }
    }
}
