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
    
    /// All sensor readings from all devices
    @Published var allSensorReadings: [SensorReading] = []
    
    /// Latest readings by sensor type (aggregated from all devices)
    @Published var latestReadings: [SensorType: SensorReading] = [:]
    
    /// Connection state
    @Published var isScanning: Bool = false
    @Published var isConnecting: Bool = false
    
    /// Errors
    @Published var lastError: DeviceError?

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

        session.onSessionStarted = {
            Logger.shared.info("[DeviceManager] Automatic recording session started")
        }

        session.onSessionStopped = { eventCount in
            Logger.shared.info("[DeviceManager] Automatic recording session stopped with \(eventCount) events")
        }

        session.onStateChanged = { newState in
            Logger.shared.info("[DeviceManager] Recording state changed to: \(newState.rawValue)")
        }

        automaticRecordingSession = session
        Logger.shared.info("[DeviceManager] Automatic recording session configured")
    }

    /// Handle events from background worker
    private func handleBackgroundWorkerEvent(_ event: BLEBackgroundWorkerEvent) {
        switch event {
        case .reconnectionSucceeded(let peripheralId):
            Logger.shared.info("[DeviceManager] Reconnection succeeded for \(peripheralId)")

        case .reconnectionGaveUp(let peripheralId, let attempts):
            Logger.shared.warning("[DeviceManager] Reconnection gave up for \(peripheralId) after \(attempts) attempts")
            lastError = .connectionLost

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

        // Subscribe to BLEService event publisher (new reactive approach)
        bleService?.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleBLEServiceEvent(event)
            }
            .store(in: &cancellables)

        // Also set up legacy callbacks for backward compatibility with BLECentralManager
        if let centralManager = bleManager {
            centralManager.onDeviceDiscovered = { [weak self] peripheral, name, rssi in
                Logger.shared.debug("[DeviceManager] onDeviceDiscovered callback received")
                Logger.shared.debug("[DeviceManager] Peripheral: \(peripheral.identifier)")
                Logger.shared.debug("[DeviceManager] Name: \(name)")
                Logger.shared.debug("[DeviceManager] RSSI: \(rssi)")

                Task { @MainActor [weak self] in
                    Logger.shared.debug("[DeviceManager] Dispatching to main actor...")
                    self?.handleDeviceDiscovered(peripheral: peripheral, name: name, rssi: rssi)
                }
            }

            centralManager.onDeviceConnected = { [weak self] peripheral in
                Logger.shared.debug("[DeviceManager] onDeviceConnected callback received")
                Logger.shared.debug("[DeviceManager] Peripheral: \(peripheral.identifier)")

                Task { @MainActor [weak self] in
                    Logger.shared.debug("[DeviceManager] Dispatching to main actor...")
                    self?.handleDeviceConnected(peripheral: peripheral)
                }
            }

            centralManager.onDeviceDisconnected = { [weak self] peripheral, error in
                Logger.shared.debug("[DeviceManager] onDeviceDisconnected callback received")
                Logger.shared.debug("[DeviceManager] Peripheral: \(peripheral.identifier)")
                if let error = error {
                    Logger.shared.error("[DeviceManager] Error: \(error.localizedDescription)")
                }

                Task { @MainActor [weak self] in
                    Logger.shared.debug("[DeviceManager] Dispatching to main actor...")
                    self?.handleDeviceDisconnected(peripheral: peripheral, error: error)
                }
            }

            centralManager.onBluetoothStateChanged = { [weak self] state in
                Logger.shared.debug("[DeviceManager] onBluetoothStateChanged callback received")
                Logger.shared.debug("[DeviceManager] State: \(state.rawValue)")

                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    // Update published state for UI
                    self.bluetoothState = state

                    if state != .poweredOn && self.isScanning {
                        Logger.shared.warning("[DeviceManager] Bluetooth not powered on, stopping scan")
                        self.isScanning = false
                    }
                }
            }
        }

        Logger.shared.info("[DeviceManager] BLE callbacks configured successfully")
    }

    /// Handle events from BLEService publisher
    private func handleBLEServiceEvent(_ event: BLEServiceEvent) {
        switch event {
        case .deviceDiscovered(let peripheral, let name, let rssi):
            handleDeviceDiscovered(peripheral: peripheral, name: name, rssi: rssi)

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

    // MARK: - Auto-Reconnect to Remembered Devices

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
                Logger.shared.info("[DeviceManager] ✅ Bluetooth ready - starting auto-reconnect scan")

                await self.startScanning()
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds to discover

                for remembered in rememberedDevices {
                    if let discovered = self.discoveredDevices.first(where: { $0.peripheralIdentifier?.uuidString == remembered.id }) {
                        do {
                            try await self.connect(to: discovered)
                            Logger.shared.info("[DeviceManager] Auto-reconnected to \(remembered.name)")
                            break // Successfully connected, stop trying
                        } catch {
                            Logger.shared.debug("[DeviceManager] Auto-reconnect failed for \(remembered.name): \(error.localizedDescription)")
                        }
                    }
                }

                self.stopScanning()
            }
        }
    }
}
