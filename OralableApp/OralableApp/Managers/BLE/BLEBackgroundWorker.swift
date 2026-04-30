//
//  BLEBackgroundWorker.swift
//  OralableApp
//
//  Created: December 15, 2025
//  Purpose: Dedicated worker for background BLE tasks including reconnection,
//  RSSI polling, and connection health monitoring
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - Background Worker Configuration

/// Configuration for BLEBackgroundWorker behavior
struct BLEBackgroundWorkerConfig {
    /// Maximum number of reconnection attempts before giving up
    var maxReconnectionAttempts: Int = 3

    /// Base delay for exponential backoff (in seconds)
    var baseReconnectionDelay: TimeInterval = 2.0

    /// Maximum reconnection delay cap (in seconds)
    var maxReconnectionDelay: TimeInterval = 30.0

    /// Jitter factor (0.0-1.0) to randomize delays and prevent thundering herd
    var jitterFactor: Double = 0.25

    /// Timeout for each connection attempt (in seconds)
    var connectionTimeout: TimeInterval = 15.0

    /// Interval for RSSI polling (in seconds)
    var rssiPollingInterval: TimeInterval = 5.0

    /// Interval for connection health checks (in seconds)
    var healthCheckInterval: TimeInterval = 10.0

    /// Timeout for considering a connection stale (in seconds)
    var connectionStaleTimeout: TimeInterval = 30.0

    /// Whether to auto-reconnect on unexpected disconnection
    var autoReconnectEnabled: Bool = true

    /// Whether to pause reconnection when Bluetooth is off
    var pauseOnBluetoothOff: Bool = true

    /// Default configuration
    static let `default` = BLEBackgroundWorkerConfig()

    /// Aggressive reconnection configuration
    static let aggressive = BLEBackgroundWorkerConfig(
        maxReconnectionAttempts: 5,
        baseReconnectionDelay: 1.0,
        maxReconnectionDelay: 15.0,
        jitterFactor: 0.1,
        connectionTimeout: 10.0
    )

    /// Conservative configuration (battery saving)
    static let conservative = BLEBackgroundWorkerConfig(
        maxReconnectionAttempts: 2,
        baseReconnectionDelay: 5.0,
        jitterFactor: 0.3,
        connectionTimeout: 20.0,
        rssiPollingInterval: 15.0,
        healthCheckInterval: 30.0
    )
}

// MARK: - Reconnection Callback Protocol

/// Protocol for receiving reconnection callbacks
/// Alternative to Combine publisher for simpler integration
protocol BLEReconnectionDelegate: AnyObject {
    /// Called when a reconnection attempt starts
    func reconnectionDidStart(for peripheralId: UUID, attempt: Int, maxAttempts: Int, nextRetryDelay: TimeInterval)

    /// Called when reconnection succeeds
    func reconnectionDidSucceed(for peripheralId: UUID, afterAttempts: Int)

    /// Called when a single reconnection attempt fails
    func reconnectionAttemptDidFail(for peripheralId: UUID, attempt: Int, error: Error?, willRetry: Bool)

    /// Called when all reconnection attempts are exhausted
    func reconnectionDidGiveUp(for peripheralId: UUID, totalAttempts: Int, lastError: Error?)
}

/// Default empty implementations for optional methods
extension BLEReconnectionDelegate {
    func reconnectionDidStart(for peripheralId: UUID, attempt: Int, maxAttempts: Int, nextRetryDelay: TimeInterval) {}
    func reconnectionAttemptDidFail(for peripheralId: UUID, attempt: Int, error: Error?, willRetry: Bool) {}
}

// MARK: - Background Worker Events

/// Events emitted by the background worker
enum BLEBackgroundWorkerEvent {
    case reconnectionAttemptStarted(peripheralId: UUID, attempt: Int, maxAttempts: Int)
    case reconnectionSucceeded(peripheralId: UUID)
    case reconnectionFailed(peripheralId: UUID, error: Error?)
    case reconnectionGaveUp(peripheralId: UUID, totalAttempts: Int)
    case rssiUpdated(peripheralId: UUID, rssi: Int)
    case connectionHealthWarning(peripheralId: UUID, reason: String)
    case connectionStale(peripheralId: UUID)
    case workerStarted
    case workerStopped
}

// MARK: - Reconnection State

