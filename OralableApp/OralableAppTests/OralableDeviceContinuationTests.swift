//
//  OralableDeviceContinuationTests.swift
//  OralableAppTests
//
//  Regression tests for BLE read continuations that must not leak across
//  disconnects or invalid CoreBluetooth read callbacks.
//

import CoreBluetooth
import XCTest
@testable import OralableApp

@MainActor
final class OralableDeviceContinuationTests: XCTestCase {

    func testCancelPendingContinuationsCancelsFirmwareConfigStateRead() async {
        let device = OralableDevice(peripheral: MockCBPeripheral())
        let started = expectation(description: "Firmware config-state read started")
        let completed = expectation(description: "Firmware config-state read completed")
        var result: Result<Data, Error>?

        let task = Task { @MainActor in
            do {
                let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    device.firmwareConfigStateReadContinuation = continuation
                    started.fulfill()
                }
                result = .success(data)
            } catch {
                result = .failure(error)
            }
            completed.fulfill()
        }

        await fulfillment(of: [started], timeout: 1.0)
        device.cancelPendingContinuations()
        await fulfillment(of: [completed], timeout: 1.0)
        task.cancel()

        guard case .failure(let error)? = result else {
            return XCTFail("Expected firmware config-state read to throw on disconnect")
        }
        guard case DeviceError.connectionFailed = error else {
            return XCTFail("Expected connectionFailed, got \(error)")
        }
        XCTAssertNil(device.firmwareConfigStateReadContinuation)
    }

    func testNilFirmwareConfigStateValueFailsPendingRead() async {
        let peripheral = MockCBPeripheral()
        let device = OralableDevice(peripheral: peripheral)
        let characteristic = CBMutableCharacteristic(
            type: device.firmwareConfigStateCharUUID,
            properties: .read,
            value: nil,
            permissions: .readable
        )
        let started = expectation(description: "Firmware config-state read started")
        let completed = expectation(description: "Firmware config-state read completed")
        var result: Result<Data, Error>?

        let task = Task { @MainActor in
            do {
                let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    device.firmwareConfigStateReadContinuation = continuation
                    started.fulfill()
                }
                result = .success(data)
            } catch {
                result = .failure(error)
            }
            completed.fulfill()
        }

        await fulfillment(of: [started], timeout: 1.0)
        let delegate = device as CBPeripheralDelegate
        delegate.peripheral?(peripheral, didUpdateValueFor: characteristic, error: nil)
        await fulfillment(of: [completed], timeout: 1.0)
        task.cancel()

        guard case .failure(let error)? = result else {
            return XCTFail("Expected nil firmware config-state read to throw")
        }
        guard case DeviceError.invalidData = error else {
            return XCTFail("Expected invalidData, got \(error)")
        }
        XCTAssertNil(device.firmwareConfigStateReadContinuation)
    }
}
