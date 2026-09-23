//
//  DeviceManager.swift
//  OralableApp
//
//  Coordinates BLE device discovery, connection, and data flow.
//
//  This is the core file containing published properties, initialization,
//  BLE callback setup, readiness tracking, error handling, and device info access.
//
//  Related extension files (same class, split for organization):
//  - DeviceScanningCoordinator.swift: Scanning, discovery, device type detection
//  - DeviceConnectionCoordinator.swift: Connection lifecycle, service discovery
//  - DeviceSensorDataRouter.swift: Sensor data subscription and routing
//
//  Connection State Machine (ConnectionReadiness):
//  disconnected -> connecting -> connected -> discoveringServices
//  -> servicesDiscovered -> discoveringCharacteristics
//  -> characteristicsDiscovered -> enablingNotifications -> ready
//
//  Supported Devices:
//  - Oralable: Primary muscle activity monitor
//  - ANR M40: EMG device for research comparison
//  - Demo: Virtual device for testing
//
//  Data Flow:
//  BLE notification -> OralableDevice.parseSensorData()
//  -> DeviceManager.handleReadingsBatch()
//  -> DeviceManagerAdapter -> DashboardViewModel
//
//  Updated: December 8, 2025 - Stricter device filtering (only Oralable and ANR)
//

import Foundation
import CoreBluetooth
import Combine
import OralableCore

// MARK: - Connection Readiness State Machine (Day 1)

enum ConnectionReadiness: Equatable {
    case disconnected
    case connecting
    case connected
    case discoveringServices
    case servicesDiscovered
    case discoveringCharacteristics
    case characteristicsDiscovered
    case enablingNotifications
    case ready
    case failed(String)
    
    var isConnected: Bool {
        switch self {
        case .disconnected, .connecting, .failed:
            return false
        case .connected, .discoveringServices, .servicesDiscovered,
             .discoveringCharacteristics, .characteristicsDiscovered,
             .enablingNotifications, .ready:
            return true
        }
    }
    
    var canRecord: Bool {
        return self == .ready
    }
    
    var displayText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .discoveringServices:
            return "Discovering services..."
        case .servicesDiscovered:
            return "Services found"
        case .discoveringCharacteristics:
            return "Discovering characteristics..."
        case .characteristicsDiscovered:
            return "Characteristics found"
        case .enablingNotifications:
            return "Setting up notifications..."
        case .ready:
            return "Ready"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
}

/// Manager for coordinating multiple BLE devices
@MainActor
class DeviceManager: ObservableObject {
    // MARK: - Published Properties
    
    /// All discovered devices
    @Published var discoveredDevices: [DeviceInfo] = []
    
    /// Currently connected devices
    @Published var connectedDevices: [DeviceInfo] = []
    
    /// Primary active device
    @Published var primaryDevice: DeviceInfo?

    /// Discovery / connect path selected from Withings-style UI (`DeviceManagerFactory`).
    @Published var preferredDiscoveryProduct: DeviceManagerFactory.Product = .temporalisHeadband

    /// Shared OralableCore ring buffer for loss-bounded 50 Hz `SensorData` (all product lines).
    let unifiedSensorDataBuffer: SensorDataBuffer

    /// Future ANR transport; already wired to `unifiedSensorDataBuffer`.
    let anrMuscleManager: ANRMuscleManager
    
    /// All sensor readings from all devices
    @Published var allSensorReadings: [SensorReading] = []
    
    /// Latest readings by sensor type (aggregated from all devices)
    @Published var latestReadings: [SensorType: SensorReading] = [:]
    
    /// Connection state
    @Published var isScanning: Bool = false
    @Published var isConnecting: Bool = false
    
    /// Errors
    @Published var lastError: DeviceError?

    /// Latest firmware status from primary Oralable device (3A0FF009).
    @Published var primaryFirmwareDeviceStatus: TGMDeviceStatus?

    /// REV10 peripherals that failed the minimum firmware gate (UUID matches `DeviceInfo.peripheralIdentifier`).
    @Published var oralableFirmwareBlockedPeripheralIds: Set<UUID> = []

    /// Bluetooth state for UI display
    @Published var bluetoothState: CBManagerState = .unknown