/// State tracking for a single device's reconnection
private struct ReconnectionState {
    let peripheralId: UUID
    var attemptCount: Int = 0
    var lastAttemptTime: Date?
    var peripheral: CBPeripheral?
    var task: Task<Void, Never>?
    var isActive: Bool = false

    mutating func incrementAttempt() {
        attemptCount += 1
        lastAttemptTime = Date()
    }

    mutating func reset() {
        attemptCount = 0
        lastAttemptTime = nil
        peripheral = nil
        task?.cancel()
        task = nil
        isActive = false
    }
}

// MARK: - BLE Background Worker

/// Dedicated worker for handling background BLE tasks
/// Manages reconnection with exponential backoff, RSSI polling, and connection health monitoring
@MainActor
final class BLEBackgroundWorker: ObservableObject {

    // MARK: - Published State

    /// Whether the worker is currently running
    @Published private(set) var isRunning: Bool = false

    /// Active reconnection states by peripheral ID
    @Published private(set) var activeReconnections: Set<UUID> = []

    /// Latest RSSI values by peripheral ID
    @Published private(set) var rssiValues: [UUID: Int] = [:]

    /// Connection health status by peripheral ID
    @Published private(set) var connectionHealth: [UUID: ConnectionHealthStatus] = [:]

    // MARK: - Event Publisher

    /// Publisher for background worker events
    var eventPublisher: AnyPublisher<BLEBackgroundWorkerEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    private weak var bleService: BLEService?
    private let config: BLEBackgroundWorkerConfig

    /// Delegate for reconnection callbacks (alternative to Combine publisher)
    weak var reconnectionDelegate: BLEReconnectionDelegate?

    // MARK: - Internal State

    private var reconnectionStates: [UUID: ReconnectionState] = [:]
    private var rssiPollingTask: Task<Void, Never>?
    private var healthCheckTask: Task<Void, Never>?
    private var lastDataReceived: [UUID: Date] = [:]
    private var bleServiceEventCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private let eventSubject = PassthroughSubject<BLEBackgroundWorkerEvent, Never>()

    /// Peripherals waiting for Bluetooth to become ready before reconnection
    private var pendingReconnectionPeripherals: [UUID: CBPeripheral] = [:]

    /// Timeout tasks for connection attempts (to cancel on success)
    private var connectionTimeoutTasks: [UUID: Task<Void, Never>] = [:]

    #if DEBUG
    /// Throttle noisy link-quality debug lines (per peripheral).
    private var linkQualityLastDebugLogAt: [UUID: Date] = [:]
    #endif

    // MARK: - Async Streams

