import SwiftUI
import OralableCore

@main
struct OralableApp: App {
    // Core managers - no legacy OralableBLE.
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
    @StateObject private var recordingStateCoordinator: RecordingStateCoordinator

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
        let recordingStateCoordinator = RecordingStateCoordinator.shared

        // Set up RecordingStateCoordinator with SharedDataManager for auto-sync after recording
        recordingStateCoordinator.sharedDataManager = sharedDataManager

        // Create AppDependencies without legacy OralableBLE
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
        _recordingStateCoordinator = StateObject(wrappedValue: recordingStateCoordinator)
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
            // Stop recording if active to prevent data loss
            if recordingStateCoordinator.isRecording {
                recordingStateCoordinator.stopRecording()
                Logger.shared.warning("[OralableApp] Recording stopped due to background transition")
            }
            // Sync data when app goes to background
            Task {
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
