//
//  AppDependencies.swift
//  OralableApp
//
//  Dependency injection container for app-wide services.
//
//  Provides:
//  - DeviceManager: BLE device management + automatic recording
//  - DeviceManagerAdapter: Sensor data adaptation
//  - SensorDataProcessor: Data processing and storage
//  - RecordingSessionManager: Recording lifecycle (legacy)
//  - HistoricalDataManager: Historical data access
//  - SubscriptionManager: In-app purchase handling
//  - AuthenticationManager: Apple ID authentication
//  - SharedDataManager: CloudKit data sharing
//  - DesignSystem: UI styling configuration
//
//  Recording:
//  - Recording is now automatic via DeviceManager.automaticRecordingSession
//  - Starts on BLE connect, stops on disconnect
//
//  Usage:
//  - Injected into SwiftUI via .environmentObject()
//  - ViewModels created via factory methods
//
//  Updated: January 29, 2026 - Removed RecordingStateCoordinator (automatic recording)
//

import SwiftUI

@MainActor
final class AppDependencies: ObservableObject {
    // Core managers - no legacy OralableBLE
    let authenticationManager: AuthenticationManager
    let recordingSessionManager: RecordingSessionManager
    let historicalDataManager: HistoricalDataManager
    let sensorDataStore: SensorDataStore
    let subscriptionManager: SubscriptionManager
    let deviceManager: DeviceManager
    let deviceManagerAdapter: DeviceManagerAdapter
    let sensorDataProcessor: SensorDataProcessor
    let appStateManager: AppStateManager
    let sharedDataManager: SharedDataManager
    let designSystem: DesignSystem

    // Cached view models to preserve state across views
    private var _cachedDashboardViewModel: DashboardViewModel?

    init(authenticationManager: AuthenticationManager,
         recordingSessionManager: RecordingSessionManager,
         historicalDataManager: HistoricalDataManager,
         sensorDataStore: SensorDataStore,
         subscriptionManager: SubscriptionManager,
         deviceManager: DeviceManager,
         sensorDataProcessor: SensorDataProcessor,
         appStateManager: AppStateManager,
         sharedDataManager: SharedDataManager,
         designSystem: DesignSystem) {
        self.authenticationManager = authenticationManager
        self.recordingSessionManager = recordingSessionManager
        self.historicalDataManager = historicalDataManager
        self.sensorDataStore = sensorDataStore
        self.subscriptionManager = subscriptionManager
        self.deviceManager = deviceManager
        self.deviceManagerAdapter = DeviceManagerAdapter(deviceManager: deviceManager, sensorDataProcessor: sensorDataProcessor)
        self.sensorDataProcessor = sensorDataProcessor
        self.appStateManager = appStateManager
        self.sharedDataManager = sharedDataManager
        self.designSystem = designSystem

        Logger.shared.info("[AppDependencies] Initialized with automatic recording support")
    }

    // MARK: - Factory Methods

    /// Returns cached DashboardViewModel to preserve recorded events across views
    func makeDashboardViewModel() -> DashboardViewModel {
        if let cached = _cachedDashboardViewModel {
            Logger.shared.debug("[AppDependencies] Returning cached DashboardViewModel")
            return cached
        }

        Logger.shared.info("[AppDependencies] Creating new DashboardViewModel")
        let vm = DashboardViewModel(
            deviceManagerAdapter: deviceManagerAdapter,
            deviceManager: deviceManager,
            appStateManager: appStateManager
        )
        _cachedDashboardViewModel = vm
        return vm
    }

    /// Reset cached DashboardViewModel (call on logout or when fresh state needed)
    func resetDashboardViewModel() {
        Logger.shared.info("[AppDependencies] Resetting cached DashboardViewModel")
        _cachedDashboardViewModel?.stopMonitoring()
        _cachedDashboardViewModel = nil
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        return SettingsViewModel(
            sensorDataProcessor: sensorDataProcessor
        )
    }
}

struct DependenciesModifier: ViewModifier {
    @ObservedObject var dependencies: AppDependencies

    func body(content: Content) -> some View {
        content
            .environmentObject(dependencies)
            .environmentObject(dependencies.authenticationManager)
            .environmentObject(dependencies.recordingSessionManager)
            .environmentObject(dependencies.historicalDataManager)
            .environmentObject(dependencies.deviceManager)
            .environmentObject(dependencies.deviceManagerAdapter)
            .environmentObject(dependencies.sensorDataProcessor)
            .environmentObject(dependencies.sensorDataStore)
            .environmentObject(dependencies.subscriptionManager)
            .environmentObject(dependencies.appStateManager)
            .environmentObject(dependencies.sharedDataManager)
            .environmentObject(dependencies.designSystem)
    }
}

extension View {
    func withDependencies(_ dependencies: AppDependencies) -> some View {
        self.modifier(DependenciesModifier(dependencies: dependencies))
    }
}