    /// Async stream for reconnection events
    var reconnectionEvents: AsyncStream<BLEBackgroundWorkerEvent> {
        AsyncStream { continuation in
            let cancellable = eventPublisher
                .filter { event in
                    switch event {
                    case .reconnectionAttemptStarted, .reconnectionSucceeded,
                         .reconnectionFailed, .reconnectionGaveUp:
                        return true
                    default:
                        return false
                    }
                }
                .sink { event in
                    continuation.yield(event)
                }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    /// Async stream for RSSI updates
    var rssiUpdates: AsyncStream<(UUID, Int)> {
        AsyncStream { continuation in
            let cancellable = eventPublisher
                .compactMap { event -> (UUID, Int)? in
                    if case .rssiUpdated(let id, let rssi) = event {
                        return (id, rssi)
                    }
                    return nil
                }
                .sink { value in
                    continuation.yield(value)
                }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    // MARK: - Initialization

    init(bleService: BLEService? = nil, config: BLEBackgroundWorkerConfig = .default) {
        self.bleService = bleService
        self.config = config
        Logger.shared.info("[BLEBackgroundWorker] Initialized with config: maxAttempts=\(config.maxReconnectionAttempts), baseDelay=\(config.baseReconnectionDelay)s")
    }

    /// Configure the BLE service (for dependency injection)
    func configure(bleService: BLEService) {
        self.bleService = bleService
        setupEventSubscription()
    }

    // MARK: - Lifecycle

    /// Start the background worker
    func start() {
        guard !isRunning else {
            Logger.shared.debug("[BLEBackgroundWorker] Already running, ignoring start request")
            return
        }

        Logger.shared.info("[BLEBackgroundWorker] Starting...")
        isRunning = true
        setupEventSubscription()
        startHealthCheckLoop()
        eventSubject.send(.workerStarted)
    }

    /// Stop the background worker
    func stop() {
        guard isRunning else { return }

        Logger.shared.info("[BLEBackgroundWorker] Stopping...")
        isRunning = false

        // Cancel all reconnection tasks
        for (_, state) in reconnectionStates {
            state.task?.cancel()
        }
        reconnectionStates.removeAll()
        activeReconnections.removeAll()

        // Cancel timeout tasks
        for (_, task) in connectionTimeoutTasks {
            task.cancel()
        }
        connectionTimeoutTasks.removeAll()

        // Clear pending reconnections
        pendingReconnectionPeripherals.removeAll()

        // Cancel polling tasks
        rssiPollingTask?.cancel()
        rssiPollingTask = nil
        healthCheckTask?.cancel()
        healthCheckTask = nil

        // Clear subscriptions
        bleServiceEventCancellable?.cancel()
        bleServiceEventCancellable = nil
        cancellables.removeAll()

        eventSubject.send(.workerStopped)
    }

    // MARK: - Reconnection Management

    /// Schedule a reconnection attempt for a peripheral
    /// - Parameters:
    ///   - peripheralId: The peripheral identifier
    ///   - peripheral: The CBPeripheral to reconnect to
    ///   - immediate: Whether to attempt immediately (skip initial delay)
    func scheduleReconnection(for peripheralId: UUID, peripheral: CBPeripheral, immediate: Bool = false) {
        guard config.autoReconnectEnabled else {
            Logger.shared.debug("[BLEBackgroundWorker] Auto-reconnect disabled, skipping")
            return
        }

        guard isRunning else {
            Logger.shared.warning("[BLEBackgroundWorker] Worker not running, cannot schedule reconnection")
            return
        }

        // Check Bluetooth state if configured to pause when BT is off
        if config.pauseOnBluetoothOff, let bleService = bleService, !bleService.isReady {
            Logger.shared.warning("[BLEBackgroundWorker] Bluetooth not ready, deferring reconnection for \(peripheralId)")
            // Store the peripheral for later reconnection when BT comes back
            pendingReconnectionPeripherals[peripheralId] = peripheral
            return
        }

        // Check if already reconnecting
        if reconnectionStates[peripheralId]?.isActive == true {
            Logger.shared.debug("[BLEBackgroundWorker] Already reconnecting to \(peripheralId)")
            return
        }

        // Initialize or get existing state
        var state = reconnectionStates[peripheralId] ?? ReconnectionState(peripheralId: peripheralId)
        state.peripheral = peripheral

        // Check max attempts
        guard state.attemptCount < config.maxReconnectionAttempts else {
            Logger.shared.warning("[BLEBackgroundWorker] Max reconnection attempts reached for \(peripheralId)")
            let totalAttempts = state.attemptCount
            let maxAttemptsError = BLEError.maxReconnectionAttemptsExceeded(
                peripheralId: peripheralId,
                attempts: totalAttempts
            )
            logBLEError(maxAttemptsError, context: "scheduleReconnection")
            eventSubject.send(.reconnectionGaveUp(peripheralId: peripheralId, totalAttempts: totalAttempts))
            reconnectionDelegate?.reconnectionDidGiveUp(for: peripheralId, totalAttempts: totalAttempts, lastError: maxAttemptsError)
            reconnectionStates[peripheralId]?.reset()
            activeReconnections.remove(peripheralId)
            return
        }

        state.isActive = true
        state.incrementAttempt()
        activeReconnections.insert(peripheralId)

        // Calculate delay with exponential backoff and jitter
        let delay: TimeInterval
        if immediate && state.attemptCount == 1 {
            delay = 0
        } else {
            let exponentialDelay = config.baseReconnectionDelay * pow(2.0, Double(state.attemptCount - 1))
            let cappedDelay = min(exponentialDelay, config.maxReconnectionDelay)
            // Apply jitter: delay * (1 ± jitterFactor)
            let jitter = cappedDelay * config.jitterFactor * Double.random(in: -1...1)
            delay = max(0, cappedDelay + jitter)
        }

        Logger.shared.info("[BLEBackgroundWorker] Scheduling reconnection #\(state.attemptCount) for \(peripheralId) in \(String(format: "%.2f", delay))s (with jitter)")

        eventSubject.send(.reconnectionAttemptStarted(
            peripheralId: peripheralId,
            attempt: state.attemptCount,
            maxAttempts: config.maxReconnectionAttempts
        ))

        // Notify delegate
        reconnectionDelegate?.reconnectionDidStart(
            for: peripheralId,
            attempt: state.attemptCount,
            maxAttempts: config.maxReconnectionAttempts,
            nextRetryDelay: delay
        )

        // Create reconnection task with timeout
        let currentAttempt = state.attemptCount
        let timeout = config.connectionTimeout
        state.task = Task { [weak self] in
            guard let self = self else { return }

            // Wait for delay
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    // Task was cancelled
                    return
                }
            }

            // Check if still active and Bluetooth is ready
            guard !Task.isCancelled, self.isRunning else { return }

            // Double-check Bluetooth state before attempting
            if self.config.pauseOnBluetoothOff, let bleService = self.bleService, !bleService.isReady {
                Logger.shared.warning("[BLEBackgroundWorker] Bluetooth off before reconnection attempt, deferring")
                self.pendingReconnectionPeripherals[peripheralId] = peripheral
                self.reconnectionStates[peripheralId]?.isActive = false
                return
            }

            Logger.shared.info("[BLEBackgroundWorker] Attempting reconnection #\(currentAttempt) to \(peripheralId) (timeout: \(timeout)s)")

            // Attempt connection with timeout
            self.bleService?.connect(to: peripheral)

            // Replace any prior watchdog for this peripheral (defensive — avoids orphaned timers).
            self.connectionTimeoutTasks[peripheralId]?.cancel()

            // Start timeout task
            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    // Timeout expired - check if still waiting for connection
                    if self.reconnectionStates[peripheralId]?.isActive == true {
                        Logger.shared.warning("[BLEBackgroundWorker] Connection timeout for \(peripheralId)")
                        await self.handleReconnectionTimeout(for: peripheralId, peripheral: peripheral, attempt: currentAttempt)
                    }
                } catch {
                    // Timeout task cancelled (connection succeeded or was cancelled)
                }
            }

            // Store timeout task reference for cancellation on success
            self.connectionTimeoutTasks[peripheralId] = timeoutTask
        }

        reconnectionStates[peripheralId] = state
    }

