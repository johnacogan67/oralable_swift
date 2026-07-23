//
//  OralableDeviceContinuationTests.swift
//  OralableAppTests
//

import Foundation
import XCTest
@testable import OralableApp

@MainActor
final class OralableDeviceContinuationTests: XCTestCase {

    func testWithTimeoutRunsCleanupForStuckBLEContinuation() async {
        let manager = DeviceManager(bleService: MockBLEService())
        let probe = TimeoutCleanupProbe()

        do {
            try await manager.withTimeout(seconds: 0.01, onTimeout: {
                probe.cleanup()
            }) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    probe.store(continuation)
                }
            }
            XCTFail("Expected stuck BLE continuation to time out")
        } catch {
            XCTAssertTrue(probe.didCleanup)
            XCTAssertFalse(probe.hasPendingContinuation)
        }
    }
}

private final class TimeoutCleanupProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var cleanupCalled = false

    var didCleanup: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cleanupCalled
    }

    var hasPendingContinuation: Bool {
        lock.lock()
        defer { lock.unlock() }
        return continuation != nil
    }

    func store(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        guard !Task.isCancelled else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func cleanup() {
        lock.lock()
        cleanupCalled = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(throwing: DeviceError.timeout)
    }
}
