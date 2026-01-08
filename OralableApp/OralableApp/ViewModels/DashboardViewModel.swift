//
//  DashboardViewModel.swift
//  OralableApp
//
//  Complete ViewModel with MAM state detection
//  Updated: December 7, 2025 - Added dual-device support (Oralable + ANR M40)
//

import SwiftUI
import Combine
import CoreBluetooth
import Foundation
import OralableCore

@MainActor
class DashboardViewModel: ObservableObject {
    // MARK: - Published Properties

    // Connection State (throttled from BLE manager)
    @Published var isConnected: Bool = false
    @Published var deviceName: String = ""
    @Published var batteryLevel: Double = 0.0
    @Published var connectedDeviceType: DeviceType? = nil

    // MARK: - Dual Device Connection Status
    @Published var oralableConnected: Bool = false
    @Published var anrConnected: Bool = false
    @Published var anrFailed: Bool = false

    // MARK: - Dual Device Sensor Values
    @Published var ppgIRValue: Double = 0.0      // IR sensor value from Oralable
    @Published var emgValue: Double = 0.0        // EMG value from ANR M40
    @Published var ppgHistory: [Double] = []     // PPG sparkline data
    @Published var emgHistory: [Double] = []     // EMG sparkline data

    // Metrics
    @Published var heartRate: Int = 0
    @Published var spO2: Int = 0
    @Published var temperature: Double = 0.0
    @Published var signalQuality: Int = 0
    @Published var sessionDuration: String = "00:00"

    // MAM States (Movement, Adhesion, Monitoring)
    @Published var isCharging: Bool = false
    @Published var isMoving: Bool = false
    @Published var positionQuality: String = "Good" // "Good", "Adjust", "Off"

    // Movement metrics (numeric values for display)
    @Published var movementValue: Double = 0.0       // Average movement magnitude
    @Published var movementVariability: Double = 0.0 // Movement variability (determines active/still)

    // Accelerometer in g-units (for AccelerometerCardView)
    @Published var accelXRaw: Int16 = 0
    @Published var accelYRaw: Int16 = 0
    @Published var accelZRaw: Int16 = 0

    /// Accelerometer magnitude in g units
    var accelerometerMagnitudeG: Double {
        AccelerometerConversion.magnitude(x: accelXRaw, y: accelYRaw, z: accelZRaw)
    }

    /// Whether device is at rest (magnitude ~1g)
    var isAtRest: Bool {
        AccelerometerConversion.isAtRest(x: accelXRaw, y: accelYRaw, z: accelZRaw)
    }

    /// Movement threshold from user settings (dynamically updated)
    private var movementActiveThreshold: Double {
        ThresholdSettings.shared.movementThreshold
    }

    // Device State Detection
    @Published var deviceStateDescription: String = "Unknown"
    @Published var deviceStateConfidence: Double = 0.0

    // Waveform Data
    @Published var ppgData: [Double] = []
    @Published var accelerometerData: [Double] = []

    // Muscle Activity (derived from PPG IR or EMG)
    @Published var muscleActivity: Double = 0.0
    @Published var muscleActivityHistory: [Double] = []

    // Recording state from coordinator (read-only binding)
    @Published private(set) var isRecording: Bool = false

    /// Formatted duration string for recording button display (MM:SS)
    var formattedDuration: String {
        sessionDuration
    }

    // MARK: - Event Recording
    @Published private(set) var eventCount: Int = 0
    @Published private(set) var discardedEventCount: Int = 0
    private var eventSession: EventRecordingSession?

    // MARK: - Heart Rate & Worn Status
    @Published var currentHRResult: HeartRateService.HRResult?
    @Published var wornStatus: WornStatus = .initializing

    // MARK: - Device-Specific Display Labels

    /// Label for the muscle activity card based on connected device type
    var muscleActivityLabel: String {
        switch connectedDeviceType {
        case .anr:
            return "EMG Activity"
        case .oralable:
            return "Muscle Activity"
        default:
            return "Muscle Activity"
        }
    }