    /// Handle reconnection timeout
    private func handleReconnectionTimeout(for peripheralId: UUID, peripheral: CBPeripheral, attempt: Int) {
        let willRetry = (reconnectionStates[peripheralId]?.attemptCount ?? 0) < config.maxReconnectionAttempts

        // Cancel the pending connection
        bleService?.disconnect(from: peripheral)

        // Create structured BLEError for timeout
        let timeoutError = BLEError.connectionTimeout(
            peripheralId: peripheralId,
            timeoutSeconds: config.connectionTimeout
        )

        // Log error with severity
        logBLEError(timeoutError, context: "handleReconnectionTimeout")

        reconnectionDelegate?.reconnectionAttemptDidFail(
            for: peripheralId,
            attempt: attempt,
            error: timeoutError,
            willRetry: willRetry
        )
        eventSubject.send(.reconnectionFailed(peripheralId: peripheralId, error: timeoutError))

        // Schedule next attempt if allowed
        if willRetry {
            reconnectionStates[peripheralId]?.isActive = false
            scheduleReconnection(for: peripheralId, peripheral: peripheral, immediate: false)
        } else {
            Logger.shared.error("[BLEBackgroundWorker] Giving up on \(peripheralId) after \(attempt) attempts")
            reconnectionDelegate?.reconnectionDidGiveUp(for: peripheralId, totalAttempts: attempt, lastError: timeoutError)
            eventSubject.send(.reconnectionGaveUp(peripheralId: peripheralId, totalAttempts: attempt))
            reconnectionStates[peripheralId]?.reset()
            activeReconnections.remove(peripheralId)
        }
    }

    /// Cancel reconnection attempts for a peripheral
    func cancelReconnection(for peripheralId: UUID) {
        guard var state = reconnectionStates[peripheralId] else { return }

        Logger.shared.info("[BLEBackgroundWorker] Cancelling reconnection for \(peripheralId)")
        state.reset()
        reconnectionStates[peripheralId] = state
        activeReconnections.remove(peripheralId)
    }

