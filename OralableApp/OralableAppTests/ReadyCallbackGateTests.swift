//
//  ReadyCallbackGateTests.swift
//  OralableAppTests
//
//  A powered-on transition must not drop a callback that is enqueued in the
//  same window, and must not run that callback twice.
//

import XCTest
@testable import OralableApp

final class ReadyCallbackGateTests: XCTestCase {

    func testCallbackWaitsUntilReadyThenRunsOnce() {
        let gate = ReadyCallbackGate(queue: DispatchQueue(label: "ready-gate-wait"), isReady: false)
        let runs = Counter()
        gate.whenReady { runs.increment() }

        let queued = expectation(description: "callback is waiting")
        poll(timeout: 2) {
            gate.pendingCountForTesting() == 1
        } done: {
            queued.fulfill()
        }
        wait(for: [queued], timeout: 2)
        XCTAssertEqual(gate.pendingCountForTesting(), 1)
        XCTAssertEqual(runs.value, 0)

        gate.setReady(true)
        gate.setReady(true)

        let ran = expectation(description: "callback ran once")
        poll(timeout: 2) {
            runs.value == 1 && gate.pendingCountForTesting() == 0
        } done: {
            ran.fulfill()
        }
        wait(for: [ran], timeout: 2)
        XCTAssertEqual(runs.value, 1)
        XCTAssertEqual(gate.pendingCountForTesting(), 0)
    }

    func testCallbackAfterReadyRunsWithoutParking() {
        let gate = ReadyCallbackGate(queue: DispatchQueue(label: "ready-gate-immediate"), isReady: false)
        gate.setReady(true)

        let ran = expectation(description: "callback ran")
        gate.whenReady { ran.fulfill() }
        wait(for: [ran], timeout: 2)
        XCTAssertEqual(gate.pendingCountForTesting(), 0)
    }

    func testConcurrentEnqueueAroundReadyDoesNotDropOrDoubleRun() {
        let gate = ReadyCallbackGate(queue: DispatchQueue(label: "ready-gate-race"), isReady: false)
        let count = 80
        let counter = Counter()
        let done = expectation(description: "every callback ran once")
        done.expectedFulfillmentCount = count

        DispatchQueue.concurrentPerform(iterations: count) { index in
            if index == 0 {
                gate.setReady(true)
            }
            gate.whenReady {
                counter.increment()
                done.fulfill()
            }
        }

        wait(for: [done], timeout: 5)
        XCTAssertEqual(counter.value, count)
        XCTAssertEqual(gate.pendingCountForTesting(), 0)
    }

    private func poll(timeout: TimeInterval, until condition: @escaping () -> Bool, done: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func check() {
            if condition() || Date() > deadline {
                done()
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.01, execute: check)
        }
        check()
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