    /// Subtitle showing signal source
    var signalSourceLabel: String {
        switch connectedDeviceType {
        case .anr:
            return "ANR M40 EMG"
        case .oralable:
            return "Oralable IR"
        default:
            return ""
        }
    }

    /// Icon for the muscle activity card
    var muscleActivityIcon: String {
        switch connectedDeviceType {
        case .anr:
            return "bolt.horizontal.circle.fill"
        case .oralable:
            return "waveform.path.ecg"
        default:
            return "waveform.path.ecg"
        }
    }

    // MARK: - Private Properties
    private let deviceManagerAdapter: DeviceManagerAdapter
    private let deviceManager: DeviceManager
    private let appStateManager: AppStateManager
    private let recordingStateCoordinator: RecordingStateCoordinator
    private var cancellables = Set<AnyCancellable>()
    private let heartRateService = HeartRateService()

    // MARK: - Demo Mode Properties
    private let featureFlags = FeatureFlags.shared
    private let demoDataProvider = DemoDataProvider.shared
    private var demoCancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(deviceManagerAdapter: DeviceManagerAdapter,
         deviceManager: DeviceManager,
         appStateManager: AppStateManager,
         recordingStateCoordinator: RecordingStateCoordinator) {
        self.deviceManagerAdapter = deviceManagerAdapter
        self.deviceManager = deviceManager
        self.appStateManager = appStateManager
        self.recordingStateCoordinator = recordingStateCoordinator
        setupBindings()
        Logger.shared.info("[DashboardViewModel] ✅ Initialized with RecordingStateCoordinator")
    }

    deinit {
        Logger.shared.info("[DashboardViewModel] deinit - cleaning up subscriptions")
    }

    // MARK: - Public Methods
    func startMonitoring() {
        setupBLESubscriptions()
        Logger.shared.info("[DashboardViewModel] ✅ Monitoring started - waiting for real device data")
    }

    func stopMonitoring() {
        // Subscriptions cleaned up via cancellables
    }

    func startRecording() {
        recordingStateCoordinator.startRecording()
        startEventRecording()
    }

    func stopRecording() {
        recordingStateCoordinator.stopRecording()
        stopEventRecording()
    }

    // MARK: - Event Recording

    /// Start event recording with current threshold settings
    func startEventRecording() {
        eventSession = EventRecordingSession(threshold: EventSettings.shared.threshold)
        eventSession?.startRecording()
        eventCount = 0
        discardedEventCount = 0
        Logger.shared.info("[DashboardViewModel] Event recording started with threshold: \(EventSettings.shared.threshold)")
    }

    /// Stop event recording
    func stopEventRecording() {
        eventSession?.stopRecording()
        Logger.shared.info("[DashboardViewModel] Event recording stopped. Events: \(eventCount), Discarded: \(discardedEventCount)")
    }

    /// Get export options based on enabled dashboard cards
    func getEventExportOptions() -> EventCSVExporter.ExportOptions {
        EventCSVExporter.ExportOptions(
            includeTemperature: featureFlags.showTemperatureCard,
            includeHR: featureFlags.showHeartRateCard,
            includeSpO2: featureFlags.showSpO2Card,
            includeSleep: false // Sleep not currently tracked
        )
    }

    /// Export recorded events to a file
    /// - Returns: URL of the exported file, or nil if no events
    func exportEvents() throws -> URL? {
        guard let session = eventSession, !session.events.isEmpty else {
            Logger.shared.info("[DashboardViewModel] No events to export")
            return nil
        }

        let options = getEventExportOptions()
        let userIdentifier = UserDefaults.standard.string(forKey: "userID")
        let fileURL = try session.exportToTempFile(options: options, userIdentifier: userIdentifier)
        Logger.shared.info("[DashboardViewModel] Events exported to: \(fileURL.lastPathComponent)")
        return fileURL
    }

