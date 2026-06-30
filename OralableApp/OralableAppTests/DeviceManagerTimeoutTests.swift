//
//  DeviceManagerTimeoutTests.swift
//  OralableAppTests
//

import XCTest
@testable import OralableApp

@MainActor
final class DeviceManagerTimeoutTests: XCTestCase {

    func testWithTimeoutRunsCleanupWhenOperationTimesOut() async {
        let manager = DeviceManager(bleService: MockBLEService())
        var cleanupCount = 0

        do {
            let _: Void = try await manager.withTimeout(seconds: 0.01, onTimeout: {
                cleanupCount += 1
            }) {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }

            XCTFail("Expected timeout")
        } catch let error as DeviceError {
            if case .timeout = error {
                XCTAssertEqual(cleanupCount, 1)
            } else {
                XCTFail("Expected timeout, got \(error)")
            }
        } catch {
            XCTFail("Expected DeviceError.timeout, got \(error)")
        }
    }
}
