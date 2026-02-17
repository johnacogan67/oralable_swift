//
//  SubscriptionSettingsView.swift
//  OralableApp
//
//  Created by John A Cogan on 07/11/2025.
//


import SwiftUI
import AuthenticationServices

struct SubscriptionSettingsView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @ObservedObject var deviceManagerAdapter: DeviceManagerAdapter
    @ObservedObject var sensorDataProcessor: SensorDataProcessor
    @Binding var selectedMode: HistoricalAppMode?
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var loggingService = AppLoggingService()
    @State private var showSignOutAlert = false
    @State private var showLogs = false
    @State private var showSubscriptionInfo = false
    @State private var showAppleIDDebug = false

    var body: some View {
        List {
            // Account Section
            Section("Account") {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.title)
                        .foregroundColor(designSystem.colors.info)

                    VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
                        Text(authManager.userFullName ?? "User")
                            .font(designSystem.typography.headline)
                        if let email = authManager.userEmail {
                            Text(email)
                                .font(designSystem.typography.caption)
                                .foregroundColor(designSystem.colors.textSecondary)
                        }
                        Text("Apple ID")
                            .font(designSystem.typography.caption2)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                }
                .padding(.vertical, designSystem.spacing.sm)

                Button(action: { showSignOutAlert = true }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .foregroundColor(designSystem.colors.error)
                }
            }

            // Subscription Section
            Section("Subscription") {
                HStack {
                    VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
                        Text("Current Plan")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.textSecondary)
                        HStack {
                            Text(subscriptionManager.currentTier.displayName)
                                .font(designSystem.typography.headline)
                            if subscriptionManager.currentTier == .premium {
                                Image(systemName: "star.fill")
                                    .foregroundColor(designSystem.colors.warning)
                                    .font(designSystem.typography.caption)
                            }
                        }
                    }
                    Spacer()
                    if subscriptionManager.currentTier == .basic {
                        Button("Upgrade") {
                            showSubscriptionInfo = true
                        }
                        .font(designSystem.typography.bodySmall)
                    }
                }

                Button(action: { showSubscriptionInfo = true }) {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("View Plans")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                }
            }
            
            // PPG Configuration Section (Debug)
            // Note: This debug feature is specific to OralableBLE and is not yet implemented in DeviceManager
            // TODO: Add PPG channel configuration to DeviceManager if needed
            /*
            if deviceManagerAdapter.isConnected {
                Section("PPG Configuration (Debug)") {
                    Picker("Channel Order", selection: $deviceManagerAdapter.ppgChannelOrder) {
                        ForEach(PPGChannelOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("If PPG values seem random or mixed up, try different channel orders to find the correct one.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            */
            
            // Connection Section
            Section("Device Connection") {
                HStack {
                    Text("Status")
                    Spacer()
                    HStack(spacing: designSystem.spacing.xs + 2) {
                        Circle()
                            .fill(deviceManagerAdapter.isConnected ? designSystem.colors.success : designSystem.colors.error)
                            .frame(width: 8, height: 8)
                        Text(deviceManagerAdapter.isConnected ? "Connected" : "Disconnected")
                            .foregroundColor(deviceManagerAdapter.isConnected ? designSystem.colors.success : designSystem.colors.error)
                    }
                }

                if deviceManagerAdapter.isConnected {
                    HStack {
                        Text("Device")
                        Spacer()
                        Text(deviceManagerAdapter.deviceName)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }

                    HStack {
                        Text("Battery")
                        Spacer()
                        Text("\(Int(deviceManagerAdapter.batteryLevel))%")
                            .foregroundColor(designSystem.colors.textSecondary)
                    }

                    Button(action: { deviceManagerAdapter.disconnect() }) {
                        HStack {
                            Image(systemName: "link.slash")
                            Text("Disconnect")
                        }
                        .foregroundColor(designSystem.colors.warning)
                    }
                } else {
                    Button(action: {
                        if deviceManagerAdapter.isScanning {
                            deviceManagerAdapter.stopScanning()
                        } else {
                            deviceManagerAdapter.startScanning()
                        }
                    }) {
                        HStack {
                            Image(systemName: deviceManagerAdapter.isScanning ? "stop.circle" : "antenna.radiowaves.left.and.right")
                            Text(deviceManagerAdapter.isScanning ? "Stop Scanning" : "Start Scanning")
                        }
                    }
                }
            }
            
            // Logs Section
            Section("Diagnostics") {
                Button(action: { showLogs = true }) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("View Logs")
                        Spacer()
                        Text("\(loggingService.recentLogs.count)")
                            .foregroundColor(designSystem.colors.textSecondary)
                            .font(designSystem.typography.caption)
                        Image(systemName: "chevron.right")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                }

                Button(action: { showAppleIDDebug = true }) {
                    HStack {
                        Image(systemName: "person.crop.rectangle.badge.plus")
                        Text("Apple ID Debug")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                }

                Button(action: { loggingService.clearLogs() }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Logs")
                    }
                    .foregroundColor(designSystem.colors.error)
                }
            }

            // App Mode Section
            Section("App Mode") {
                HStack {
                    VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
                        Text("Current Mode")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.textSecondary)
                        Text("Subscription Mode")
                            .font(designSystem.typography.headline)
                    }
                }

                Button(action: {
                    selectedMode = nil
                }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Change Mode")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                }
            }

            // About Section
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(designSystem.colors.textSecondary)
                }
                
                if deviceManagerAdapter.isConnected {
                    // TODO: Add firmware version to DeviceManager if available
                    /*
                    HStack {
                        Text("Firmware Version")
                        Spacer()
                        Text(deviceManagerAdapter.firmwareVersion)
                            .foregroundColor(.secondary)
                    }
                    */

                    if let deviceUUID = deviceManagerAdapter.deviceUUID {
                        HStack {
                            Text("Device UUID")
                            Spacer()
                            Text(deviceUUID.uuidString)
                                .font(designSystem.typography.caption)
                                .foregroundColor(designSystem.colors.textSecondary)
                        }
                    }
                }

                Link(destination: URL(string: "https://github.com/johna67/tgm_firmware")!) {
                    HStack {
                        Text("GitHub Repository")
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showLogs) {
            BLELogsView(logs: loggingService.recentLogs)
        }
        .sheet(isPresented: $showSubscriptionInfo) {
            SubscriptionInfoView()
        }
        .sheet(isPresented: $showAppleIDDebug) {
            AppleIDDebugView()
        }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                authManager.signOut()
                selectedMode = nil
            }
        } message: {
            Text("Are you sure you want to sign out? You'll need to sign in again to access subscription features.")
        }
    }
}

