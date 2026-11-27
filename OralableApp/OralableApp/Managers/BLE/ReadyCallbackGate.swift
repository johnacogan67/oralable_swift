//
//  ReadyCallbackGate.swift
//  OralableApp
//
//  Serial gate for "run this once Bluetooth is powered on".
//  The check, the enqueue, and the flush share one queue so a ready
//  transition cannot drain the list between the check and the append.
//

import Foundation

/// Callbacks waiting on a readiness flag.
///
/// `whenReady` used to read `isReady` on the main thread and append on that
/// same thread, while `centralManagerDidUpdateState` flushed the list on the
/// CoreBluetooth queue. Those two steps could pass each other: powered-on
/// flushed an empty list, then the callback was appended and never run.
/// Auto-reconnect sets `autoReconnectInFlight` before `whenReady`, so one
/// lost callback also made later foreground retries return immediately.
final class ReadyCallbackGate {
    private let queue: DispatchQueue
    private var pending: [() -> Void] = []
    private var isReady: Bool

    init(queue: DispatchQueue, isReady: Bool = false) {
        self.queue = queue
        self.isReady = isReady
    }

    /// Run `operation` now if already ready, otherwise keep it until `setReady(true)`.
    /// The operation runs on `queue`, not on the caller.
    func whenReady(_ operation: @escaping () -> Void) {
        queue.async {
            if self.isReady {
                operation()
            } else {
                self.pending.append(operation)
                Logger.shared.info("[BLECentralManager] ⏳ Operation queued - waiting for Bluetooth to power on")
            }
        }
    }

    /// Update readiness. Safe to call from the CoreBluetooth delegate queue or any other queue.
    func setReady(_ ready: Bool) {
        queue.async {
            let wasReady = self.isReady
            self.isReady = ready
            guard ready else { return }
            let ops = self.pending
            self.pending.removeAll()
            if !wasReady || !ops.isEmpty {
                Logger.shared.info("[BLECentralManager] ✅ Executing \(ops.count) pending operation(s)")
            }
            for op in ops {
                op()
            }
        }
    }

    /// How many callbacks are still waiting. For tests.
    func pendingCountForTesting() -> Int {
        queue.sync { pending.count }
    }
}