    /// Cancel all ongoing reconnection attempts
    func cancelAllReconnections() {
        Logger.shared.info("[BLEBackgroundWorker] Cancelling all reconnections")
        for peripheralId in reconnectionStates.keys {
            reconnectionStates[peripheralId]?.reset()
        }
        reconnectionStates.removeAll()
        activeReconnections.removeAll()

        // Cancel all timeout tasks
        for (_, task) in connectionTimeoutTasks {
            task.cancel()
        }
        connectionTimeoutTasks.removeAll()

        // Clear pending reconnections
        pendingReconnectionPeripherals.removeAll()
    }

    /// Handle successful connection (resets reconnection state)
    func handleConnectionSuccess(for peripheralId: UUID) {
        // Cancel any pending timeout task
        connectionTimeoutTasks[peripheralId]?.cancel()
        connectionTimeoutTasks.removeValue(forKey: peripheralId)

        // Remove from pending reconnections if it was waiting for BT
        pendingReconnectionPeripherals.removeValue(forKey: peripheralId)

        if reconnectionStates[peripheralId]?.isActive == true {
            let attempts = reconnectionStates[peripheralId]?.attemptCount ?? 1
            Logger.shared.info("[BLEBackgroundWorker] Reconnection succeeded for \(peripheralId) after \(attempts) attempt(s)")
            eventSubject.send(.reconnectionSucceeded(peripheralId: peripheralId))
            reconnectionDelegate?.reconnectionDidSucceed(for: peripheralId, afterAttempts: attempts)
        }
        reconnectionStates[peripheralId]?.reset()
        activeReconnections.remove(peripheralId)
        lastDataReceived[peripheralId] = Date()
        connectionHealth[peripheralId] = .healthy
    }

    /// Handle disconnection (may trigger reconnection)
    func handleDisconnection(for peripheralId: UUID, peripheral: CBPeripheral, wasUnexpected: Bool, error: Error? = nil) {
        connectionHealth[peripheralId] = .disconnected
        lastDataReceived.removeValue(forKey: peripheralId)

        if wasUnexpected && config.autoReconnectEnabled {
            // Supervision / link-loss timeouts recover better with a short radio backoff than instant reconnect storms.
            let isLinkSupervisionTimeout = (error as? CBError)?.code == .connectionTimeout
            scheduleReconnection(
                for: peripheralId,
                peripheral: peripheral,
                immediate: !isLinkSupervisionTimeout
            )
        } else {
            reconnectionStates[peripheralId]?.reset()
            activeReconnections.remove(peripheralId)
        }
    }

    // MARK: - RSSI Polling