// MARK: - Subscription Info View

struct SubscriptionInfoView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager()
    @State private var isUpgrading = false
    @State private var showSuccessAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: designSystem.spacing.lg) {
                    headerSection
                    subscriptionTiersSection
                    footerSection
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Success!", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("You've been upgraded to Premium! Enjoy all the premium features.")
            }
            .disabled(isUpgrading)
            .overlay {
                if isUpgrading {
                    loadingOverlay
                }
            }
        }
    }

    // MARK: - View Sections

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: designSystem.spacing.sm) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(designSystem.colors.warning)

            Text("Choose Your Plan")
                .font(designSystem.typography.largeTitle)
                .fontWeight(.bold)

            Text("Unlock premium features and get the most out of your device")
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top)
    }

    @ViewBuilder
    private var subscriptionTiersSection: some View {
        VStack(spacing: designSystem.spacing.md) {
            // Basic Tier
            SubscriptionTierCard(
                tier: .basic,
                isCurrentTier: subscriptionManager.currentTier == .basic,
                action: {
                    // Already on basic, no action needed
                }
            )

            // Premium Tier
            SubscriptionTierCard(
                tier: .premium,
                isCurrentTier: subscriptionManager.currentTier == .premium,
                action: {
                    upgradeToPremium()
                }
            )
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var footerSection: some View {
        VStack(spacing: designSystem.spacing.buttonPadding) {
            Text("All plans include:")
                .font(designSystem.typography.headline)

            VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
                FeatureBullet(text: "Secure data encryption")
                FeatureBullet(text: "Regular firmware updates")
                FeatureBullet(text: "Customer support")
            }
            .padding(.horizontal, designSystem.spacing.xl)
        }
        .padding(.top)
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        designSystem.colors.primaryBlack.opacity(0.3)
            .ignoresSafeArea()

        ProgressView()
            .scaleEffect(1.5)
            .progressViewStyle(CircularProgressViewStyle(tint: designSystem.colors.primaryWhite))
    }
    
    private func upgradeToPremium() {
        guard subscriptionManager.currentTier != .premium else { return }

        isUpgrading = true

        #if DEBUG
        // In debug mode, simulate purchase
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            subscriptionManager.simulatePurchase()
            isUpgrading = false
            showSuccessAlert = true
        }
        #else
        // In production, would use actual StoreKit purchase
        Task {
            do {
                guard let product = subscriptionManager.monthlyProduct else {
                    isUpgrading = false
                    return
                }
                try await subscriptionManager.purchase(product)
                isUpgrading = false
                showSuccessAlert = true
            } catch {
                isUpgrading = false
                Logger.shared.error("[SubscriptionSettingsView] Purchase failed: \(error)")
            }
        }
        #endif
    }
}