    /// Whether Bluetooth is ready for scanning/connecting
    var isBluetoothReady: Bool { bluetoothState == .poweredOn }

    // Day 1: Connection readiness tracking
    @Published var deviceReadiness: [UUID: ConnectionReadiness] = [:]
    
    var primaryDeviceReadiness: ConnectionReadiness {
        guard let primaryId = primaryDevice?.peripheralIdentifier else {
            // Check if demo device is connected
            if DemoDataProvider.shared.isConnected {
                return .ready
            }
            return .disconnected
        }
        return deviceReadiness[primaryId] ?? .disconnected
    }

    // MARK: - Demo Device Integration

    /// Check if any device is connected (real or demo)
    var isAnyDeviceConnected: Bool {
        return !connectedDevices.isEmpty || DemoDataProvider.shared.isConnected
    }
    
    // MARK: - Automatic Recording Session

    /// Automatic state-based recording session
    /// Starts on device connect, stops on disconnect
    public private(set) var automaticRecordingSession: AutomaticRecordingSession?

    // MARK: - Internal Properties (accessed by extensions in other files)

    /// Single-flight guard for the async discovery/notification pipeline per peripheral.
    /// Note: accessed by connection coordinator extension in another file.
    var discoveryFlowTasks: [UUID: Task<Void, Never>] = [:]

    var devices: [UUID: BLEDeviceProtocol] = [:]
    var cancellables = Set<AnyCancellable>()
    private let maxDevices: Int = 5

    // BLE Integration - now using protocol for dependency injection
    private(set) var bleService: BLEService?

    // Legacy accessor for backward compatibility
    var bleManager: BLECentralManager? {
        bleService as? BLECentralManager
    }

    // Background worker for reconnection and polling
    let backgroundWorker: BLEBackgroundWorker

    // Discovery tracking
    var discoveryCount: Int = 0
    var scanStartTime: Date?
    var rejectedDiscoveryLogSeenThisScan: Set<String> = []

    // Device persistence for auto-reconnect
    let persistenceManager = DevicePersistenceManager.shared

    // Per-reading publisher (legacy, prefer batch)
    let readingsSubject = PassthroughSubject<SensorReading, Never>()
    var readingsPublisher: AnyPublisher<SensorReading, Never> {
        readingsSubject.eraseToAnyPublisher()
    }

    // Batch publisher for efficient multi-reading delivery
    let readingsBatchSubject = PassthroughSubject<[SensorReading], Never>()
    var readingsBatchPublisher: AnyPublisher<[SensorReading], Never> {
        readingsBatchSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    /// Default initializer using concrete BLECentralManager
    init() {
        let buffer = SensorDataBuffer(maxCapacity: 1_800_000)
        self.unifiedSensorDataBuffer = buffer
        self.anrMuscleManager = ANRMuscleManager(sensorDataBuffer: buffer)
        Logger.shared.info("[DeviceManager] Initializing with default BLECentralManager...")
        self.bleService = BLECentralManager()
        self.backgroundWorker = BLEBackgroundWorker()
        setupBLECallbacks()
        setupBackgroundWorker()
        setupAutomaticRecordingSession()
        Logger.shared.info("[DeviceManager] Initialization complete")
    }

    /// Dependency injection initializer for testing and flexibility
    /// - Parameters:
    ///   - bleService: Any BLEService conforming instance
    ///   - backgroundWorker: Optional custom background worker (defaults to new instance)
    init(bleService: BLEService, backgroundWorker: BLEBackgroundWorker? = nil) {
        let buffer = SensorDataBuffer(maxCapacity: 1_800_000)
        self.unifiedSensorDataBuffer = buffer
        self.anrMuscleManager = ANRMuscleManager(sensorDataBuffer: buffer)
        Logger.shared.info("[DeviceManager] Initializing with injected BLEService...")
        self.bleService = bleService
        self.backgroundWorker = backgroundWorker ?? BLEBackgroundWorker()
        setupBLECallbacks()
        setupBackgroundWorker()
        setupAutomaticRecordingSession()
        Logger.shared.info("[DeviceManager] Initialization complete")
    }

    /// Setup background worker with BLE service and start
    private func setupBackgroundWorker() {
        if let service = bleService {
            backgroundWorker.configure(bleService: service)
        }
        backgroundWorker.start()

        // Subscribe to background worker events
        backgroundWorker.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleBackgroundWorkerEvent(event)
            }
            .store(in: &cancellables)

        Logger.shared.info("[DeviceManager] Background worker configured and started")
    }

