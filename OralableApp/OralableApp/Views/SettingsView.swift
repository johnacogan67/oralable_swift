//
//  SettingsView.swift
//  OralableApp
//
//  Settings screen for app configuration.
//
//  Sections:
//  - Detection Settings: Event detection threshold configuration (if enabled)
//  - Subscription: Premium features and subscription management (if enabled)
//  - Health: Apple Health integration settings
//  - Support: Links to user guide, FAQ, contact support
//  - About: App version, legal links, and hidden developer access (7-tap)
//
//  Hidden Features:
//  - Developer Settings: Accessible by tapping version number 7 times
//    - Feature flag toggles for dashboard cards
//    - Demo mode toggle (moved here from main settings)
//    - Debug configuration options
//
//  Updated: January 2026 - Removed Demo Mode from main UI (now in Developer Settings only)
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @EnvironmentObject var dependencies: AppDependencies
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var appleHealthManager: AppleHealthManager
    @ObservedObject private var featureFlags = FeatureFlags.shared

    @State private var showSubscriptionInfo = false
    @State private var developerTapCount = 0
    @State private var showDeveloperSettings = false

    /// Toggle between standard and simplified dashboard
    @AppStorage("useSimplifiedDashboard") private var useSimplifiedDashboard: Bool = false
    @AppStorage("oralable.settings.appleHealthSync") private var appleHealthSyncEnabled: Bool = false

    init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                // Subscription Section - CONDITIONAL
                if featureFlags.showSubscription {
                    Section {
                        subscriptionRow
                    } header: {
                        Text("Subscription")
                    }
                }

                // Detection Settings Section - CONDITIONAL
                if featureFlags.showDetectionSettings {
                    Section {
                        thresholdsRow
                        eventSettingsRow
                    } header: {
                        Text("Detection Settings")
                    }
                }

                // Display Settings Section - ALWAYS SHOWN
                Section {
                    dashboardStyleRow
                } header: {
                    Text("Display")
                } footer: {
                    Text("Simplified dashboard shows a single status card with color-coded positioning.")
                }

                Section {
                    Toggle(isOn: $appleHealthSyncEnabled) {
                        Label("Apple Health Sync", systemImage: "heart.text.square.fill")
                    }
                    .disabled(!appleHealthManager.isHealthDataAvailable)
                    .tint(designSystem.colors.info)
                    .onChange(of: appleHealthSyncEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            try? await appleHealthManager.requestAuthorization()
                        }
                    }

                    if appleHealthManager.isHealthDataAvailable {
                        if let last = appleHealthManager.lastSuccessfulSpO2SyncAt {
                            Text("Last successful sync: \(last.formatted(date: .abbreviated, time: .shortened))")
                                .font(designSystem.typography.bodySmall)
                                .foregroundColor(designSystem.colors.textSecondary)
                        } else {
                            Text("No SpO₂ written to Health yet")
                                .font(designSystem.typography.bodySmall)
                                .foregroundColor(designSystem.colors.textSecondary)
                        }
                    } else {
                        Text("Health data is not available on this device.")
                            .font(designSystem.typography.bodySmall)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }

                    NavigationLink {
                        ProfessionalShareView()
                    } label: {
                        Label("Share with clinician", systemImage: "stethoscope")
                    }
                } header: {
                    Text("Clinical data")
                } footer: {
                    Text("Enable sync to authorize Health access. Session-average SpO₂ is saved from the Temporalis HOI export action. Use clinician sharing to generate a secure code and export package for Oralable for Professionals.")
                }

                Section {
                    NavigationLink {
                        MainDashboardView()
                    } label: {
                        Label("Sleep study setup", systemImage: "moon.zzz.fill")
                    }
                } header: {
                    Text("Sleep study")
                } footer: {
                    Text("Temporalis mirror fit, IR-DC placement check, and 10-minute calibration gate before overnight recording.")
                }

                // About Section - ALWAYS SHOWN (with hidden developer access)
                Section {
                    aboutRow
                } header: {
                    Text("About")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSubscriptionInfo) {
                SubscriptionInfoView()
            }
            .sheet(isPresented: $showDeveloperSettings) {
                NavigationStack {
                    DeveloperSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showDeveloperSettings = false
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - About Row (with hidden developer access)
    private var aboutRow: some View {
        Button(action: {
            developerTapCount += 1
            if developerTapCount >= 7 {
                showDeveloperSettings = true
                developerTapCount = 0
            }
            // Reset after 2 seconds of no taps
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if developerTapCount > 0 && developerTapCount < 7 {
                    developerTapCount = 0
                }
            }
        }) {
            HStack {
                Image(systemName: "info.circle")
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.gray500)
                    .frame(width: designSystem.spacing.xl)

                VStack(alignment: .leading, spacing: designSystem.spacing.xxs) {
                    Text("About")
                        .font(designSystem.typography.body)
                        .foregroundColor(designSystem.colors.textPrimary)

                    Text("Version 1.0")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                }

                Spacer()
            }
            .padding(.vertical, designSystem.spacing.xs)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var subscriptionRow: some View {
        Button(action: { showSubscriptionInfo = true }) {
            HStack {
                Image(systemName: "star.fill")
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.warning)
                    .frame(width: designSystem.spacing.xl)

                VStack(alignment: .leading, spacing: designSystem.spacing.xxs) {
                    Text("Current Plan")
                        .font(designSystem.typography.body)
                        .foregroundColor(designSystem.colors.textPrimary)

                    HStack(spacing: designSystem.spacing.xs) {
                        Text(dependencies.subscriptionManager.currentTier.displayName)
                            .font(designSystem.typography.bodySmall)
                            .foregroundColor(designSystem.colors.textSecondary)

                        if dependencies.subscriptionManager.currentTier == .premium {
                            Image(systemName: "checkmark.seal.fill")
                                .font(designSystem.typography.footnote)
                                .foregroundColor(designSystem.colors.success)
                        }
                    }
                }

                Spacer()

                if dependencies.subscriptionManager.currentTier == .basic {
                    Text("Upgrade")
                        .font(designSystem.typography.labelLarge)
                        .foregroundColor(designSystem.colors.info)
                } else {
                    Image(systemName: "chevron.right")
                        .font(designSystem.typography.buttonSmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }
        }
        .padding(.vertical, designSystem.spacing.xs)
    }

    private var thresholdsRow: some View {
        NavigationLink {
            ThresholdsSettingsView()
        } label: {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.warning)
                    .frame(width: designSystem.spacing.xl)

                VStack(alignment: .leading, spacing: designSystem.spacing.xxs) {
                    Text("Thresholds")
                        .font(designSystem.typography.body)
                        .foregroundColor(designSystem.colors.textPrimary)

                    Text("Adjust movement sensitivity")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                }

                Spacer()
            }
            .padding(.vertical, designSystem.spacing.xs)
        }
    }

    private var eventSettingsRow: some View {
        NavigationLink {
            EventSettingsView()
        } label: {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.info)
                    .frame(width: designSystem.spacing.xl)

                VStack(alignment: .leading, spacing: designSystem.spacing.xxs) {
                    Text("Event Detection")
                        .font(designSystem.typography.body)
                        .foregroundColor(designSystem.colors.textPrimary)

                    Text("Configure IR threshold for events")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                }

                Spacer()
            }
            .padding(.vertical, designSystem.spacing.xs)
        }
    }

    // MARK: - Dashboard Style Row

    private var dashboardStyleRow: some View {
        Toggle(isOn: $useSimplifiedDashboard) {
            HStack {
                Image(systemName: "rectangle.on.rectangle")
                    .font(designSystem.typography.headline)
                    .foregroundColor(designSystem.colors.info)
                    .frame(width: designSystem.spacing.xl)

                VStack(alignment: .leading, spacing: designSystem.spacing.xxs) {
                    Text("Simplified Dashboard")
                        .font(designSystem.typography.body)
                        .foregroundColor(designSystem.colors.textPrimary)

                    Text("Color-coded status card")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }
        }
        .tint(designSystem.colors.info)
        .padding(.vertical, designSystem.spacing.xs)
    }
}

