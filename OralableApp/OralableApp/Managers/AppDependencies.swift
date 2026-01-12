//
//  AppDependencies.swift
//  OralableApp
//
//  Dependency injection container for app-wide services.
//
//  Provides:
//  - DeviceManager: BLE device management
//  - DeviceManagerAdapter: Sensor data adaptation
//  - SensorDataProcessor: Data processing and storage
//  - RecordingSessionManager: Recording lifecycle
//  - HistoricalDataManager: Historical data access
//  - SubscriptionManager: In-app purchase handling
//  - AuthenticationManager: Apple ID authentication
//  - SharedDataManager: CloudKit data sharing
//  - DesignSystem: UI styling configuration
//
//  Usage:
//  - Injected into SwiftUI via .environmentObject()
//  - ViewModels created via factory methods
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
    let recordingStateCoordinator: RecordingStateCoordinator

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
        self.recordingStateCoordinator = RecordingStateCoordinator.shared

        Logger.shared.info("[AppDependencies] Initialized (legacy OralableBLE removed)")
    }

    // MARK: - Factory Methods
    func makeDashboardViewModel() -> DashboardViewModel {
        return DashboardViewModel(
            deviceManagerAdapter: deviceManagerAdapter,
            deviceManager: deviceManager,
            appStateManager: appStateManager,
            recordingStateCoordinator: recordingStateCoordinator
        )
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
            .environmentObject(dependencies.recordingStateCoordinator)
    }
}

extension View {
    func withDependencies(_ dependencies: AppDependencies) -> some View {
        self.modifier(DependenciesModifier(dependencies: dependencies))
    }
}