    /// Get the current event session for direct access
    var currentEventSession: EventRecordingSession? {
        eventSession
    }

    func disconnect() {
        Task {
            if let device = deviceManager.primaryDevice,
               let peripheralId = device.peripheralIdentifier {
                await deviceManager.disconnect(from: DeviceInfo(
                    type: device.type,
                    name: device.name,
                    peripheralIdentifier: peripheralId,
                    connectionState: .connected
                ))
            }
        }
    }

    func startScanning() {
        Task {
            await deviceManager.startScanning()
        }
    }

    // MARK: - Private Methods
    private func setupBindings() {
        // Setup demo mode subscription
        setupDemoModeSubscription()

        // Subscribe to threshold changes for live UI updates
        ThresholdSettings.shared.$movementThreshold
            .sink { [weak self] newThreshold in
                guard let self = self else { return }
                self.isMoving = self.movementVariability > newThreshold
            }
            .store(in: &cancellables)

        // Bind recording state from coordinator (single source of truth)
        recordingStateCoordinator.$isRecording
            .assign(to: &$isRecording)

        // Bind session duration from coordinator
        recordingStateCoordinator.$sessionDuration
            .map { duration -> String in
                let minutes = Int(duration / 60)
                let seconds = Int(duration) % 60
                return String(format: "%02d:%02d", minutes, seconds)
            }
            .assign(to: &$sessionDuration)

        // Connection state from DeviceManager - track both devices separately
        deviceManager.$connectedDevices
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] devices in
                guard let self = self else { return }
                let wasConnected = self.isConnected
                self.isConnected = !devices.isEmpty

                // Track each device type separately for dual-device UI
                self.oralableConnected = devices.contains { $0.type == .oralable }
                self.anrConnected = devices.contains { $0.type == .anr }

                // Track connected device type for UI differentiation (primary device)
                if let primaryDevice = devices.first {
                    self.connectedDeviceType = primaryDevice.type
                    Logger.shared.info("[DashboardViewModel] 📱 Connected devices: Oralable=\(self.oralableConnected), ANR=\(self.anrConnected)")
                } else {
                    self.connectedDeviceType = nil
                }