// MARK: - Preview

#Preview("Settings View") {
    let (dependencies, designSystem): (AppDependencies, DesignSystem) = {
        let designSystem = DesignSystem()
        let calculator = BioMetricCalculator()
        let sensorDataProcessor = SensorDataProcessor(calculator: calculator)
        let authManager = AuthenticationManager()
        let sessionHistoryStore = SessionHistoryStore()
        let recordingSessionManager = RecordingSessionManager()
        recordingSessionManager.sessionHistoryStore = sessionHistoryStore
        let historicalDataManager = HistoricalDataManager(sensorDataProcessor: sensorDataProcessor)
        let sensorDataStore = SensorDataStore()
        let subscriptionManager = SubscriptionManager()
        let deviceManager = DeviceManager()
        sessionHistoryStore.attach(recordingManager: recordingSessionManager, deviceManager: deviceManager)
        let appStateManager = AppStateManager()
        let sharedDataManager = SharedDataManager(
            authenticationManager: authManager,
            sensorDataProcessor: sensorDataProcessor
        )
        let dependencies = AppDependencies(
            authenticationManager: authManager,
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
        return (dependencies, designSystem)
    }()

    SettingsView(viewModel: dependencies.makeSettingsViewModel())
        .withDependencies(dependencies)
        .environmentObject(designSystem)
}