    /// Setup automatic recording session for state-based event recording
    private func setupAutomaticRecordingSession() {
        let session = AutomaticRecordingSession()
        session.skipCalibration = FeatureFlags.shared.vitalsPhaseEnabled

        session.onSessionStarted = { [weak self] in
            Logger.shared.info("[DeviceManager] Automatic recording session started")
            NRFConnectBLELogger.shared.throttleHighRateNotifications = false
            self?.backgroundWorker.setUnlimitedReconnectActive(true)
        }

        session.onSessionStopped = { [weak self] eventCount in
            Logger.shared.info("[DeviceManager] Automatic recording session stopped with \(eventCount) events")
            NRFConnectBLELogger.shared.throttleHighRateNotifications = true
            self?.backgroundWorker.setUnlimitedReconnectActive(false)
        }

        session.onStateChanged = { newState in
            Logger.shared.info("[DeviceManager] Recording state changed to: \(newState.rawValue)")
        }

        automaticRecordingSession = session
        Logger.shared.info("[DeviceManager] Automatic recording session configured")

        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.automaticRecordingSession?.endSessionIfPauseExpired()
            }
            .store(in: &cancellables)
    }

    /// Call when BLE discovery reaches `.ready`.
    /// Ends an expired automatic-session pause before `onDeviceConnected()` so a
    /// late reconnect cannot leave the session active+paused (Core no-ops in that
    /// state) and then lose AutoFlush / unlimited reconnect when the timer ends it.
    func notifyAutomaticRecordingDeviceReady() {
        automaticRecordingSession?.endSessionIfPauseExpired()
        automaticRecordingSession?.onDeviceConnected()
    }

    /// Handle events from background worker
    private func handleBackgroundWorkerEvent(_ event: BLEBackgroundWorkerEvent) {
        switch event {
        case .reconnectionSucceeded(let peripheralId):
            Logger.shared.info("[DeviceManager] Reconnection succeeded for \(peripheralId)")

        case .reconnectionGaveUp(let peripheralId, let attempts):
            Logger.shared.warning("[DeviceManager] Reconnection gave up for \(peripheralId) after \(attempts) attempts")
            lastError = .connectionLost
            if automaticRecordingSession?.isSessionPaused == true {
                automaticRecordingSession?.endSession()
            }

        case .connectionStale(let peripheralId):
            Logger.shared.warning("[DeviceManager] Connection stale for \(peripheralId)")
            // Optionally trigger UI update or notification

        case .rssiUpdated(let peripheralId, let rssi):
            // Update device signal strength
            if let index = connectedDevices.firstIndex(where: { $0.peripheralIdentifier == peripheralId }) {
                connectedDevices[index].signalStrength = rssi
            }

        default:
            break
        }
    }
    
    // MARK: - BLE Callbacks Setup

    private func setupBLECallbacks() {
        Logger.shared.info("[DeviceManager] Setting up BLE callbacks...")

        // Subscribe to BLEService event publisher (single source of truth).
        // Using both publisher + legacy closures causes duplicate events.
        bleService?.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleBLEServiceEvent(event)
            }
            .store(in: &cancellables)

        // Disable legacy callbacks to avoid duplicate discovery/connection flows.
        if let centralManager = bleManager {
            centralManager.onDeviceDiscovered = nil
            centralManager.onDeviceConnected = nil
            centralManager.onDeviceDisconnected = nil
            centralManager.onBluetoothStateChanged = nil
            centralManager.shouldPreserveValidationLog = { [weak self] in
                self?.automaticRecordingSession?.isSessionActive == true
            }
        }

        Logger.shared.info("[DeviceManager] BLE callbacks configured successfully")
    }

    /// Handle events from BLEService publisher
    private func handleBLEServiceEvent(_ event: BLEServiceEvent) {
        switch event {
        case .deviceDiscovered(let peripheral, let name, let rssi, let advertisementData):
            handleDeviceDiscovered(peripheral: peripheral, name: name, rssi: rssi, advertisementData: advertisementData)

        case .deviceConnected(let peripheral):
            handleDeviceConnected(peripheral: peripheral)

        case .deviceDisconnected(let peripheral, let error):
            handleDeviceDisconnected(peripheral: peripheral, error: error)

        case .bluetoothStateChanged(let state):
            bluetoothState = state
            if state != .poweredOn && isScanning {
                Logger.shared.warning("[DeviceManager] Bluetooth not powered on, stopping scan")
                isScanning = false
            }

        case .characteristicUpdated(_, _, _):
            // Handled by individual device implementations
            break

        case .characteristicWritten(_, _, _):
            // Handled by individual device implementations
            break

        case .servicesDiscovered(_, _, _):
            // Handled by individual device implementations
            break

        case .characteristicsDiscovered(_, _, _, _):
            // Handled by individual device implementations
            break

        case .error(let bleError):
            handleBLEError(bleError)
        }
    }

    /// Handle BLEError events from the BLE service
    private func handleBLEError(_ error: BLEError) {
        // Log based on severity
        logBLEError(error)

        // Convert to DeviceError for UI display and update lastError
        lastError = convertToDeviceError(error)

        // Handle specific error types
        switch error {
        case .bluetoothNotReady, .bluetoothUnauthorized, .bluetoothUnsupported:
            // Stop scanning if Bluetooth issue
            if isScanning {
                isScanning = false
            }
            isConnecting = false

        case .connectionFailed(let peripheralId, _),
             .connectionTimeout(let peripheralId, _):
            // Update device state to disconnected
            updateDeviceReadiness(peripheralId, to: .failed(error.errorDescription ?? "Connection failed"))
            isConnecting = false

        case .unexpectedDisconnection(let peripheralId, _):
            // Already handled by handleDeviceDisconnected, but ensure state is updated
            updateDeviceReadiness(peripheralId, to: .disconnected)

        case .maxReconnectionAttemptsExceeded(let peripheralId, let attempts):
            Logger.shared.error("[DeviceManager] Max reconnection attempts (\(attempts)) exceeded for device \(peripheralId)")
            updateDeviceReadiness(peripheralId, to: .failed("Reconnection failed after \(attempts) attempts"))

        default:
            // Other errors are logged but don't require special handling
            break
        }
    }

    /// Convert BLEError to DeviceError for UI display
    private func convertToDeviceError(_ bleError: BLEError) -> DeviceError {
        switch bleError {
        case .bluetoothNotReady, .bluetoothResetting:
            return .bluetoothUnavailable
        case .bluetoothUnauthorized:
            return .bluetoothUnauthorized
        case .bluetoothUnsupported:
            return .bluetoothUnavailable
        case .connectionFailed(_, let reason):
            return .connectionFailed(reason ?? "Unknown reason")
        case .connectionTimeout(_, let timeout):
            return .connectionFailed("Connection timed out after \(Int(timeout)) seconds")
        case .unexpectedDisconnection:
            return .connectionLost
        case .peripheralNotConnected(let id):
            return .notConnected("Device \(id) is not connected")
        case .peripheralNotFound(let id):
            return .invalidPeripheral("Device \(id) not found")
        case .maxReconnectionAttemptsExceeded(_, let attempts):
            return .connectionFailed("Max reconnection attempts (\(attempts)) exceeded")
        case .serviceNotFound(let uuid, _):
            return .serviceNotFound(uuid.uuidString)
        case .characteristicNotFound(let uuid, _):
            return .characteristicNotFound(uuid.uuidString)
        case .serviceDiscoveryFailed(_, let reason):
            return .serviceNotFound(reason ?? "Discovery failed")
        case .characteristicDiscoveryFailed(_, let reason):
            return .characteristicNotFound(reason ?? "Discovery failed")
        case .timeout:
            return .timeout
        case .dataCorrupted(let description):
            return .parsingError(description)
        case .dataValidationFailed(let expected, let received):
            return .parsingError("Expected: \(expected), Received: \(received)")
        case .invalidDataFormat(let description):
            return .parsingError(description)
        case .writeFailed:
            return .characteristicWriteFailed
        case .readFailed:
            return .characteristicReadFailed
        case .notificationSetupFailed:
            return .characteristicWriteFailed
        case .cancelled:
            return .timeout
        case .operationNotPermitted:
            return .operationNotSupported
        case .alreadyScanning, .notScanning:
            return .deviceBusy
        case .internalError(let reason, _):
            return .unknownError(reason)
        case .unknown(let description):
            return .unknownError(description)
        }
    }

    /// Log BLEError with appropriate severity
    private func logBLEError(_ error: BLEError) {
        let message = "[DeviceManager] BLE Error: \(error.errorDescription ?? "Unknown error")"

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
            Logger.shared.info("  ↳ Recovery suggestion: \(suggestion)")
        }
    }
    
    // Day 1 & Day 4: Helper to update device readiness across all collections
    func updateDeviceReadiness(_ peripheralId: UUID, to readiness: ConnectionReadiness) {
        deviceReadiness[peripheralId] = readiness
        
        // Update in discoveredDevices
        if let index = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheralId }) {
            discoveredDevices[index].connectionReadiness = readiness
        }
        
        // Update in connectedDevices
        if let index = connectedDevices.firstIndex(where: { $0.peripheralIdentifier == peripheralId }) {
            connectedDevices[index].connectionReadiness = readiness
        }
        
        // Update primaryDevice
        if primaryDevice?.peripheralIdentifier == peripheralId {
            primaryDevice?.connectionReadiness = readiness
        }
        
        Logger.shared.debug("[DeviceManager] Updated readiness to: \(readiness.displayText)")
        
        // Day 4 Fix: Auto-stop scanning when device is ready
        if readiness == .ready && isScanning {
            Logger.shared.info("[DeviceManager] 🛑 Device ready - auto-stopping scan")
            stopScanning()
        }

        if readiness == .ready {
            oralableFirmwareBlockedPeripheralIds.remove(peripheralId)
        }
    }

    /// Sync firmware string read from GATT into list models for discovery UI.
    func applyDiscoveredFirmwareVersion(peripheralId: UUID, version: String) {
        if let index = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheralId }) {
            discoveredDevices[index].firmwareVersion = version
        }
        if let index = connectedDevices.firstIndex(where: { $0.peripheralIdentifier == peripheralId }) {
            connectedDevices[index].firmwareVersion = version
        }
        if var p = primaryDevice, p.peripheralIdentifier == peripheralId {
            p.firmwareVersion = version
            primaryDevice = p
        }
    }

    /// Writes the unified ring buffer to a temp CSV and clears memory (paired with `SensorDataProcessor` flush).
    func flushUnifiedSensorBufferToTempFile() async {
        let batch = await unifiedSensorDataBuffer.removeAllCopying()
        guard !batch.isEmpty else { return }
        do {
            let name = "oralable_unified_flush_\(Int(Date().timeIntervalSince1970)).csv"
            let url = ApplicationSupportPaths.memoryFlushDirectory.appendingPathComponent(name)
            try ResearchRawDataExport.writeOralableRaw50HzCSV(samples: batch, to: url)
            MemoryFlushStatus.shared.recordFlushSuccess()
            Logger.shared.info("[DeviceManager] Unified buffer auto-flush: \(batch.count) samples → Application Support/\(name)")
        } catch {
            Logger.shared.warning("[DeviceManager] Unified buffer flush failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Device Info Access
    
    func device(withId id: UUID) -> DeviceInfo? {
        return discoveredDevices.first { $0.id == id }
    }

    /// Read-only helper to fetch the underlying CBPeripheral for a given peripheral identifier
    func peripheral(for id: UUID) -> CBPeripheral? {
        return devices[id]?.peripheral
    }
    
    // MARK: - Data Management
    
    /// Clear all sensor readings
    func clearReadings() {
        Logger.shared.info("[DeviceManager] clearReadings() called")
        allSensorReadings.removeAll()
        latestReadings.removeAll()
        Logger.shared.info("[DeviceManager] All readings cleared")
    }
    
    /// Set a device as the primary device
    func setPrimaryDevice(_ deviceInfo: DeviceInfo?) {
        Logger.shared.info("[DeviceManager] setPrimaryDevice() called")
        if let device = deviceInfo {
            Logger.shared.info("[DeviceManager] Setting primary device to: \(device.name)")
        } else {
            Logger.shared.info("[DeviceManager] Clearing primary device")
        }
        primaryDevice = deviceInfo
    }

    /// Active `BLEDeviceProtocol` instance for the primary slot (nil if unknown / demo-only).
    var primaryBLEDevice: BLEDeviceProtocol? {
        guard let pid = primaryDevice?.peripheralIdentifier else { return nil }
        return devices[pid]
    }

    /// Minimum battery % before worn placement / PPG streaming (pilot test plan: charge >50%).
    static let wornPlacementMinimumBatteryPercent = 50

    /// Best available battery for the primary Oralable clip (status notify, then GATT battery).
    func primaryBatteryPercent() -> Int? {
        if let status = primaryFirmwareDeviceStatus {
            return Int(status.batteryPercent)
        }
        if let oralable = primaryBLEDevice as? OralableDevice, let level = oralable.batteryLevel {
            return level
        }
        if let level = primaryDevice?.batteryLevel {
            return level
        }
        return nil
    }

    /// Reported firmware string for the primary Oralable clip (GATT `3A0FF006`), if known.
    func primaryFirmwareVersion() -> String? {
        if let v = (primaryBLEDevice as? OralableDevice)?.firmwareVersion?
            .trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            return v
        }
        if let v = primaryDevice?.firmwareVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !v.isEmpty {
            return v
        }
        return nil
    }

    /// Placement mode last written to firmware on the active primary clip (nil if unknown / disconnected).
    func appliedFirmwarePlacementMode() -> FeatureFlags.DevicePlacementMode? {
        (primaryBLEDevice as? OralableDevice)?.lastAppliedPlacementMode
    }

    /// Apply explicit firmware placement (`00B` 0x09). Requires FW ≥ 1.0.62.
    /// Gen1 pcb00003: mid-session writes while streaming often drop BLE — use `force: true` only during connect setup.
    func applyFirmwarePlacementMode(_ mode: FeatureFlags.DevicePlacementMode, force: Bool = false) {
        guard let oralable = primaryBLEDevice as? OralableDevice else { return }

        if !force,
           FeatureFlags.shared.vitalsPhaseEnabled,
           primaryDeviceReadiness.isConnected,
           oralable.isConnectionReady,
           oralable.lastAppliedPlacementMode != mode {
            Logger.shared.info(
                "[DeviceManager] Deferred placement \(mode.title) — will apply on next connect (avoid mid-session BLE drop)"
            )
            return
        }

        if mode == .worn, FeatureFlags.shared.vitalsPhaseEnabled,
           let pct = primaryBatteryPercent(), pct < Self.wornPlacementMinimumBatteryPercent {
            Logger.shared.warning(
                "[DeviceManager] Blocked worn placement at \(pct)% (need ≥ \(Self.wornPlacementMinimumBatteryPercent)%)"
            )
            lastError = .connectionFailed(
                "Battery too low for temple mode (\(pct)%). Charge on the Qi pad to at least \(Self.wornPlacementMinimumBatteryPercent)% first."
            )
            return
        }

        do {
            try oralable.setFirmwareUserDeviceMode(mode)
            Logger.shared.info("[DeviceManager] Applied firmware placement mode: \(mode.title)")
        } catch {
            Logger.shared.warning("[DeviceManager] Firmware placement apply failed: \(error.localizedDescription)")
        }
    }

    /// Worn on cheek for on-body capture (overnight or structured session).
    func applyWornPlacementForBodySession() {
        FeatureFlags.shared.devicePlacementMode = .worn
        applyFirmwarePlacementMode(.worn)
    }

    /// Before Protocol B: set worn + arm connect hook (promotes forgotten off-dock connects).
    func prepareProtocolBSession() {
        applyWornPlacementForBodySession()
        FeatureFlags.shared.protocolBSessionPrepared = true
        Logger.shared.info("[DeviceManager] Protocol B session prepared (worn placement armed)")
    }

    /// Resolves placement for pilot connect.
    /// FW ≥ 1.0.70: keep Automatic (STAT blink dock). Older Gen1: remap Automatic → Off charger.
    func resolvePilotPlacementOnConnect(oralable: OralableDevice) throws {
        let flags = FeatureFlags.shared
        var mode = flags.devicePlacementMode
        let fw = oralable.firmwareVersion
        let automaticDockOK = FirmwareGate.supportsAutomaticDockDetect(fw)

        if mode == .auto {
            if automaticDockOK {
                Logger.shared.info(
                    "[DeviceManager] Keeping Automatic placement (FW \(fw ?? "?") STAT dock)"
                )
            } else if flags.vitalsPhaseEnabled {
                mode = .offDockIdle
                Logger.shared.info(
                    "[DeviceManager] Vitals phase: Automatic → Off charger (FW \(fw ?? "?") < \(FirmwareGate.recommendedOralableSemanticVersion))"
                )
            } else {
                mode = flags.protocolBSessionPrepared ? .worn : .offDockIdle
                Logger.shared.info(
                    "[DeviceManager] Promoted placement Automatic → \(mode.title) (pre-1.0.70 chrsts policy)"
                )
            }
        } else if flags.protocolBSessionPrepared && mode == .offDockIdle {
            mode = .worn
            Logger.shared.info("[DeviceManager] Promoted placement Off charger → Worn (Protocol B prepared)")
        }

        if mode != flags.devicePlacementMode {
            flags.devicePlacementMode = mode
        }

        if flags.vitalsPhaseEnabled && mode == .worn {
            if let pct = oralable.batteryLevel, pct < Self.wornPlacementMinimumBatteryPercent {
                mode = .offDockIdle
                flags.devicePlacementMode = mode
                Logger.shared.warning(
                    "[DeviceManager] Vitals: blocked worn on connect at \(pct)% — using Off charger (not worn)"
                )
            }
        }

        try oralable.setFirmwareUserDeviceMode(mode)

        if flags.debugRebootIntervalMinutes > 0 {
            let seconds = UInt16(flags.debugRebootIntervalMinutes) * 60
            try? oralable.setFirmwareDebugRebootInterval(seconds: seconds)
        }
    }

    /// Append resampled / framed `SensorData` into the shared OralableCore buffer (50 Hz lane).
    func appendToUnifiedSensorStream(_ data: SensorData) {
        Task { await unifiedSensorDataBuffer.append(data) }
    }

    /// Batch append into the unified buffer (single actor hop via `append(contentsOf:)`).
    func appendBatchToUnifiedSensorStream(_ data: [SensorData]) {
        guard !data.isEmpty else { return }
        Task {
            await unifiedSensorDataBuffer.append(contentsOf: data)
        }
    }

    // MARK: - Auto-Reconnect to Remembered Devices

    /// Preferred Oralable target for error-banner retry and vitals reconnect (not arbitrary scan order).
    func preferredOralableReconnectTarget() -> DeviceInfo? {
        let remembered = persistenceManager.getRememberedDevices()
        let oralableRemembered = remembered.filter {
            $0.name.lowercased().contains("oralable")
        }

        if let primaryId = primaryDevice?.peripheralIdentifier?.uuidString,
           let match = oralableRemembered.first(where: { $0.id == primaryId }),
           let uuid = UUID(uuidString: match.id) {
            if let discovered = discoveredDevices.first(where: { $0.peripheralIdentifier == uuid }) {
                return discovered
            }
            if let registry = devices[uuid] {
                return DeviceInfo(
                    type: .oralable,
                    name: match.name,
                    peripheralIdentifier: uuid,
                    connectionState: registry.connectionState,
                    signalStrength: discoveredDevices.first(where: { $0.peripheralIdentifier == uuid })?.signalStrength ?? -60
                )
            }
        }

        for remembered in oralableRemembered {
            guard let uuid = UUID(uuidString: remembered.id) else { continue }
            if let discovered = discoveredDevices.first(where: { $0.peripheralIdentifier == uuid }) {
                return discovered
            }
            if devices[uuid] != nil {
                return DeviceInfo(
                    type: .oralable,
                    name: remembered.name,
                    peripheralIdentifier: uuid,
                    connectionState: .disconnected,
                    signalStrength: -60
                )
            }
        }

        if FeatureFlags.shared.vitalsPhaseEnabled {
            return discoveredDevices.first(where: { $0.type == .oralable })
        }

        return discoveredDevices.first
    }

    /// Connect to a remembered device by UUID — uses CoreBluetooth retrieve when not in scan list.
    func connectToRememberedDevice(id: String) async throws {
        if let discovered = discoveredDevices.first(where: { $0.peripheralIdentifier?.uuidString == id }) {
            try await connect(to: discovered)
            return
        }

        guard let uuid = UUID(uuidString: id) else {
            throw DeviceError.invalidPeripheral("Invalid device id")
        }

        if devices[uuid] == nil, let peripheral = bleService?.retrievePeripherals(withIdentifiers: [uuid]).first {
            let name = persistenceManager.getRememberedDevices().first(where: { $0.id == id })?.name
                ?? peripheral.name
                ?? "Oralable"
            handleDeviceDiscovered(peripheral: peripheral, name: name, rssi: -60)
        }

        guard let device = devices[uuid] else {
            Logger.shared.warning("[DeviceManager] Remembered device not in registry — starting scan")
            await startScanning()
            throw DeviceError.invalidPeripheral("Device not available — scan started")
        }

        let rememberedName = persistenceManager.getRememberedDevices().first(where: { $0.id == id })?.name
            ?? device.name

        let info = DeviceInfo(
            type: device.deviceType,
            name: rememberedName,
            peripheralIdentifier: uuid,
            connectionState: device.connectionState,
            signalStrength: -60
        )

        if !discoveredDevices.contains(where: { $0.peripheralIdentifier == uuid }) {
            discoveredDevices.append(info)
        }

        try await connect(to: info)
    }

    /// Attempt to auto-reconnect to previously remembered devices
    /// This method waits for Bluetooth to be ready before attempting reconnection
    func attemptAutoReconnect() {
        let rememberedDevices = persistenceManager.getRememberedDevices()
        guard !rememberedDevices.isEmpty else {
            Logger.shared.info("[DeviceManager] No remembered devices for auto-reconnect")
            return
        }

        Logger.shared.info("[DeviceManager] Scheduling auto-reconnect to \(rememberedDevices.count) remembered device(s)")

        // Use whenReady to defer scanning until Bluetooth is powered on
        bleService?.whenReady { [weak self] in
            guard let self = self else { return }

            Task { @MainActor in
                Logger.shared.info("[DeviceManager] ✅ Bluetooth ready - starting auto-reconnect")

                let targets = rememberedDevices.filter { remembered in
                    if FeatureFlags.shared.vitalsPhaseEnabled {
                        return remembered.name.lowercased().contains("oralable")
                    }
                    return true
                }

                for remembered in targets {
                    guard let uuid = UUID(uuidString: remembered.id) else { continue }
                    do {
                        try await self.connectToRememberedDevice(id: remembered.id)
                        let readiness = await self.waitForDeviceReadiness(uuid, timeoutSeconds: 20)
                        if readiness == .ready {
                            Logger.shared.info("[DeviceManager] Auto-reconnected to \(remembered.name)")
                            return
                        }
                        Logger.shared.debug(
                            "[DeviceManager] Auto-reconnect incomplete for \(remembered.name): \(readiness.displayText)"
                        )
                    } catch {
                        Logger.shared.debug("[DeviceManager] Auto-reconnect failed for \(remembered.name): \(error.localizedDescription)")
                    }
                }

                if self.deviceReadiness.values.contains(.ready) {
                    return
                }

                await self.startScanning()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                for remembered in targets {
                    guard let uuid = UUID(uuidString: remembered.id) else { continue }
                    do {
                        try await self.connectToRememberedDevice(id: remembered.id)
                        let readiness = await self.waitForDeviceReadiness(uuid, timeoutSeconds: 20)
                        if readiness == .ready {
                            Logger.shared.info("[DeviceManager] Auto-reconnected after scan to \(remembered.name)")
                            break
                        }
                    } catch {
                        Logger.shared.debug("[DeviceManager] Post-scan auto-reconnect failed for \(remembered.name)")
                    }
                }
                self.stopScanning()
            }
        }
    }
}