                Logger.shared.debug("[DashboardViewModel] connectedDevices changed: \(devices.count) devices, isConnected: \(self.isConnected)")
                if wasConnected && !self.isConnected {
                    self.resetMetrics()
                }
            }
            .store(in: &cancellables)

        // Track device readiness changes for logging
                deviceManager.$deviceReadiness
                    .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
                    .sink { [weak self] readiness in
                        guard let self = self else { return }
                        let primaryReadiness = self.deviceManager.primaryDeviceReadiness
                        Logger.shared.debug("[DashboardViewModel] deviceReadiness changed: primary=\(primaryReadiness)")
                        
                        // Reset anrFailed when ANR connects successfully
                        if self.anrConnected {
                            self.anrFailed = false
                        }
                    }
                    .store(in: &cancellables)

        // Device name from primary device
        deviceManager.$primaryDevice
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] device in
                self?.deviceName = device?.name ?? ""
            }
            .store(in: &cancellables)

        // Battery level (throttled)
        deviceManagerAdapter.batteryLevelPublisher
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] level in
                self?.batteryLevel = level
            }
            .store(in: &cancellables)

        // Device state from DeviceStateDetector
        deviceManagerAdapter.deviceStatePublisher
            .sink { [weak self] stateResult in
                guard let self = self, let stateResult = stateResult else { return }
                self.updateMAMStates(from: stateResult)
            }
            .store(in: &cancellables)
    }

    private func setupBLESubscriptions() {
        // Subscribe to Heart Rate
        deviceManagerAdapter.heartRatePublisher
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] hr in
                self?.heartRate = hr
            }
            .store(in: &cancellables)

        // Subscribe to SpO2
        deviceManagerAdapter.spO2Publisher
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] spo2 in
                self?.spO2 = spo2
            }
            .store(in: &cancellables)

        // Subscribe to PPG IR data for Oralable card
        deviceManagerAdapter.ppgIRValuePublisher
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] value in
                self?.processPPGIRData(value)
            }
            .store(in: &cancellables)

        // Subscribe to PPG Red data for waveform (legacy)
        deviceManagerAdapter.ppgRedValuePublisher
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] value in
                self?.processPPGData(value)
            }
            .store(in: &cancellables)

        // Subscribe to EMG data for ANR M40 card
        deviceManagerAdapter.emgValuePublisher
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] value in
                self?.processEMGData(value)
            }
            .store(in: &cancellables)

        // Subscribe to accelerometer data
        deviceManagerAdapter.accelXPublisher
            .combineLatest(deviceManagerAdapter.accelYPublisher, deviceManagerAdapter.accelZPublisher)
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] x, y, z in
                self?.processAccelerometerData(x: x, y: y, z: z)
            }
            .store(in: &cancellables)

        // Subscribe to temperature
        deviceManagerAdapter.temperaturePublisher
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] temp in
                self?.temperature = temp
            }
            .store(in: &cancellables)

        // Subscribe to HR quality for signal quality display
        deviceManagerAdapter.heartRateQualityPublisher
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] quality in
                self?.signalQuality = Int(quality * 100)
            }
            .store(in: &cancellables)

        // Create a publisher for accelerometer magnitude in G's
        let accelMagnitudePublisher = deviceManagerAdapter.accelXPublisher
            .combineLatest(deviceManagerAdapter.accelYPublisher, deviceManagerAdapter.accelZPublisher)
            .map { x, y, z -> Double in
                // Convert raw accelerometer values to G's before calculating magnitude
                let xG = AccelerometerConversion.toG(rawValue: Int16(clamping: Int(x)))
                let yG = AccelerometerConversion.toG(rawValue: Int16(clamping: Int(y)))
                let zG = AccelerometerConversion.toG(rawValue: Int16(clamping: Int(z)))
                return sqrt(xG*xG + yG*yG + zG*zG)
            }
            .eraseToAnyPublisher()

        // Zip PPG IR stream with accelerometer magnitude stream, collect 100 samples, and process
        deviceManagerAdapter.ppgIRValuePublisher
            .zip(accelMagnitudePublisher)
            .collect(100)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] samples in
                let irSamples = samples.map { $0.0 }
                let accelMagnitudes = samples.map { $0.1 }
                self?.updateHeartRate(with: irSamples, accelMagnitudes: accelMagnitudes)
            }
            .store(in: &cancellables)
    }

    // MARK: - PPG IR Data Processing (Oralable)
    private func processPPGIRData(_ value: Double) {
        ppgIRValue = value

        ppgHistory.append(value)
        if ppgHistory.count > 20 {
            ppgHistory.removeFirst()
        }

        // Also update legacy muscle activity if Oralable is the primary device
        if connectedDeviceType == .oralable {
            muscleActivity = value
            muscleActivityHistory.append(value)
            if muscleActivityHistory.count > 20 {
                muscleActivityHistory.removeFirst()
            }
        }

        // Feed data to event detector for event-based recording
        feedSampleToEventDetector(irValue: Int(value))
    }

    /// Feed sample data to the event detector
    private func feedSampleToEventDetector(irValue: Int) {
        guard let session = eventSession, session.isRecording else { return }

        session.processSample(
            irValue: irValue,
            timestamp: Date(),
            accelX: Int(accelXRaw),
            accelY: Int(accelYRaw),
            accelZ: Int(accelZRaw),
            temperature: temperature
        )

        // Update metrics for event validation
        if heartRate > 0 {
            session.updateHR(Double(heartRate))
        }
        if spO2 > 0 {
            session.updateSpO2(Double(spO2))
        }
        // Temperature is always passed - validation checks 32-38°C range
        session.updateTemperature(temperature)

        // Update event counts
        eventCount = session.eventCount
        discardedCount = session.discardedCount
    }

    /// Discarded event count (alias for consistency)
    private var discardedCount: Int {
        get { discardedEventCount }
        set { discardedEventCount = newValue }
    }

    // MARK: - EMG Data Processing (ANR M40)
    private func processEMGData(_ value: Double) {
        emgValue = value

        emgHistory.append(value)
        if emgHistory.count > 20 {
            emgHistory.removeFirst()
        }

        // Also update legacy muscle activity if ANR is the primary device
        if connectedDeviceType == .anr {
            muscleActivity = value
            muscleActivityHistory.append(value)
            if muscleActivityHistory.count > 20 {
                muscleActivityHistory.removeFirst()
            }
        }
    }

    private func processPPGData(_ value: Double) {
        ppgData.append(value)
        if ppgData.count > 100 {
            ppgData.removeFirst()
        }

        // Legacy: only update muscle activity from PPG Red if no IR data flowing
        if ppgIRValue == 0 && connectedDeviceType == .oralable {
            muscleActivity = value
            muscleActivityHistory.append(value)
            if muscleActivityHistory.count > 20 {
                muscleActivityHistory.removeFirst()
            }
        }
    }

    private func processAccelerometerData(x: Double, y: Double, z: Double) {
        accelXRaw = Int16(clamping: Int(x))
        accelYRaw = Int16(clamping: Int(y))
        accelZRaw = Int16(clamping: Int(z))

        let magnitude = sqrt(x*x + y*y + z*z)

        accelerometerData.append(magnitude)
        if accelerometerData.count > 100 {
            accelerometerData.removeFirst()
        }

        movementValue = magnitude

        if accelerometerData.count >= 10 {
            let recentSamples = Array(accelerometerData.suffix(20))
            let mean = recentSamples.reduce(0, +) / Double(recentSamples.count)
            let variance = recentSamples.map { pow($0 - mean, 2) }.reduce(0, +) / Double(recentSamples.count)
            movementVariability = sqrt(variance)
            isMoving = movementVariability > movementActiveThreshold
        }
    }

    private func updateMAMStates(from stateResult: DeviceStateResult) {
        deviceStateDescription = stateResult.state.rawValue
        deviceStateConfidence = stateResult.confidence

        switch stateResult.state {
        case .onChargerStatic:
            isCharging = true
            positionQuality = "Off"
        case .offChargerStatic:
            isCharging = false
            positionQuality = "Off"
        case .inMotion:
            isCharging = false
            positionQuality = "Adjust"
        case .onCheek:
            isCharging = false
            if stateResult.confidence >= 0.8 {
                positionQuality = "Good"
            } else if stateResult.confidence >= 0.6 {
                positionQuality = "Adjust"
            } else {
                positionQuality = "Off"
            }
        case .unknown:
            isCharging = false
            positionQuality = "Off"
        }
    }

    private func resetMetrics() {
        heartRate = 0
        spO2 = 0
        temperature = 0.0
        signalQuality = 0
        ppgData = []
        accelerometerData = []
        muscleActivity = 0.0
        muscleActivityHistory = []
        isMoving = false
        movementValue = 0.0
        movementVariability = 0.0
        accelXRaw = 0
        accelYRaw = 0
        accelZRaw = 0
        positionQuality = "Off"
        deviceStateDescription = "Unknown"
        deviceStateConfidence = 0.0

        // Reset dual-device specific values
        ppgIRValue = 0.0
        emgValue = 0.0
        ppgHistory = []
        emgHistory = []
        oralableConnected = false
        anrConnected = false
        anrFailed = false
    }

    // MARK: - Demo Mode
    private func setupDemoModeSubscription() {
        // Watch for demo device connection state changes (primary trigger for demo data flow)
        demoDataProvider.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                Logger.shared.info("[DashboardViewModel] Demo device connection changed: \(isConnected)")
                if isConnected {
                    self?.startDemoMode()
                } else {
                    self?.stopDemoMode()
                }
            }
            .store(in: &demoCancellables)

        // Also watch for demo mode toggle to disconnect if disabled
        featureFlags.$demoModeEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                Logger.shared.info("[DashboardViewModel] Demo mode flag changed: \(enabled)")
                if !enabled {
                    // Demo mode disabled - disconnect demo device
                    DemoDataProvider.shared.disconnect()
                    DemoDataProvider.shared.resetDiscovery()
                    self?.stopDemoMode()
                }
            }
            .store(in: &demoCancellables)

        // Subscribe to demo PPG data
        // Use dropFirst to skip initial value, then receive on main thread
        demoDataProvider.$currentPPGIR
            .dropFirst() // Skip initial 0 value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self = self else { return }
                guard FeatureFlags.shared.demoModeEnabled else { return }
                Logger.shared.debug("[DashboardViewModel] Demo PPG IR received: \(Int(value))")
                self.processPPGIRData(value)
            }
            .store(in: &demoCancellables)

        // Subscribe to demo accelerometer data (already in raw LSB units from CSV)
        demoDataProvider.$currentAccelX
            .combineLatest(demoDataProvider.$currentAccelY, demoDataProvider.$currentAccelZ)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] x, y, z in
                guard let self = self else { return }
                guard FeatureFlags.shared.demoModeEnabled else { return }
                // CSV data is already in raw accelerometer values (LSB)
                self.processAccelerometerData(x: x, y: y, z: z)
            }
            .store(in: &demoCancellables)

        // Subscribe to demo temperature
        demoDataProvider.$currentTemperature
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] temp in
                guard let self = self else { return }
                guard FeatureFlags.shared.demoModeEnabled else { return }
                self.temperature = temp
            }
            .store(in: &demoCancellables)

        // Subscribe to demo heart rate
        demoDataProvider.$currentHeartRate
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hr in
                guard let self = self else { return }
                guard FeatureFlags.shared.demoModeEnabled else { return }
                self.heartRate = hr
            }
            .store(in: &demoCancellables)

        // Subscribe to demo SpO2
        demoDataProvider.$currentSpO2
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spo2 in
                guard let self = self else { return }
                guard FeatureFlags.shared.demoModeEnabled else { return }
                self.spO2 = Int(spo2)
            }
            .store(in: &demoCancellables)

        // Subscribe to demo battery
        demoDataProvider.$currentBattery
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] battery in
                guard let self = self else { return }
                guard FeatureFlags.shared.demoModeEnabled else { return }
                self.batteryLevel = Double(battery)
            }
            .store(in: &demoCancellables)
    }

    private func startDemoMode() {
        // Set demo device as connected (playback is already started by simulateConnect)
        oralableConnected = true
        isConnected = true
        connectedDeviceType = .demo
        deviceName = demoDataProvider.deviceName

        Logger.shared.info("[DashboardViewModel] Demo mode started - device connected")
    }

    private func stopDemoMode() {
        // Playback is stopped by disconnect() method

        // Only reset connection state if no real device is connected
        if deviceManager.connectedDevices.isEmpty {
            oralableConnected = false
            isConnected = false
            connectedDeviceType = nil
            deviceName = ""
        }

        Logger.shared.info("[DashboardViewModel] Demo mode stopped - device disconnected")
    }
}

/// Extension to handle real-time HR integration in the Dashboard.
extension DashboardViewModel {
    
    func toggleRecording() {
        recordingStateCoordinator.toggleRecording()
    }
    
    // Call this inside your SensorDataProcessor subscription
    func updateHeartRate(with rawIRSamples: [Double], accelMagnitudes: [Double]) {
        let result = heartRateService.process(samples: rawIRSamples)
        self.currentHRResult = result
        
        // Map boolean isWorn to WornStatus enum
        if result.confidence < 0.3 {
            self.wornStatus = .initializing
        } else if result.isWorn {
            self.wornStatus = .active
        } else {
            self.wornStatus = .repositioning
        }
    }
}
