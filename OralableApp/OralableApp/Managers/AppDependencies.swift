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
import Combine

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
    let sessionHistoryStore: SessionHistoryStore
    let sensorDataProcessor: SensorDataProcessor
    let appStateManager: AppStateManager
    let sharedDataManager: SharedDataManager
    let designSystem: DesignSystem
    let appleHealthManager: AppleHealthManager
    let memoryFlushStatus: MemoryFlushStatus

    // Cached view models to preserve state across views
    private var _cachedDashboardViewModel: DashboardViewModel?

    private var clinicalMetricsCancellables = Set<AnyCancellable>()

    init(authenticationManager: AuthenticationManager,
         recordingSessionManager: RecordingSessionManager,
         historicalDataManager: HistoricalDataManager,
         sensorDataStore: SensorDataStore,
         subscriptionManager: SubscriptionManager,
         deviceManager: DeviceManager,
         sensorDataProcessor: SensorDataProcessor,
         sessionHistoryStore: SessionHistoryStore,
         appStateManager: AppStateManager,
         sharedDataManager: SharedDataManager,
         designSystem: DesignSystem,
         appleHealthManager: AppleHealthManager = AppleHealthManager()) {
        self.authenticationManager = authenticationManager
        self.recordingSessionManager = recordingSessionManager
        self.historicalDataManager = historicalDataManager
        self.sensorDataStore = sensorDataStore
        self.subscriptionManager = subscriptionManager
        self.deviceManager = deviceManager
        self.sessionHistoryStore = sessionHistoryStore
        self.deviceManagerAdapter = DeviceManagerAdapter(
            deviceManager: deviceManager,
            sensorDataProcessor: sensorDataProcessor,
            sessionHistoryStore: sessionHistoryStore
        )
        self.sensorDataProcessor = sensorDataProcessor
        self.appStateManager = appStateManager
        self.sharedDataManager = sharedDataManager
        self.designSystem = designSystem
        self.appleHealthManager = appleHealthManager
        self.memoryFlushStatus = MemoryFlushStatus.shared

        Publishers.CombineLatest3(
            deviceManager.$primaryDevice,
            deviceManager.$deviceReadiness,
            deviceManager.$connectedDevices
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in
            guard let self else { return }
            self.sessionHistoryStore.applyPrimaryDeviceForSleepGate(
                primaryPeripheralId: self.deviceManager.primaryDevice?.peripheralIdentifier
            )
            self.appStateManager.refreshOralableClinicalMetrics(
                primaryBLE: self.deviceManager.primaryBLEDevice
            )
        }
        .store(in: &clinicalMetricsCancellables)

        appStateManager.refreshOralableClinicalMetrics(primaryBLE: deviceManager.primaryBLEDevice)

        AutoFlushService.shared.start(deviceManager: deviceManager, sensorDataProcessor: sensorDataProcessor)

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
            .environmentObject(dependencies.sessionHistoryStore)
            .environmentObject(dependencies.sensorDataProcessor)
            .environmentObject(dependencies.sensorDataStore)
            .environmentObject(dependencies.subscriptionManager)
            .environmentObject(dependencies.appStateManager)
            .environmentObject(dependencies.sharedDataManager)
            .environmentObject(dependencies.designSystem)
            .environmentObject(dependencies.appleHealthManager)
            .environmentObject(dependencies.memoryFlushStatus)
    }
}

extension View {
    func withDependencies(_ dependencies: AppDependencies) -> some View {
        self.modifier(DependenciesModifier(dependencies: dependencies))
    }
}