// MARK: - Subscription Tier Card

struct SubscriptionTierCard: View {
    @EnvironmentObject var designSystem: DesignSystem
    let tier: SubscriptionTier
    let isCurrentTier: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
                    Text(tier.displayName)
                        .font(designSystem.typography.h3)
                        .fontWeight(.bold)

                    if tier == .premium {
                        Text("$9.99/month")
                            .font(designSystem.typography.headline)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                }

                Spacer()

                if tier == .premium {
                    Image(systemName: "star.fill")
                        .foregroundColor(designSystem.colors.warning)
                        .font(designSystem.typography.h3)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
                ForEach(tier.features, id: \.self) { feature in
                    HStack(alignment: .top, spacing: designSystem.spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(designSystem.colors.success)
                            .font(designSystem.typography.body)
                        Text(feature)
                            .font(designSystem.typography.bodySmall)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if isCurrentTier {
                HStack {
                    Spacer()
                    Text("Current Plan")
                        .font(designSystem.typography.bodySmall)
                        .fontWeight(.semibold)
                        .foregroundColor(designSystem.colors.success)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(designSystem.colors.success)
                    Spacer()
                }
                .padding(.vertical, designSystem.spacing.buttonPadding)
                .background(designSystem.colors.success.opacity(0.1))
                .cornerRadius(designSystem.cornerRadius.medium)
            } else if tier == .premium {
                Button(action: action) {
                    HStack {
                        Spacer()
                        Text("Upgrade Now")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, designSystem.spacing.buttonPadding)
                    .background(designSystem.colors.info)
                    .foregroundColor(designSystem.colors.primaryWhite)
                    .cornerRadius(designSystem.cornerRadius.medium)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: designSystem.cornerRadius.large)
                .stroke(isCurrentTier ? designSystem.colors.success : designSystem.colors.gray400.opacity(0.3), lineWidth: isCurrentTier ? 2 : 1)
        )
        .background(
            RoundedRectangle(cornerRadius: designSystem.cornerRadius.large)
                .fill(designSystem.colors.backgroundPrimary)
        )
    }
}

// MARK: - Feature Bullet

struct FeatureBullet: View {
    @EnvironmentObject var designSystem: DesignSystem
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: designSystem.spacing.sm) {
            Image(systemName: "checkmark.circle")
                .foregroundColor(designSystem.colors.info)
            Text(text)
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)
        }
    }
}

// MARK: - BLE Logs View

struct BLELogsView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @Environment(\.dismiss) private var dismiss
    let logs: [LogEntry]
    @State private var searchText = ""

    var filteredLogs: [LogEntry] {
        if searchText.isEmpty {
            return logs
        }
        return logs.filter { $0.message.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredLogs.isEmpty {
                    VStack(spacing: designSystem.spacing.md) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(designSystem.colors.textSecondary)

                        Text("No Logs")
                            .font(designSystem.typography.headline)

                        Text(searchText.isEmpty ? "No logs available" : "No logs matching '\(searchText)'")
                            .font(designSystem.typography.bodySmall)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                } else {
                    List {
                        ForEach(Array(filteredLogs.enumerated().reversed()), id: \.offset) { index, log in
                            VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
                                HStack {
                                    Image(systemName: log.level.icon)
                                        .foregroundColor(log.level.color)
                                        .font(designSystem.typography.caption)

                                    Text(log.category)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(designSystem.colors.textSecondary)
                                }

                                Text(log.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(designSystem.colors.textPrimary)

                                HStack {
                                    Text("Entry #\(filteredLogs.count - index)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(designSystem.colors.textSecondary)

                                    Spacer()

                                    Text(log.timestamp, style: .time)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(designSystem.colors.textSecondary)
                                }
                            }
                            .padding(.vertical, designSystem.spacing.xs)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("BLE Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search logs...")
        }
    }
}