    /// Start RSSI polling for connected peripherals
    func startRSSIPolling(for peripherals: [CBPeripheral]) {
        rssiPollingTask?.cancel()

        guard !peripherals.isEmpty else { return }

        rssiPollingTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled && self.isRunning {
                for peripheral in peripherals where peripheral.state == .connected {
                    peripheral.readRSSI()
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(self.config.rssiPollingInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    /// Stop RSSI polling
    func stopRSSIPolling() {
        rssiPollingTask?.cancel()
        rssiPollingTask = nil
    }

    /// Update RSSI value for a peripheral
    func updateRSSI(for peripheralId: UUID, rssi: Int) {
        rssiValues[peripheralId] = rssi
        eventSubject.send(.rssiUpdated(peripheralId: peripheralId, rssi: rssi))

        #if DEBUG
        let now = Date()
        let lastLog = linkQualityLastDebugLogAt[peripheralId] ?? .distantPast
        guard now.timeIntervalSince(lastLog) >= 30 else { return }
        linkQualityLastDebugLogAt[peripheralId] = now

        let shortId = String(peripheralId.uuidString.prefix(8))
        let health = connectionHealth[peripheralId]?.rawValue ?? "n/a"
        let dataAgeMs: String
        if let last = lastDataReceived[peripheralId] {
            dataAgeMs = String(format: "%.0f", now.timeIntervalSince(last) * 1000)
        } else {
            dataAgeMs = "n/a"
        }
        Logger.shared.debug(
            "[BLELinkQuality] id=\(shortId)… rssi=\(rssi) dBm notifyAgeMs=\(dataAgeMs) health=\(health)"
        )
        #endif
    }

    // MARK: - Connection Health Monitoring

    /// Record that data was received from a peripheral
    func recordDataReceived(from peripheralId: UUID) {
        let previousHealth = connectionHealth[peripheralId]
        lastDataReceived[peripheralId] = Date()
        if previousHealth != .healthy {
            connectionHealth[peripheralId] = .healthy
            if let previousHealth {
                Logger.shared.info("[BLEBackgroundWorker][Health] \(peripheralId) recovered to healthy (was \(previousHealth.rawValue))")
            } else {
                Logger.shared.debug("[BLEBackgroundWorker][Health] \(peripheralId) marked healthy on first data receipt")
            }
        }
    }

    /// Start the health check loop
    private func startHealthCheckLoop() {
        healthCheckTask?.cancel()

        healthCheckTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled && self.isRunning {
                await self.performHealthCheck()

                do {
                    try await Task.sleep(nanoseconds: UInt64(self.config.healthCheckInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    /// Perform a health check on all tracked connections
    private func performHealthCheck() {
        let now = Date()

        for (peripheralId, lastReceived) in lastDataReceived {
            let elapsed = now.timeIntervalSince(lastReceived)

            if elapsed > config.connectionStaleTimeout {
                if connectionHealth[peripheralId] != .stale {
                    connectionHealth[peripheralId] = .stale
                    eventSubject.send(.connectionStale(peripheralId: peripheralId))
                    Logger.shared.warning("[BLEBackgroundWorker] Connection stale for \(peripheralId) - no data for \(Int(elapsed))s")
                }
            } else if elapsed > config.connectionStaleTimeout / 2 {
                if connectionHealth[peripheralId] == .healthy {
                    connectionHealth[peripheralId] = .warning
                    eventSubject.send(.connectionHealthWarning(
                        peripheralId: peripheralId,
                        reason: "No data received for \(Int(elapsed)) seconds"
                    ))
                    Logger.shared.warning("[BLEBackgroundWorker][Health] Warning for \(peripheralId): no data for \(Int(elapsed))s (warning threshold: \(Int(config.connectionStaleTimeout / 2))s, stale threshold: \(Int(config.connectionStaleTimeout))s)")
                }
            }
        }
    }

    // MARK: - Event Subscription

    private func setupEventSubscription() {
        guard let bleService = bleService else { return }

        // Ensure we never process BLE service events twice.
        bleServiceEventCancellable?.cancel()
        bleServiceEventCancellable = bleService.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleBLEEvent(event)
            }
    }

    private func handleBLEEvent(_ event: BLEServiceEvent) {
        switch event {
        case .deviceConnected(let peripheral):
            handleConnectionSuccess(for: peripheral.identifier)

        case .deviceDisconnected(let peripheral, let error):
            let wasUnexpected = error != nil
            handleDisconnection(
                for: peripheral.identifier,
                peripheral: peripheral,
                wasUnexpected: wasUnexpected,
                error: error
            )

        case .characteristicUpdated(let peripheral, _, _):
            recordDataReceived(from: peripheral.identifier)

        case .bluetoothStateChanged(let state):
            handleBluetoothStateChange(state)

        case .error(let bleError):
            handleBLEError(bleError)

        default:
            break
        }
    }

    /// Handle BLEError events from the BLE service
    private func handleBLEError(_ error: BLEError) {
        // Log the error
        logBLEError(error, context: "BLEServiceEvent")

        // Handle specific error types that affect reconnection
        switch error {
        case .connectionFailed(let peripheralId, _):
            // Mark reconnection as failed for this attempt
            if reconnectionStates[peripheralId]?.isActive == true {
                let attempt = reconnectionStates[peripheralId]?.attemptCount ?? 0
                let willRetry = attempt < config.maxReconnectionAttempts
                reconnectionDelegate?.reconnectionAttemptDidFail(
                    for: peripheralId,
                    attempt: attempt,
                    error: error,
                    willRetry: willRetry
                )
            }

        case .bluetoothNotReady, .bluetoothUnauthorized, .bluetoothUnsupported:
            // These are handled by handleBluetoothStateChange
            break

        case .maxReconnectionAttemptsExceeded(let peripheralId, let attempts):
            // Ensure we clean up state
            reconnectionStates[peripheralId]?.reset()
            activeReconnections.remove(peripheralId)
            reconnectionDelegate?.reconnectionDidGiveUp(for: peripheralId, totalAttempts: attempts, lastError: error)

        default:
            break
        }
    }

    /// Log a BLEError with appropriate severity
    private func logBLEError(_ error: BLEError, context: String) {
        let message = "[BLEBackgroundWorker] [\(context)] \(error.errorDescription ?? "Unknown error")"

        switch error.severity {
        case .info:
            Logger.shared.info(message)
        case .warning:
            Logger.shared.warning(message)
        case .error:
            Logger.shared.error(message)
        case .critical:
            Logger.shared.error("⚠️ CRITICAL: \(message)")
        }

        // Log recovery suggestion if available
        if let suggestion = error.recoverySuggestion {
            Logger.shared.debug("  ↳ Suggestion: \(suggestion)")
        }
    }

    /// Handle Bluetooth state changes - resume pending reconnections when BT comes back
    private func handleBluetoothStateChange(_ state: CBManagerState) {
        if state == .poweredOn {
            // Bluetooth is back on - resume any pending reconnections
            let pending = pendingReconnectionPeripherals
            pendingReconnectionPeripherals.removeAll()

            if !pending.isEmpty {
                Logger.shared.info("[BLEBackgroundWorker] Bluetooth ready - resuming \(pending.count) pending reconnection(s)")
                for (peripheralId, peripheral) in pending {
                    scheduleReconnection(for: peripheralId, peripheral: peripheral, immediate: false)
                }
            }
        } else if state == .poweredOff && config.pauseOnBluetoothOff {
            // Bluetooth turned off - pause active reconnections
            Logger.shared.warning("[BLEBackgroundWorker] Bluetooth powered off - pausing reconnections")

            // Move active reconnections to pending
            for peripheralId in activeReconnections {
                let deferredPeripheral = reconnectionStates[peripheralId]?.peripheral
                    ?? bleService?.retrievePeripherals(withIdentifiers: [peripheralId]).first
                reconnectionStates[peripheralId]?.task?.cancel()
                reconnectionStates[peripheralId]?.task = nil
                reconnectionStates[peripheralId]?.isActive = false
                if let peripheral = deferredPeripheral {
                    pendingReconnectionPeripherals[peripheralId] = peripheral
                }
            }
            activeReconnections.removeAll()

            // Cancel timeout tasks
            for (_, task) in connectionTimeoutTasks {
                task.cancel()
            }
            connectionTimeoutTasks.removeAll()
        }
    }

    // MARK: - App Lifecycle Handling

    /// Handle app entering background mode
    /// BLE operations continue in background for connected devices
    func handleAppEnteredBackground() {
        Logger.shared.info("[BLEBackgroundWorker] App entered background - BLE operations continue")
        // BLE operations continue in background for connected devices
        // No action needed - CoreBluetooth maintains connections in background
    }

    /// Handle app returning to foreground
    func handleAppEnteredForeground() {
        Logger.shared.info("[BLEBackgroundWorker] App entered foreground")
        // No action needed - operations continue normally
    }

    /// Handle app about to suspend (low memory, system pressure)
    func handleAppWillSuspend() {
        Logger.shared.warning("[BLEBackgroundWorker] App will suspend - BLE operations may be interrupted")
        // Note: We don't stop operations here as iOS manages BLE background execution
    }

    /// Handle app resuming from suspended state
    func handleAppDidResume() {
        Logger.shared.info("[BLEBackgroundWorker] App resumed from suspension")
        // Verify connections are still active after resume
        // The health check loop will detect any stale connections
    }

    /// Handle app termination - clean up all resources
    func handleAppWillTerminate() {
        Logger.shared.warning("[BLEBackgroundWorker] App will terminate - stopping worker")
        stop()
    }
}

// MARK: - Connection Health Status

/// Health status for a BLE connection
enum ConnectionHealthStatus: String {
    case healthy = "Healthy"
    case warning = "Warning"
    case stale = "Stale"
    case disconnected = "Disconnected"

    var isConnected: Bool {
        self != .disconnected
    }

    var needsAttention: Bool {
        self == .warning || self == .stale
    }
}

// MARK: - Singleton Access

extension BLEBackgroundWorker {
    /// Shared instance for app-wide use
    static let shared = BLEBackgroundWorker()
}
