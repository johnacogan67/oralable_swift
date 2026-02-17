//
//  DashboardView.swift
//  OralableApp
//
//  Main dashboard displaying real-time sensor data.
//
//  Features:
//  - Device connection status indicator with recording state
//  - PPG sensor card (IR waveform)
//  - Optional metric cards (EMG, Movement, Temperature, HR, SpO2, Battery)
//  - Demo mode banner when using virtual device
//  - Automatic recording status display (no manual button)
//
//  Data Flow:
//  Device → DeviceManager → DashboardViewModel → DashboardView
//
//  Recording:
//  - Recording is automatic - starts on BLE connect, stops on disconnect
//  - State indicator shows: DataStreaming (Black), Positioned (Green), Activity (Red)
//
//  Navigation:
//  - Tapping metric cards navigates to HistoricalView
//  - Profile icon opens ProfileView
//
//  Updated: January 29, 2026 - Removed manual recording button (automatic recording)
//

import SwiftUI
import Charts

// MARK: - LazyView Helper
struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}

struct DashboardView: View {
    @EnvironmentObject var dependencies: AppDependencies
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var deviceManagerAdapter: DeviceManagerAdapter
    @EnvironmentObject var deviceManager: DeviceManager
    @ObservedObject private var featureFlags = FeatureFlags.shared

    @State private var viewModel: DashboardViewModel?
    @State private var showingProfile = false
    @State private var dismissedErrorDescription: String?

    var body: some View {
        Group {
            if let viewModel = viewModel {
                dashboardContent(viewModel: viewModel)
            } else {
                ProgressView("Loading...")
                    .task {
                        if viewModel == nil {
                            let vm = dependencies.makeDashboardViewModel()
                            await MainActor.run {
                                self.viewModel = vm
                                vm.startMonitoring()
                            }
                        }
                    }
            }
        }
        .onDisappear {
            viewModel?.stopMonitoring()
        }
        .onChange(of: deviceManager.lastError?.errorDescription) { newErrorDescription in
            // Reset dismissed state when a new different error arrives
            if newErrorDescription != dismissedErrorDescription {
                dismissedErrorDescription = nil
            }
        }
    }

