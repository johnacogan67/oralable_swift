//
//  MainTabView.swift
//  OralableApp
//
//  Main tab bar container for the app's primary navigation.
//
//  Tabs:
//  - Dashboard: Real-time monitoring and recording
//  - Devices: BLE device management
//  - Share: Data export and sharing
//  - Settings: App configuration
//
//  Each tab receives required environment objects for
//  dependency injection throughout the view hierarchy.
//
//  Updated: January 15, 2026 - Added toggle between standard and simplified dashboard
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var historicalDataManager: HistoricalDataManager
    @EnvironmentObject var sensorDataProcessor: SensorDataProcessor
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var dependencies: AppDependencies

    /// Toggle between standard and simplified dashboard
    @AppStorage("useSimplifiedDashboard") private var useSimplifiedDashboard: Bool = false

    var body: some View {
        TabView {
            // Dashboard Tab - switches based on user preference
            DashboardContainer(useSimplified: useSimplifiedDashboard)
                .tabItem {
                    Label("Dashboard", systemImage: "house.fill")
                }

            // Devices Tab
            DevicesView()
                .environmentObject(designSystem)
                .environmentObject(deviceManager)
                .tabItem {
                    Label("Devices", systemImage: "cpu")
                }

            // Share Tab
            ShareView(sensorDataProcessor: sensorDataProcessor, deviceManager: deviceManager)
                .environmentObject(designSystem)
                .tabItem {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

            // Settings Tab
            SettingsView(viewModel: dependencies.makeSettingsViewModel())
                .environmentObject(dependencies)
                .environmentObject(designSystem)
                .environmentObject(dependencies.authenticationManager)
                .environmentObject(dependencies.subscriptionManager)
                .environmentObject(dependencies.appStateManager)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

// MARK: - Dashboard Container

/// Container that switches between standard and simplified dashboard
private struct DashboardContainer: View {
    @EnvironmentObject var dependencies: AppDependencies
    let useSimplified: Bool

    @State private var viewModel: DashboardViewModel?

    var body: some View {
        Group {
            if let viewModel = viewModel {
                if useSimplified {
                    SimplifiedDashboardView(viewModel: viewModel)
                } else {
                    DashboardView()
                }
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
    }
}
