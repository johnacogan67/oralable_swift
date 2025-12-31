//
//  DeviceManager.swift
//  OralableApp
//
//  CORRECTED: November 11, 2025
//  Fixed: connect() method now uses correct UUID key
//  UPDATED: November 28, 2025 (Day 1 & Day 2)
//  Added: ConnectionReadiness state machine and async discovery methods
//  UPDATED: November 29, 2025 (Day 4 - Memory Fix + Diagnostic Logging)
//  Fixed: Auto-stop scanning when ready, prevent duplicate device instances, smart scan restart prevention
//  UPDATED: December 8, 2025 - Stricter device filtering (only Oralable and ANR)
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
    
    // MARK: - Private Properties

    private var devices: [UUID: BLEDeviceProtocol] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let maxDevices: Int = 5

    // BLE Integration - now using protocol for dependency injection
    private(set) var bleService: BLEService?

    // Legacy accessor for backward compatibility
    var bleManager: BLECentralManager? {
        bleService as? BLECentralManager
    }

    // Background worker for reconnection and polling
    private let backgroundWorker: BLEBackgroundWorker

    // Discovery tracking
    private var discoveryCount: Int = 0
    private var scanStartTime: Date?

    // Device persistence for auto-reconnect
    private let persistenceManager = DevicePersistenceManager.shared

    // Per-reading publisher (legacy, prefer batch)
    private let readingsSubject = PassthroughSubject<SensorReading, Never>()
    var readingsPublisher: AnyPublisher<SensorReading, Never> {
        readingsSubject.eraseToAnyPublisher()
    }

    // Batch publisher for efficient multi-reading delivery
    private let readingsBatchSubject = PassthroughSubject<[SensorReading], Never>()
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
    
    // MARK: - Device Discovery Handlers
    
    private func handleDeviceDiscovered(peripheral: CBPeripheral, name: String, rssi: Int) {
        discoveryCount += 1

        #if DEBUG
        Logger.shared.debug("[DeviceManager] Discovered device #\(discoveryCount): \(name) | RSSI: \(rssi) dBm")
        #endif

        // Check if already in discoveredDevices list (UI)
        if let index = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheral.identifier }) {
            // Just update RSSI for existing entry
            discoveredDevices[index].signalStrength = rssi
            Logger.shared.debug("[DeviceManager] ⏭️ Device already in list - updating RSSI only")
            return
        }

        // Detect device type - STRICT FILTERING
        guard let deviceType = detectDeviceType(from: name, peripheral: peripheral) else {
            Logger.shared.debug("[DeviceManager] ❌ Unknown device type '\(name)' - rejected")
            return
        }

        Logger.shared.info("[DeviceManager] ✅ Device discovered: \(name) (\(deviceType))")

        // Create device info for UI
        let deviceInfo = DeviceInfo(
            type: deviceType,
            name: name,
            peripheralIdentifier: peripheral.identifier,
            connectionState: .disconnected,
            signalStrength: rssi
        )

        // Always add to discovered list for UI display
        discoveredDevices.append(deviceInfo)
        Logger.shared.info("[DeviceManager] 📝 Device added to UI list. Total discovered: \(discoveredDevices.count)")
        
        // Initialize readiness state
        deviceReadiness[peripheral.identifier] = .disconnected

        // Only create new device instance if we don't already have one
        // (device instances persist across scans to maintain state)
        if devices[peripheral.identifier] == nil {
            let device: BLEDeviceProtocol

            switch deviceType {
            case .oralable:
                device = OralableDevice(peripheral: peripheral)
            case .anr:
                device = ANRMuscleSenseDevice(peripheral: peripheral, name: name)
            case .demo:
                #if DEBUG
                device = MockBLEDevice(type: .demo)
                #else
                device = OralableDevice(peripheral: peripheral)
                #endif
            }

            // Store device - KEY POINT: Using peripheral.identifier as the key
            devices[peripheral.identifier] = device
            Logger.shared.debug("[DeviceManager] 💾 New device instance created and stored")

            // Subscribe to device sensor readings
            subscribeToDevice(device)
        } else {
            Logger.shared.debug("[DeviceManager] 📦 Reusing existing device instance")
        }

        #if DEBUG
        Logger.shared.debug("[DeviceManager] 📊 Total devices in system:")
        Logger.shared.debug("[DeviceManager]    - discoveredDevices: \(discoveredDevices.count)")
        Logger.shared.debug("[DeviceManager]    - devices dictionary: \(devices.count)")
        #endif
    }
    
    // Day 1 & Day 2: Updated to use async discovery flow
    private func handleDeviceConnected(peripheral: CBPeripheral) {
        Logger.shared.info("[DeviceManager] Device connected: \(peripheral.name ?? "Unknown")")

        isConnecting = false

        // Notify background worker of successful connection (clears reconnection state)
        backgroundWorker.handleConnectionSuccess(for: peripheral.identifier)

        // Update connection readiness to .connected
        updateDeviceReadiness(peripheral.identifier, to: .connected)

        // Update device info
        if let index = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheral.identifier }) {
            discoveredDevices[index].connectionState = .connected

            // Add to connected devices if not already there
            if !connectedDevices.contains(where: { $0.id == discoveredDevices[index].id }) {
                connectedDevices.append(discoveredDevices[index])
            }

            // Set as primary if none set
            if primaryDevice == nil {
                primaryDevice = discoveredDevices[index]
            }

            // Remember this device for auto-reconnect
            persistenceManager.rememberDevice(
                id: peripheral.identifier.uuidString,
                name: discoveredDevices[index].name
            )
        }

        // Start RSSI polling for connected peripherals
        let connectedPeripherals = connectedDevices.compactMap { deviceInfo -> CBPeripheral? in
            guard let peripheralId = deviceInfo.peripheralIdentifier else { return nil }
            return devices[peripheralId]?.peripheral
        }
        backgroundWorker.startRSSIPolling(for: connectedPeripherals)

        // Start Day 2 async discovery flow
        Task {
            await discoverServicesAndCharacteristics(peripheral: peripheral)
        }
    }
    
    // Day 2: Async service and characteristic discovery with notification enabling
    private func discoverServicesAndCharacteristics(peripheral: CBPeripheral) async {
        guard let device = devices[peripheral.identifier] else {
            Logger.shared.error("[DeviceManager] ❌ Device not found in devices dictionary")
            return
        }
        
        do {
            // Step 1: Discover services (10-second timeout)
            updateDeviceReadiness(peripheral.identifier, to: .discoveringServices)
            try await withTimeout(seconds: 10) {
                try await device.discoverServices()
            }
            updateDeviceReadiness(peripheral.identifier, to: .servicesDiscovered)
            
            // Step 2: Discover characteristics (10-second timeout)
            updateDeviceReadiness(peripheral.identifier, to: .discoveringCharacteristics)
            try await withTimeout(seconds: 10) {
                try await device.discoverCharacteristics()
            }
            updateDeviceReadiness(peripheral.identifier, to: .characteristicsDiscovered)
            
            // Step 3: Enable notifications on main characteristic (10-second timeout)
            updateDeviceReadiness(peripheral.identifier, to: .enablingNotifications)
            try await withTimeout(seconds: 10) {
                try await device.enableNotifications()
            }
            
            // Step 4: Enable accelerometer notifications (non-blocking, no timeout)
            if let oralableDevice = device as? OralableDevice {
                await oralableDevice.enableAccelerometerNotifications()

                // Step 4b: Enable temperature notifications on 3A0FF003
                await oralableDevice.enableTemperatureNotifications()

                // Step 5: Configure PPG LEDs to turn them on
                do {
                    try await oralableDevice.configurePPGLEDs()
                } catch {
                    Logger.shared.warning("[DeviceManager] ⚠️ LED configuration failed (non-critical): \(error.localizedDescription)")
                }
            }

            // Device is now ready!
            updateDeviceReadiness(peripheral.identifier, to: .ready)
            Logger.shared.info("[DeviceManager] ✅ Device fully ready - all notifications enabled, LEDs configured")
            
        } catch {
            Logger.shared.error("[DeviceManager] ❌ Discovery failed: \(error.localizedDescription)")
            updateDeviceReadiness(peripheral.identifier, to: .failed(error.localizedDescription))
        }
    }
    
    // Day 1 & Day 4: Helper to update device readiness across all collections
    private func updateDeviceReadiness(_ peripheralId: UUID, to readiness: ConnectionReadiness) {
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
    
    // Day 2: Timeout helper for async operations (safe unwrap fix)
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Add the actual operation
            group.addTask {
                try await operation()
            }

            // Add a timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw DeviceError.timeout
            }

            // Return the first one to complete (safe unwrap)
            guard let result = try await group.next() else {
                throw DeviceError.timeout
            }
            group.cancelAll()
            return result
        }
    }
    
    private func handleDeviceDisconnected(peripheral: CBPeripheral, error: Error?) {
        let wasUnexpectedDisconnection = error != nil

        if let error = error {
            Logger.shared.warning("[DeviceManager] Device disconnected with error: \(error.localizedDescription)")
            lastError = .connectionLost
        } else {
            Logger.shared.info("[DeviceManager] Device disconnected: \(peripheral.name ?? "Unknown")")
        }

        isConnecting = false

        // Update readiness state
        updateDeviceReadiness(peripheral.identifier, to: .disconnected)

        // Update device states
        if let index = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheral.identifier }) {
            discoveredDevices[index].connectionState = .disconnected
        }

        connectedDevices.removeAll { $0.peripheralIdentifier == peripheral.identifier }

        if primaryDevice?.peripheralIdentifier == peripheral.identifier {
            primaryDevice = connectedDevices.first
        }

        // Delegate reconnection to background worker
        backgroundWorker.handleDisconnection(
            for: peripheral.identifier,
            peripheral: peripheral,
            wasUnexpected: wasUnexpectedDisconnection
        )
    }

    /// Cancel all ongoing reconnection attempts
    func cancelAllReconnections() {
        backgroundWorker.cancelAllReconnections()
        Logger.shared.debug("[DeviceManager] Cancelled all reconnection attempts via background worker")
    }
    
    // MARK: - Device Type Detection
    // UPDATED: December 8, 2025 - Stricter filtering to only accept Oralable and ANR devices
    
    private func detectDeviceType(from name: String, peripheral: CBPeripheral) -> DeviceType? {
        let lowercaseName = name.lowercased()

        // Check for Oralable device - STRICT matching
        if lowercaseName.contains("oralable") {
            Logger.shared.info("[DeviceManager] ✅ Detected Oralable device: \(name)")
            return .oralable
        }

        // Check for ANR M40 device - STRICT matching
        if lowercaseName.contains("anr") || lowercaseName.contains("m40") {
            Logger.shared.info("[DeviceManager] ✅ Detected ANR device: \(name)")
            return .anr
        }

        // Reject all other devices
        Logger.shared.debug("[DeviceManager] ❌ Rejecting unknown device: \(name)")
        return nil
    }
    
    // MARK: - Device Discovery
    
    /// Start scanning for devices
    func startScanning() async {
        Logger.shared.info("[DeviceManager] 🔍 startScanning() called")
        Logger.shared.info("[DeviceManager] Current state - discoveredDevices: \(discoveredDevices.count), devices: \(devices.count)")

        // Day 4 Fix: Don't scan if we already have a ready device (but allow demo device discovery)
        if deviceReadiness.values.contains(.ready) && !FeatureFlags.shared.demoModeEnabled {
            Logger.shared.info("[DeviceManager] 🛑 Already have ready device - skipping scan")
            return
        }

        // Don't restart if already scanning
        if isScanning {
            Logger.shared.info("[DeviceManager] 🛑 Already scanning - skipping")
            return
        }

        Logger.shared.info("[DeviceManager] Starting device scan")

        scanStartTime = Date()
        discoveryCount = 0
        discoveredDevices.removeAll()
        deviceReadiness.removeAll()
        isScanning = true

        Logger.shared.info("[DeviceManager] ✅ Scan started - discoveredDevices cleared, isScanning = true")

        bleService?.startScanning(services: nil)

        // If demo mode enabled, also "discover" the demo device
        if FeatureFlags.shared.demoModeEnabled {
            Logger.shared.info("[DeviceManager] 🎭 Demo mode enabled - triggering demo device discovery")

            // Add demo device to discoveredDevices after short delay (simulates discovery)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }

                // Create a demo device entry using the fixed UUID
                let demoUUID = UUID(uuidString: "DEADBEEF-DEMO-0001-0000-000000000001") ?? UUID()

                let demoDevice = DeviceInfo(
                    type: .demo,
                    name: DemoDataProvider.shared.deviceName,
                    peripheralIdentifier: demoUUID,
                    connectionState: .disconnected,
                    signalStrength: -50
                )

                // Add to discovered devices list (same list the UI displays)
                if !self.discoveredDevices.contains(where: { $0.type == .demo }) {
                    self.discoveredDevices.append(demoDevice)
                    DemoDataProvider.shared.isDiscovered = true
                    Logger.shared.info("[DeviceManager] 🎭 Demo device added to discoveredDevices (count: \(self.discoveredDevices.count))")
                }
            }
        }
    }

    /// Stop scanning for devices
    func stopScanning() {
        Logger.shared.info("[DeviceManager] 🛑 stopScanning() called")
        Logger.shared.info("[DeviceManager] Discovered devices at stop time: \(discoveredDevices.count)")

        #if DEBUG
        if let scanStart = scanStartTime {
            let elapsed = Date().timeIntervalSince(scanStart)
            Logger.shared.debug("[DeviceManager] Scan stopped | Duration: \(String(format: "%.1f", elapsed))s | Devices found: \(discoveredDevices.count)")
        }
        #endif

        isScanning = false
        bleService?.stopScanning()
        scanStartTime = nil

        // Note: Don't reset demo discovery state here - we want to keep the demo device
        // visible after scanning stops so user can still connect to it

        Logger.shared.info("[DeviceManager] ✅ Scan stopped - isScanning = false")
    }
    
    // MARK: - Connection Management
    
    // ✅ CORRECTED METHOD - Using peripheralIdentifier as dictionary key
    func connect(to deviceInfo: DeviceInfo) async throws {
        Logger.shared.info("[DeviceManager] Connecting to device: \(deviceInfo.name)")

        // Check if this is the demo device
        if deviceInfo.type == .demo {
            Logger.shared.info("[DeviceManager] 🎭 Connecting to demo device")
            isConnecting = true

            // Update device state to connecting
            if let index = discoveredDevices.firstIndex(where: { $0.type == .demo }) {
                discoveredDevices[index].connectionState = .connecting
            }

            // Start playback (connection happens after delay in simulateConnect)
            DemoDataProvider.shared.simulateConnect()

            // Wait for connection to complete
            try await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds

            // Move demo device from discovered to connected
            if let index = discoveredDevices.firstIndex(where: { $0.type == .demo }) {
                var connectedDemo = discoveredDevices[index]
                connectedDemo.connectionState = .connected
                connectedDemo.connectionReadiness = .ready

                // Add to connected devices
                if !connectedDevices.contains(where: { $0.type == .demo }) {
                    connectedDevices.append(connectedDemo)
                }

                // Remove from discovered
                discoveredDevices.remove(at: index)
            }

            isConnecting = false
            Logger.shared.info("[DeviceManager] 🎭 Demo device connected and moved to connectedDevices")
            return
        }

        // CRITICAL FIX: Use peripheralIdentifier, not deviceInfo.id
        guard let peripheralId = deviceInfo.peripheralIdentifier else {
            throw DeviceError.invalidPeripheral("Device has no peripheral identifier")
        }

        guard let device = devices[peripheralId] else {
            Logger.shared.error("[DeviceManager] Device not found in registry")
            throw DeviceError.invalidPeripheral("Device not found in registry")
        }

        guard let peripheral = device.peripheral else {
            throw DeviceError.invalidPeripheral("Device has no peripheral")
        }

        isConnecting = true

        // Update state
        if let index = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheralId }) {
            discoveredDevices[index].connectionState = .connecting
        }

        updateDeviceReadiness(peripheralId, to: .connecting)

        // Cancel any existing reconnection attempts on manual connect
        backgroundWorker.cancelReconnection(for: peripheralId)

        // Connect via BLE manager
        bleService?.connect(to: peripheral)
    }
    
    func disconnect(from deviceInfo: DeviceInfo) async {
        Logger.shared.info("[DeviceManager] Disconnecting from device: \(deviceInfo.name)")

        // Check if this is the demo device
        if deviceInfo.type == .demo {
            Logger.shared.info("[DeviceManager] 🎭 Disconnecting from demo device")
            DemoDataProvider.shared.disconnect()

            // Remove from connected devices
            connectedDevices.removeAll { $0.type == .demo }
            Logger.shared.info("[DeviceManager] 🎭 Demo device removed from connectedDevices")
            return
        }

        guard let peripheralId = deviceInfo.peripheralIdentifier,
              let device = devices[peripheralId],
              let peripheral = device.peripheral else {
            Logger.shared.error("[DeviceManager] Device or peripheral not found")
            return
        }

        // Cancel any pending reconnection attempts for this device via background worker
        backgroundWorker.cancelReconnection(for: peripheralId)

        // Cancel pending continuations to prevent hangs
        if let oralableDevice = device as? OralableDevice {
            oralableDevice.cancelPendingContinuations()
        }

        bleService?.disconnect(from: peripheral)

        // Stop data collection
        try? await device.stopDataCollection()
    }

    func disconnectAll() {
        Logger.shared.info("[DeviceManager] Disconnecting all devices")

        for deviceInfo in connectedDevices {
            Task {
                await disconnect(from: deviceInfo)
            }
        }

        // Also disconnect demo device if connected
        if DemoDataProvider.shared.isConnected {
            Logger.shared.info("[DeviceManager] 🎭 Also disconnecting demo device")
            DemoDataProvider.shared.disconnect()
            DemoDataProvider.shared.resetDiscovery()
            connectedDevices.removeAll { $0.type == .demo }
            discoveredDevices.removeAll { $0.type == .demo }
        }

        // Cancel all reconnection attempts
        cancelAllReconnections()
    }

    /// Disconnect demo device and reset its state (called when demo mode is disabled)
    func disconnectDemoDevice() {
        if DemoDataProvider.shared.isConnected {
            Logger.shared.info("[DeviceManager] 🎭 Disconnecting demo device (demo mode disabled)")
            DemoDataProvider.shared.disconnect()
        }
        DemoDataProvider.shared.resetDiscovery()

        // Remove demo device from both lists
        connectedDevices.removeAll { $0.type == .demo }
        discoveredDevices.removeAll { $0.type == .demo }
    }
    
    // MARK: - Sensor Data Management
    
    private func subscribeToDevice(_ device: BLEDeviceProtocol) {
        Logger.shared.debug("[DeviceManager] subscribeToDevice")
        Logger.shared.debug("[DeviceManager] Device: \(device.deviceInfo.name)")

        // Subscribe to batch publisher for efficient multi-reading delivery
        device.sensorReadingsBatch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] readings in
                self?.handleSensorReadingsBatch(readings, from: device)
            }
            .store(in: &cancellables)

        Logger.shared.debug("[DeviceManager] Batch subscription created")
    }
    
    private func handleSensorReading(_ reading: SensorReading, from device: BLEDeviceProtocol) {
        // Add to all readings
        allSensorReadings.append(reading)

        // Update latest readings
        latestReadings[reading.sensorType] = reading

        // Emit per-reading for streaming consumers
        readingsSubject.send(reading)

        // Trim history if needed (keep last 1000)
        if allSensorReadings.count > 1000 {
            allSensorReadings.removeFirst(100)
        }
    }

    private func handleSensorReadingsBatch(_ readings: [SensorReading], from device: BLEDeviceProtocol) {
        Logger.shared.info("[DeviceManager] 📥 Received batch: \(readings.count) readings from \(device.deviceInfo.name)")

        // Add to all readings
        allSensorReadings.append(contentsOf: readings)

        // PERFORMANCE FIX: Batch update to prevent UI flooding
        // First collect latest per type, then update latestReadings once per type
        var latestByType: [SensorType: SensorReading] = [:]
        for reading in readings {
            latestByType[reading.sensorType] = reading
        }

        // Single batch update (triggers publisher once per type, not per reading)
        for (type, reading) in latestByType {
            latestReadings[type] = reading
        }

        Logger.shared.info("[DeviceManager] 📊 Updated latestReadings: \(latestByType.count) types - \(latestByType.keys.map { $0.rawValue }.joined(separator: ", "))")

        // Emit batch for efficient downstream processing
        readingsBatchSubject.send(readings)

        // Trim history if needed (keep last 1000)
        if allSensorReadings.count > 1000 {
            let removeCount = allSensorReadings.count - 1000
            allSensorReadings.removeFirst(removeCount)
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
