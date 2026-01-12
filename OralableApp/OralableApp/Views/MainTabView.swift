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

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var historicalDataManager: HistoricalDataManager
    @EnvironmentObject var sensorDataProcessor: SensorDataProcessor
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var dependencies: AppDependencies

    var body: some View {
        TabView {
            // Dashboard Tab
            DashboardView()
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
