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
    @ObservedObject private var featureFlags = FeatureFlags.shared

    @State private var showSubscriptionInfo = false
    @State private var developerTapCount = 0
    @State private var showDeveloperSettings = false

    init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationView {
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
        .navigationViewStyle(.stack)
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
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("About")
                        .font(.system(size: 17))
                        .foregroundColor(.primary)

                    Text("Version 1.0")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var subscriptionRow: some View {
        Button(action: { showSubscriptionInfo = true }) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Plan")
                        .font(.system(size: 17))
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        Text(dependencies.subscriptionManager.currentTier.displayName)
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)

                        if dependencies.subscriptionManager.currentTier == .premium {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                if dependencies.subscriptionManager.currentTier == .basic {
                    Text("Upgrade")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var thresholdsRow: some View {
        NavigationLink {
            ThresholdsSettingsView()
        } label: {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Thresholds")
                        .font(.system(size: 17))
                        .foregroundColor(.primary)

                    Text("Adjust movement sensitivity")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var eventSettingsRow: some View {
        NavigationLink {
            EventSettingsView()
        } label: {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Event Detection")
                        .font(.system(size: 17))
                        .foregroundColor(.primary)

                    Text("Configure IR threshold for events")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Preview

#Preview("Settings View") {
    let designSystem = DesignSystem()

    // Build the processing stack
    let calculator = BioMetricCalculator()
    let sensorDataProcessor = SensorDataProcessor(calculator: calculator)

    let authManager = AuthenticationManager()
    let recordingSessionManager = RecordingSessionManager()
    let historicalDataManager = HistoricalDataManager(sensorDataProcessor: sensorDataProcessor)
    let sensorDataStore = SensorDataStore()
    let subscriptionManager = SubscriptionManager()
    let deviceManager = DeviceManager()
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
        appStateManager: appStateManager,
        sharedDataManager: sharedDataManager,
        designSystem: designSystem
    )

    SettingsView(viewModel: dependencies.makeSettingsViewModel())
        .withDependencies(dependencies)
        .environmentObject(designSystem)
}
