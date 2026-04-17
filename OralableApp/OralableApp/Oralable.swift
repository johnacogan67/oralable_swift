import SwiftUI
import OralableCore

@main
struct OralableApp: App {
    // Core managers - recording is automatic via DeviceManager.automaticRecordingSession
    @StateObject private var authenticationManager: AuthenticationManager
    @StateObject private var sensorDataStore: SensorDataStore
    @StateObject private var recordingSessionManager: RecordingSessionManager
    @StateObject private var historicalDataManager: HistoricalDataManager
    @StateObject private var subscriptionManager: SubscriptionManager
    @StateObject private var deviceManager: DeviceManager
    @StateObject private var sensorDataProcessor: SensorDataProcessor
    @StateObject private var appStateManager: AppStateManager
    @StateObject private var sharedDataManager: SharedDataManager
    @StateObject private var designSystem: DesignSystem
    @StateObject private var dependencies: AppDependencies
    @StateObject private var firstLaunchManager = FirstLaunchManager()

    init() {
        let authenticationManager = AuthenticationManager()
        let sensorDataStore = SensorDataStore()
        let sessionHistoryStore = SessionHistoryStore()
        let recordingSessionManager = RecordingSessionManager()
        recordingSessionManager.sessionHistoryStore = sessionHistoryStore
        let sensorDataProcessor = SensorDataProcessor.shared
        let historicalDataManager = HistoricalDataManager(
            sensorDataProcessor: sensorDataProcessor
        )
        let subscriptionManager = SubscriptionManager()
        let deviceManager = DeviceManager()
        sessionHistoryStore.attach(recordingManager: recordingSessionManager, deviceManager: deviceManager)
        let appStateManager = AppStateManager()
        let sharedDataManager = SharedDataManager(
            authenticationManager: authenticationManager,
            sensorDataProcessor: sensorDataProcessor
        )
        let designSystem = DesignSystem()

        // Configure automatic recording session to sync to CloudKit on disconnect.
        // Run at utility priority after a short delay, then wait until the central is not
        // mid reconnect/GATT handshake — otherwise JSON compression + CloudKit overlaps
        // the same window as discoverServices/notifications (see device logs: sync_ck + BLETrace).
        deviceManager.automaticRecordingSession?.onSyncRequested = {
            Task(priority: .utility) {
                try? await Task.sleep(for: .seconds(2))
                await waitUntilBleIdleForCloudKitSync(deviceManager: deviceManager)
                await sharedDataManager.uploadCurrentDataForSharing()
            }
        }

        // Create AppDependencies with automatic recording support
        let dependencies = AppDependencies(
            authenticationManager: authenticationManager,
            recordingSessionManager: recordingSessionManager,
            historicalDataManager: historicalDataManager,
            sensorDataStore: sensorDataStore,
            subscriptionManager: subscriptionManager,
            deviceManager: deviceManager,
            sensorDataProcessor: sensorDataProcessor,
            sessionHistoryStore: sessionHistoryStore,
            appStateManager: appStateManager,
            sharedDataManager: sharedDataManager,
            designSystem: designSystem
        )

        _authenticationManager = StateObject(wrappedValue: authenticationManager)
        _sensorDataStore = StateObject(wrappedValue: sensorDataStore)
        _recordingSessionManager = StateObject(wrappedValue: recordingSessionManager)
        _historicalDataManager = StateObject(wrappedValue: historicalDataManager)
        _subscriptionManager = StateObject(wrappedValue: subscriptionManager)
        _deviceManager = StateObject(wrappedValue: deviceManager)
        _sensorDataProcessor = StateObject(wrappedValue: sensorDataProcessor)
        _appStateManager = StateObject(wrappedValue: appStateManager)
        _sharedDataManager = StateObject(wrappedValue: sharedDataManager)
        _designSystem = StateObject(wrappedValue: designSystem)
        _dependencies = StateObject(wrappedValue: dependencies)
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LaunchCoordinator()
                .withDependencies(dependencies)
                .environmentObject(firstLaunchManager)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
        }
    }

    // MARK: - Scene Phase Handling

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            Logger.shared.info("[OralableApp] App entering background")
            if deviceManager.isScanning {
                Logger.shared.info("[OralableApp] Stopping BLE scan while backgrounded")
                deviceManager.stopScanning()
            }
            deviceManager.cancelAllReconnections()
            // Note: Automatic recording continues in background
            // Events are auto-saved every 3 minutes and on disconnect
            // Sync data when app goes to background
            Task(priority: .utility) {
                // Save any pending events
                deviceManager.automaticRecordingSession?.savePendingEvents()
                await waitUntilBleIdleForCloudKitSync(deviceManager: deviceManager)
                await sharedDataManager.uploadCurrentDataForSharing()
            }

        case .inactive:
            Logger.shared.info("[OralableApp] App becoming inactive")

        case .active:
            Logger.shared.info("[OralableApp] App becoming active")

        @unknown default:
            break
        }
    }
}

// MARK: - CloudKit vs BLE (disconnect sync)

/// After a disconnect, iOS often reconnects within a few seconds. Defer heavy sync until
/// `primaryDeviceReadiness` is stable (disconnected / failed, or fully ready), not connecting
/// or discovering services/characteristics.
private func waitUntilBleIdleForCloudKitSync(
    deviceManager: DeviceManager,
    pollInterval: Duration = .milliseconds(200),
    maxWaitSeconds: TimeInterval = 25,
    reconnectGraceSeconds: TimeInterval = 4
) async {
    let start = Date()
    let deadline = start.addingTimeInterval(maxWaitSeconds)
    Logger.shared.info(
        "[OralableApp] waitUntilBleIdleForCloudKitSync: start grace=\(reconnectGraceSeconds)s max=\(maxWaitSeconds)s"
    )
    while Date() < deadline {
        let readiness = await MainActor.run { deviceManager.primaryDeviceReadiness }
        switch readiness {
        case .disconnected, .failed:
            // Right after an unexpected disconnect, the background worker usually kicks off a reconnect
            // within ~1-3s. If we sync immediately while "disconnected", we'll overlap the imminent
            // GATT discovery window (seen in logs: sync_ck starting ~2s after disconnect).
            if Date().timeIntervalSince(start) < reconnectGraceSeconds {
                try? await Task.sleep(for: pollInterval)
                continue
            }
            Logger.shared.info(
                "[OralableApp] waitUntilBleIdleForCloudKitSync: proceeding while \(readiness) after \(String(format: "%.1f", Date().timeIntervalSince(start)))s"
            )
            return
        case .ready:
            Logger.shared.info(
                "[OralableApp] waitUntilBleIdleForCloudKitSync: BLE ready after \(String(format: "%.1f", Date().timeIntervalSince(start)))s"
            )
            return
        case .connecting, .connected, .discoveringServices, .servicesDiscovered,
             .discoveringCharacteristics, .characteristicsDiscovered, .enablingNotifications:
            try? await Task.sleep(for: pollInterval)
        }
    }
    Logger.shared.info(
        "[OralableApp] waitUntilBleIdleForCloudKitSync: timed out after \(maxWaitSeconds)s, syncing anyway"
    )
}
