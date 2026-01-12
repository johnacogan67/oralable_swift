//
//  DevicesView.swift
//  OralableApp
//
//  BLE device discovery and connection management screen.
//
//  Sections:
//  - My Devices: Previously connected/remembered devices
//  - Other Devices: Newly discovered devices during scan
//
//  Features:
//  - Automatic scanning on appear (if Bluetooth ready)
//  - Manual scan button in toolbar
//  - Connection state display (Connecting, Ready, Failed)
//  - Device detail sheet for forget/disconnect actions
//  - Demo device support when demo mode enabled
//
//  Device Types Supported:
//  - Oralable (primary device)
//  - ANR M40 (research comparison)
//  - Demo (virtual device for testing)
//
//  Updated: December 8, 2025 - Fixed ANR showing "Failed" when actually working
//

import SwiftUI
import CoreBluetooth

struct DevicesView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var deviceManagerAdapter: DeviceManagerAdapter

    @State private var isScanning = false
    @State private var selectedDevice: DeviceRowItem?
    @State private var showingDeviceDetail = false

    private let persistenceManager = DevicePersistenceManager.shared

    var body: some View {
        NavigationView {
            List {
                myDevicesSection
                otherDevicesSection
            }
            .listStyle(.insetGrouped)
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isScanning {
                        ProgressView()
                    } else {
                        Button("Scan") {
                            startScanning()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingDeviceDetail) {
                if let device = selectedDevice {
                    DeviceDetailView(device: device, onForget: {
                        forgetDevice(device)
                        showingDeviceDetail = false
                    }, onDisconnect: {
                        disconnectDevice(device)
                        showingDeviceDetail = false
                    })
                }
            }
            .onAppear {
                // Only auto-scan if Bluetooth is ready and no devices connected
                if deviceManager.isBluetoothReady && deviceManager.connectedDevices.isEmpty {
                    startScanning()
                }
            }
            .onDisappear {
                deviceManager.stopScanning()
            }
            .onChange(of: deviceManager.bluetoothState) { newState in
                // Auto-start scan when Bluetooth becomes ready
                if newState == .poweredOn && deviceManager.connectedDevices.isEmpty && !isScanning {
                    Logger.shared.info("[DevicesView] 📶 Bluetooth ready - auto-starting scan")
                    startScanning()
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - My Devices Section (Remembered)
    private var myDevicesSection: some View {
        Section {
            let rememberedDevices = persistenceManager.getRememberedDevices()

            if rememberedDevices.isEmpty {
                Text("No saved devices")
                    .foregroundColor(.secondary)
            } else {
                ForEach(rememberedDevices) { device in
                    DeviceRow(
                        name: device.name,
                        readinessState: getDeviceReadiness(id: device.id),
                        onTap: {
                            let readiness = getDeviceReadiness(id: device.id)
                            if readiness == .ready {
                                selectedDevice = DeviceRowItem(id: device.id, name: device.name, isConnected: true)
                                showingDeviceDetail = true
                            } else {
                                connectToDevice(id: device.id)
                            }
                        },
                        onInfoTap: {
                            selectedDevice = DeviceRowItem(id: device.id, name: device.name, isConnected: isDeviceConnected(id: device.id))
                            showingDeviceDetail = true
                        }
                    )
                }
            }
        } header: {
            Text("My Devices")
        }
    }

    // MARK: - Other Devices Section (Discovered)
    private var otherDevicesSection: some View {
        Section {
            // Use discoveredDevices directly (demo device is added there when demo mode is enabled)
            let discoveredDevices = deviceManager.discoveredDevices.filter { discovered in
                guard let peripheralId = discovered.peripheralIdentifier else { return true }
                return !persistenceManager.isDeviceRemembered(id: peripheralId.uuidString)
            }

            if discoveredDevices.isEmpty {
                // Show Bluetooth state if not ready
                if !deviceManager.isBluetoothReady {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .foregroundColor(.orange)
                        Text(bluetoothStateMessage)
                            .foregroundColor(.secondary)
                    }
                } else if isScanning {
                    HStack {
                        Text("Searching...")
                            .foregroundColor(.secondary)
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Text("No devices found")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(discoveredDevices, id: \.peripheralIdentifier) { device in
                    DeviceRow(
                        name: device.name,
                        readinessState: getDeviceReadiness(id: device.peripheralIdentifier?.uuidString ?? ""),
                        onTap: {
                            connectToNewDevice(device)
                        },
                        onInfoTap: nil
                    )
                }
            }
        } header: {
            HStack {
                Text("Other Devices")
                if isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
    }

    // MARK: - Helper Properties

    private var bluetoothStateMessage: String {
        switch deviceManager.bluetoothState {
        case .unknown:
            return "Initializing Bluetooth..."
        case .resetting:
            return "Bluetooth resetting..."
        case .unsupported:
            return "Bluetooth not supported"
        case .unauthorized:
            return "Bluetooth permission required"
        case .poweredOff:
            return "Turn on Bluetooth"
        case .poweredOn:
            return "Bluetooth ready"
        @unknown default:
            return "Unknown Bluetooth state"
        }
    }

    // MARK: - Helper Methods

    /// Get device readiness state with fallback for devices that show "failed" but are actually working
    private func getDeviceReadiness(id: String) -> ConnectionReadiness {
        // Check if this is the demo device
        if id == DemoDataProvider.shared.deviceID {
            if DemoDataProvider.shared.isConnected {
                return .ready
            } else if DemoDataProvider.shared.isDiscovered {
                return .disconnected
            }
            return .disconnected
        }

        // Check if device is in connected devices list
        if let device = deviceManager.connectedDevices.first(where: { $0.peripheralIdentifier?.uuidString == id }) {
            if let peripheralId = device.peripheralIdentifier {
                let readiness = deviceManager.deviceReadiness[peripheralId] ?? .disconnected

                // FIX: If discovery failed but device is still connected, treat as Ready
                // This handles ANR M40 devices that work but fail the standard discovery flow
                if case .failed = readiness {
                    // Device is in connectedDevices, so it's actually connected
                    // Check if we're receiving data from this device type
                    let deviceName = device.name.lowercased()

                    if deviceName.contains("anr") || deviceName.contains("m40") {
                        // ANR device - check if we have EMG data
                        if deviceManagerAdapter.emgValue > 0 {
                            Logger.shared.debug("[DevicesView] ANR shows failed but has EMG data - treating as Ready")
                            return .ready
                        }
                    } else if deviceName.contains("oralable") {
                        // Oralable device - check if we have PPG data
                        if deviceManagerAdapter.ppgIRValue > 0 {
                            Logger.shared.debug("[DevicesView] Oralable shows failed but has PPG data - treating as Ready")
                            return .ready
                        }
                    }

                    // If we're connected but no data yet, show as connected rather than failed
                    if device.connectionState == .connected {
                        Logger.shared.debug("[DevicesView] Device shows failed but is connected - treating as Connected")
                        return .connected
                    }
                }

                return readiness
            }
        }
        return .disconnected
    }
    
    private func isDeviceConnected(id: String) -> Bool {
        // Check demo device
        if id == DemoDataProvider.shared.deviceID {
            return DemoDataProvider.shared.isConnected
        }
        return deviceManager.connectedDevices.contains { $0.peripheralIdentifier?.uuidString == id }
    }

    private func startScanning() {
        Logger.shared.info("[DevicesView] 🔍 User tapped Scan button")
        isScanning = true
        Task {
            Logger.shared.info("[DevicesView] 🔍 Calling deviceManager.startScanning()")
            await deviceManager.startScanning()
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            await MainActor.run {
                Logger.shared.info("[DevicesView] ⏱️ Scan timeout reached (10s), stopping scan")
                isScanning = false
                deviceManager.stopScanning()
            }
        }
    }

    private func connectToDevice(id: String) {
        Logger.shared.info("[DevicesView] 🔌 connectToDevice called for id: \(id)")
        if let device = deviceManager.discoveredDevices.first(where: { $0.peripheralIdentifier?.uuidString == id }) {
            Logger.shared.info("[DevicesView] 🔌 Found device in discoveredDevices: \(device.name)")
            Task {
                do {
                    Logger.shared.info("[DevicesView] 🔌 Calling deviceManager.connect(to: \(device.name))")
                    try await deviceManager.connect(to: device)
                    Logger.shared.info("[DevicesView] ✅ Connection initiated successfully")
                } catch {
                    Logger.shared.error("[DevicesView] ❌ Failed to connect: \(error.localizedDescription)")
                }
            }
        } else {
            Logger.shared.warning("[DevicesView] ⚠️ Device not in discovered list, starting scan to find it")
            // Device not in discovered list, start scanning to find it
            startScanning()
        }
    }

    private func connectToNewDevice(_ device: DeviceInfo) {
        Logger.shared.info("[DevicesView] 🔌 connectToNewDevice called for: \(device.name)")
        Task {
            do {
                Logger.shared.info("[DevicesView] 🔌 Calling deviceManager.connect(to: \(device.name))")
                try await deviceManager.connect(to: device)
                Logger.shared.info("[DevicesView] ✅ Connection initiated successfully")
                if let peripheralId = device.peripheralIdentifier {
                    persistenceManager.rememberDevice(id: peripheralId.uuidString, name: device.name)
                    Logger.shared.info("[DevicesView] 💾 Device remembered: \(device.name)")
                }
            } catch {
                Logger.shared.error("[DevicesView] ❌ Failed to connect: \(error.localizedDescription)")
            }
        }
    }

    private func forgetDevice(_ device: DeviceRowItem) {
        if device.isConnected {
            disconnectDevice(device)
        }
        persistenceManager.forgetDevice(id: device.id)
    }

    private func disconnectDevice(_ device: DeviceRowItem) {
        if let connectedDevice = deviceManager.connectedDevices.first(where: {
            $0.peripheralIdentifier?.uuidString == device.id }) {
            Task {
                await deviceManager.disconnect(from: connectedDevice)
            }
        }
    }
}

// MARK: - Device Row Item Model
struct DeviceRowItem: Identifiable {
    let id: String
    let name: String
    let isConnected: Bool
}

// MARK: - Device Row Component
struct DeviceRow: View {
    let name: String
    let readinessState: ConnectionReadiness
    let onTap: () -> Void
    let onInfoTap: (() -> Void)?

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 17))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            // Status indicator with color
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Text(statusText)
                    .font(.system(size: 15))
                    .foregroundColor(statusTextColor)
            }

            if let onInfoTap = onInfoTap {
                Button(action: onInfoTap) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    // MARK: - Status Display Logic
    
    private var statusText: String {
        switch readinessState {
        case .disconnected:
            return "Not Connected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .discoveringServices:
            return "Discovering..."
        case .servicesDiscovered:
            return "Services Found"
        case .discoveringCharacteristics:
            return "Setting up..."
        case .characteristicsDiscovered:
            return "Almost Ready"
        case .enablingNotifications:
            return "Enabling..."
        case .ready:
            return "Ready"
        case .failed:
            return "Failed"
        }
    }
    
    private var statusColor: Color {
        switch readinessState {
        case .disconnected, .failed:
            return .gray
        case .connecting, .connected, .discoveringServices, .servicesDiscovered,
             .discoveringCharacteristics, .characteristicsDiscovered, .enablingNotifications:
            return .orange
        case .ready:
            return .green
        }
    }
    
    private var statusTextColor: Color {
        switch readinessState {
        case .disconnected, .failed:
            return .secondary
        case .connecting, .connected, .discoveringServices, .servicesDiscovered,
             .discoveringCharacteristics, .characteristicsDiscovered, .enablingNotifications:
            return .orange
        case .ready:
            return .green
        }
    }
}

// MARK: - Preview
struct DevicesView_Previews: PreviewProvider {
    static var previews: some View {
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
        let designSystem = DesignSystem()

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

        return NavigationView {
            DevicesView()
        }
        .withDependencies(dependencies)
    }
}
