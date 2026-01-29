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

    init() {
        let authenticationManager = AuthenticationManager()
        let sensorDataStore = SensorDataStore()
        let recordingSessionManager = RecordingSessionManager()
        let sensorDataProcessor = SensorDataProcessor.shared
        let historicalDataManager = HistoricalDataManager(
            sensorDataProcessor: sensorDataProcessor
        )
        let subscriptionManager = SubscriptionManager()
        let deviceManager = DeviceManager()
        let appStateManager = AppStateManager()
        let sharedDataManager = SharedDataManager(
            authenticationManager: authenticationManager,
            sensorDataProcessor: sensorDataProcessor
        )
        let designSystem = DesignSystem()

        // Configure automatic recording session to sync to CloudKit on disconnect
        deviceManager.automaticRecordingSession?.onSyncRequested = {
            Task {
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
            // Note: Automatic recording continues in background
            // Events are auto-saved every 3 minutes and on disconnect
            // Sync data when app goes to background
            Task {
                // Save any pending events
                deviceManager.automaticRecordingSession?.savePendingEvents()
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