    @ViewBuilder
    private func dashboardContent(viewModel: DashboardViewModel) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: designSystem.spacing.buttonPadding) {
                    // Error Banner
                    if let error = deviceManager.lastError,
                       error.errorDescription != dismissedErrorDescription {
                        ErrorBannerView(
                            title: error.errorDescription ?? "Error",
                            message: error.recoverySuggestion ?? "Please try again.",
                            isRecoverable: error.isRecoverable,
                            retryAction: error.isRecoverable ? {
                                if let firstDevice = deviceManager.discoveredDevices.first {
                                    Task {
                                        try? await deviceManager.connect(to: firstDevice)
                                    }
                                }
                                dismissedErrorDescription = error.errorDescription
                            } : nil,
                            dismissAction: {
                                dismissedErrorDescription = error.errorDescription
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: deviceManager.lastError?.errorDescription)
                    }

                    // Demo Mode Banner
                    if featureFlags.demoModeEnabled {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(designSystem.colors.warning)
                            Text("Demo Mode Active")
                                .font(designSystem.typography.caption)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Disable") {
                                featureFlags.demoModeEnabled = false
                            }
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.warning)
                        }
                        .padding(.horizontal, designSystem.spacing.buttonPadding)
                        .padding(.vertical, designSystem.spacing.sm)
                        .background(designSystem.colors.warning.opacity(0.1))
                        .cornerRadius(designSystem.cornerRadius.button)
                    }

                    // Dual device connection status indicator (now includes Movement)
                    deviceStatusIndicator(viewModel: viewModel)

                    // Recording State Indicator (automatic recording)
                    if viewModel.isConnected {
                        RecordingStateIndicator(
                            state: viewModel.currentRecordingState,
                            isCalibrated: viewModel.isCalibrated,
                            calibrationProgress: viewModel.calibrationProgress,
                            eventCount: viewModel.eventCount,
                            duration: viewModel.formattedDuration
                        )
                        .padding(.vertical, designSystem.spacing.sm)
                    }

                    // PPG Card (Oralable) - Shows IR sensor data
                    NavigationLink(destination: LazyView(
                        HistoricalView(metricType: "IR Activity")
                            .environmentObject(designSystem)
                            .environmentObject(dependencies.recordingSessionManager)
                    )) {
                        HealthMetricCard(
                            icon: "waveform.path.ecg",
                            title: "PPG Sensor",
                            value: viewModel.oralableConnected ? String(format: "%.0f", max(0, viewModel.ppgIRValue)) : "N/A",
                            unit: viewModel.oralableConnected ? "Oralable IR" : "Not Connected",
                            color: .purple,
                            sparklineData: viewModel.ppgHistory,
                            showChevron: true
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // EMG Card (ANR M40) - CONDITIONAL
                    if featureFlags.showEMGCard {
                        NavigationLink(destination: LazyView(
                            HistoricalView(metricType: "EMG Activity")
                                .environmentObject(designSystem)
                                .environmentObject(dependencies.recordingSessionManager)
                        )) {
                            HealthMetricCard(
                                icon: "bolt.fill",
                                title: "EMG Sensor",
                                value: viewModel.anrConnected ? String(format: "%.0f", max(0, viewModel.emgValue)) : "N/A",
                                unit: viewModel.anrConnected ? "ANR M40 µV" : "Not Connected",
                                color: .blue,
                                sparklineData: viewModel.emgHistory,
                                showChevron: true
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Movement card - CONDITIONAL - Now shows g-units
                    if featureFlags.showMovementCard {
                        NavigationLink(destination: LazyView(
                            HistoricalView(metricType: "Movement")
                                .environmentObject(designSystem)
                                .environmentObject(dependencies.recordingSessionManager)
                        )) {
                            MovementMetricCard(
                                value: viewModel.isConnected ? formatMovementInG(viewModel: viewModel) : "N/A",
                                unit: viewModel.isConnected ? "g" : "",
                                statusText: viewModel.isConnected ? (viewModel.isMoving ? "Active" : "Still") : "Not Connected",
                                isActive: viewModel.isMoving,
                                isConnected: viewModel.isConnected,
                                sparklineData: Array(viewModel.accelerometerData.suffix(20)),
                                threshold: ThresholdSettings.shared.movementThreshold,
                                showChevron: true
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Heart Rate card - CONDITIONAL
                    if featureFlags.showHeartRateCard {
                        HeartRateView(
                            wornStatus: Binding(get: { viewModel.wornStatus }, set: { viewModel.wornStatus = $0 }),
                            heartRateResult: Binding(get: { viewModel.currentHRResult }, set: { viewModel.currentHRResult = $0 })
                        )
                    }

                    // SpO2 card - CONDITIONAL
                    if featureFlags.showSpO2Card {
                        NavigationLink(destination: LazyView(
                            HistoricalView(metricType: "SpO2")
                                .environmentObject(designSystem)
                                .environmentObject(dependencies.recordingSessionManager)
                        )) {
                            HealthMetricCard(
                                icon: "lungs.fill",
                                title: "Blood Oxygen",
                                value: viewModel.spO2 > 0 ? "\(viewModel.spO2)" : "N/A",
                                unit: viewModel.spO2 > 0 ? "%" : "",
                                color: .cyan,
                                sparklineData: [],
                                showChevron: true
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Temperature card - CONDITIONAL (with history navigation)
                    if featureFlags.showTemperatureCard {
                        NavigationLink(destination: LazyView(
                            HistoricalView(metricType: "Temperature")
                                .environmentObject(designSystem)
                                .environmentObject(dependencies.recordingSessionManager)
                        )) {
                            HealthMetricCard(
                                icon: "thermometer",
                                title: "Temperature",
                                value: viewModel.temperature > 0 ? String(format: "%.1f", viewModel.temperature) : "N/A",
                                unit: viewModel.temperature > 0 ? "°C" : "",
                                color: .orange,
                                sparklineData: [],
                                showChevron: true
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Battery card - CONDITIONAL (no history)
                    if featureFlags.showBatteryCard {
                        HealthMetricCard(
                            icon: batteryIcon(level: viewModel.batteryLevel, charging: viewModel.isCharging),
                            title: "Battery",
                            value: viewModel.batteryLevel > 0 ? "\(Int(viewModel.batteryLevel))" : "N/A",
                            unit: viewModel.batteryLevel > 0 ? "%" : "",
                            color: batteryColor(level: viewModel.batteryLevel),
                            sparklineData: [],
                            showChevron: false
                        )
                    }
                }
                .padding(.horizontal, designSystem.spacing.md)
                .padding(.top, designSystem.spacing.sm)
            }
            .background(designSystem.colors.backgroundSecondary)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingProfile = true }) {
                        Image(systemName: "person.circle")
                            .font(designSystem.typography.h3)
                            .foregroundColor(designSystem.colors.textPrimary)
                    }
                    .accessibilityLabel("Profile")
                }
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
                    .environmentObject(designSystem)
                    .environmentObject(dependencies.authenticationManager)
                    .environmentObject(dependencies.subscriptionManager)
            }
        }
    }

    // MARK: - Device Status Indicator (Simplified - matches Devices screen)
    private func deviceStatusIndicator(viewModel: DashboardViewModel) -> some View {
        let persistenceManager = DevicePersistenceManager.shared

        return VStack(spacing: designSystem.spacing.sm) {
            // Oralable Device - show if connected OR previously paired OR demo mode enabled
            // Only show "Ready" when actually connected (not just when demo mode is enabled)
            if viewModel.oralableConnected || persistenceManager.hasOralableDevicePaired() || featureFlags.demoModeEnabled {
                HStack {
                    Circle()
                        .fill(viewModel.oralableConnected ? designSystem.colors.success : designSystem.colors.gray400)
                        .frame(width: 10, height: 10)

                    Text("Oralable")
                        .font(designSystem.typography.bodySmall)

                    Spacer()

                    Text(viewModel.oralableConnected ? "Ready" : "Not Connected")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(viewModel.oralableConnected ? designSystem.colors.success : designSystem.colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Oralable device, \(viewModel.oralableConnected ? "Ready" : "Not Connected")")
            }

            // ANR M40 Device - only show if previously paired (not in demo mode)
            if persistenceManager.hasANRDevicePaired() && !featureFlags.demoModeEnabled {
                HStack {
                    Circle()
                        .fill(viewModel.anrConnected ? designSystem.colors.success : designSystem.colors.gray400)
                        .frame(width: 10, height: 10)

                    Text("ANR M40")
                        .font(designSystem.typography.bodySmall)

                    Spacer()

                    Text(viewModel.anrConnected ? "Ready" : "Not Connected")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(viewModel.anrConnected ? designSystem.colors.success : designSystem.colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("ANR M40 device, \(viewModel.anrConnected ? "Ready" : "Not Connected")")
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.card)
        .designShadow(.small)
    }

    // MARK: - Helper Functions
    
    private func batteryIcon(level: Double, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        if level <= 0 { return "battery.0" }  // N/A or unavailable
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        return "battery.25"
    }

    private func batteryColor(level: Double) -> Color {
        if level <= 0 { return designSystem.colors.gray400 }  // N/A or unavailable
        if level < 20 { return designSystem.colors.error }
        if level < 50 { return designSystem.colors.warning }
        return designSystem.colors.success
    }

    /// Calculate and format movement magnitude in g-units
    /// Raw accelerometer values are in LSB units (±2g range = 16384 LSB/g)
    private func formatMovementInG(viewModel: DashboardViewModel) -> String {
        let x = Double(viewModel.accelXRaw)
        let y = Double(viewModel.accelYRaw)
        let z = Double(viewModel.accelZRaw)
        
        // Calculate magnitude and convert to g-units
        // LIS2DTW12 at ±2g has 16384 LSB/g sensitivity
        let magnitude = sqrt(x*x + y*y + z*z) / 16384.0
        
        return String(format: "%.2f", magnitude)
    }

    /// Format movement value for display (legacy - used for variability)
    /// Shows values in K notation for large numbers (e.g., 1.5K instead of 1500)
    private func formatMovementValue(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fK", value / 1000)
        } else if value >= 100 {
            return String(format: "%.0f", value)
        } else if value >= 10 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}

// MARK: - Preview
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        let designSystem = DesignSystem()
        let appState = AppStateManager()
        let sensorStore = SensorDataStore()
        let recordingSession = RecordingSessionManager()
        let historicalData = HistoricalDataManager(sensorDataProcessor: SensorDataProcessor.shared)
        let authManager = AuthenticationManager()
        let subscription = SubscriptionManager()
        let device = DeviceManager()
        let sharedData = SharedDataManager(
            authenticationManager: authManager,
            sensorDataProcessor: SensorDataProcessor.shared
        )

        let dependencies = AppDependencies(
            authenticationManager: authManager,
            recordingSessionManager: recordingSession,
            historicalDataManager: historicalData,
            sensorDataStore: sensorStore,
            subscriptionManager: subscription,
            deviceManager: device,
            sensorDataProcessor: SensorDataProcessor.shared,
            appStateManager: appState,
            sharedDataManager: sharedData,
            designSystem: designSystem
        )

        return DashboardView()
            .withDependencies(dependencies)
            .environmentObject(designSystem)
    }
}
