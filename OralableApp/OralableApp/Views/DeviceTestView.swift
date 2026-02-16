//
//  DeviceTestView.swift
//  OralableApp
//
//  Created: November 4, 2025
//  Test view for device integration
//

import SwiftUI

struct DeviceTestView: View {
    @StateObject private var deviceManager = DeviceManager()
    @EnvironmentObject var designSystem: DesignSystem
    @State private var autoStopTimer: Timer?

    // For preview/testing purposes
    private let previewDeviceManager: DeviceManager?

    init(previewDeviceManager: DeviceManager? = nil) {
        self.previewDeviceManager = previewDeviceManager
    }
    
    private var currentDeviceManager: DeviceManager {
        previewDeviceManager ?? deviceManager
    }
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Scanning Section
                Section {
                    if currentDeviceManager.isScanning {
                        HStack {
                            ProgressView()
                                .padding(.trailing, designSystem.spacing.xs)
                            Text("Scanning for devices...")
                                .font(designSystem.typography.bodyMedium)
                                .foregroundColor(designSystem.colors.textPrimary)
                        }

                        Button("Stop Scanning") {
                            currentDeviceManager.stopScanning()
                        }
                        .font(designSystem.typography.buttonMedium)
                        .foregroundColor(designSystem.colors.error)
                    } else {
                        Button {
                            Task {
                                await currentDeviceManager.startScanning()
                                
                                // Auto-stop after 30 seconds
                                autoStopTimer?.invalidate()
                                autoStopTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
                                    currentDeviceManager.stopScanning()
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("Start Scanning")
                            }
                            .font(designSystem.typography.buttonMedium)
                        }
                    }
                } header: {
                    Text("Bluetooth Scanning")
                        .font(designSystem.typography.labelMedium)
                }
                
                // MARK: - Discovered Devices Section
                Section {
                    if currentDeviceManager.discoveredDevices.isEmpty {
                        Text("No devices found")
                            .font(designSystem.typography.bodyMedium)
                            .foregroundColor(designSystem.colors.textTertiary)
                            .italic()
                    } else {
                        ForEach(currentDeviceManager.discoveredDevices) { device in
                            DeviceRowView(device: device, deviceManager: currentDeviceManager)
                        }
                    }
                } header: {
                    HStack {
                        Text("Discovered Devices")
                            .font(designSystem.typography.labelMedium)
                        Spacer()
                        Text("\(currentDeviceManager.discoveredDevices.count)")
                            .font(designSystem.typography.labelSmall)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                }
                
                // MARK: - Connected Devices Section
                if !currentDeviceManager.connectedDevices.isEmpty {
                    Section {
                        ForEach(currentDeviceManager.connectedDevices) { device in
                            ConnectedDeviceRowView(device: device, deviceManager: currentDeviceManager)
                        }
                    } header: {
                        HStack {
                            Text("Connected Devices")
                                .font(designSystem.typography.labelMedium)
                            Spacer()
                            Text("\(currentDeviceManager.connectedDevices.count)")
                                .font(designSystem.typography.labelSmall)
                                .foregroundColor(designSystem.colors.textSecondary)
                        }
                    }
                }
                
                // MARK: - Latest Readings Section
                if !currentDeviceManager.latestReadings.isEmpty {
                    Section {
                        ForEach(Array(currentDeviceManager.latestReadings.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { sensorType in
                            if let reading = currentDeviceManager.latestReadings[sensorType] {
                                SensorReadingRowView(reading: reading)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Latest Sensor Readings")
                                .font(designSystem.typography.labelMedium)
                            Spacer()
                            Text("\(currentDeviceManager.latestReadings.count)")
                                .font(designSystem.typography.labelSmall)
                                .foregroundColor(designSystem.colors.textSecondary)
                        }
                    }
                }
                
                // MARK: - Actions Section
                Section {
                    Button("Clear All Data") {
                        currentDeviceManager.clearReadings()
                    }
                    .font(designSystem.typography.buttonMedium)
                    .foregroundColor(designSystem.colors.textSecondary)

                    Button("Disconnect All") {
                        Task {
                            await currentDeviceManager.disconnectAll()
                        }
                    }
                    .font(designSystem.typography.buttonMedium)
                    .foregroundColor(designSystem.colors.error)
                    .disabled(currentDeviceManager.connectedDevices.isEmpty)
                } header: {
                    Text("Actions")
                        .font(designSystem.typography.labelMedium)
                }
            }
            .navigationTitle("Device Test")
            .navigationBarTitleDisplayMode(.large)
        }
        .onDisappear {
            autoStopTimer?.invalidate()
            currentDeviceManager.stopScanning()
        }
    }
}

// MARK: - Device Row View

struct DeviceRowView: View {
    let device: DeviceInfo
    @ObservedObject var deviceManager: DeviceManager
    @EnvironmentObject var designSystem: DesignSystem

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
            // Device Name and Icon
            HStack {
                Image(systemName: device.type.icon)
                    .font(.system(size: DesignSystem.Sizing.Icon.lg))
                    .foregroundColor(designSystem.colors.textPrimary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(designSystem.typography.bodyLarge)
                        .foregroundColor(designSystem.colors.textPrimary)

                    Text(device.type.displayName)
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                }

                Spacer()

                // Connection Status
                if device.connectionState == .connected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(designSystem.colors.success)
                        .font(.system(size: DesignSystem.Sizing.Icon.lg))
                } else if device.connectionState == .connecting {
                    ProgressView()
                }
            }

            // Signal Strength
            if let rssi = device.signalStrength {
                HStack(spacing: designSystem.spacing.xs) {
                    Image(systemName: signalIcon(for: rssi))
                        .font(.system(size: DesignSystem.Sizing.Icon.sm))
                        .foregroundColor(signalColor(for: rssi))

                    Text("\(signalText(for: rssi)) (\(rssi) dBm)")
                        .font(designSystem.typography.captionSmall)
                        .foregroundColor(designSystem.colors.textTertiary)
                }
            }

            // Connection Button
            if device.connectionState != .connected && device.connectionState != .connecting {
                Button {
                    Task {
                        do {
                            try await deviceManager.connect(to: device)
                        } catch {
                            Logger.shared.error(" Connection failed: \(error.localizedDescription)")
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "link")
                        Text("Connect")
                    }
                    .font(designSystem.typography.buttonSmall)
                    .foregroundColor(designSystem.colors.textPrimary)
                    .padding(.vertical, designSystem.spacing.xs)
                    .padding(.horizontal, designSystem.spacing.sm)
                    .background(designSystem.colors.backgroundSecondary)
                    .cornerRadius(designSystem.cornerRadius.md)
                }
                .buttonStyle(.plain)
            } else if device.connectionState == .connected {
                Button {
                    Task {
                        await deviceManager.disconnect(from: device)
                    }
                } label: {
                    HStack {
                        Image(systemName: "link.slash")
                        Text("Disconnect")
                    }
                    .font(designSystem.typography.buttonSmall)
                    .foregroundColor(designSystem.colors.error)
                    .padding(.vertical, designSystem.spacing.xs)
                    .padding(.horizontal, designSystem.spacing.sm)
                    .background(designSystem.colors.backgroundSecondary)
                    .cornerRadius(designSystem.cornerRadius.md)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, designSystem.spacing.xs)
    }

    private func signalIcon(for rssi: Int) -> String {
        switch rssi {
        case -50...0: return "antenna.radiowaves.left.and.right"
        case -70 ..< -50: return "wifi.circle"
        case -85 ..< -70: return "wifi.circle.fill"
        default: return "wifi.slash"
        }
    }

    private func signalColor(for rssi: Int) -> Color {
        switch rssi {
        case -50...0: return designSystem.colors.success
        case -70 ..< -50: return designSystem.colors.success
        case -85 ..< -70: return designSystem.colors.warning
        default: return designSystem.colors.error
        }
    }
    
    private func signalText(for rssi: Int) -> String {
        switch rssi {
        case -50...0: return "Excellent"
        case -70 ..< -50: return "Good"
        case -85 ..< -70: return "Fair"
        default: return "Weak"
        }
    }
}

// MARK: - Connected Device Row View

struct ConnectedDeviceRowView: View {
    let device: DeviceInfo
    @ObservedObject var deviceManager: DeviceManager
    @EnvironmentObject var designSystem: DesignSystem

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.xs) {
            // Device Name
            HStack {
                Image(systemName: device.type.icon)
                    .foregroundColor(designSystem.colors.textPrimary)

                Text(device.name)
                    .font(designSystem.typography.bodyLarge)
                    .foregroundColor(designSystem.colors.textPrimary)

                Spacer()

                if deviceManager.primaryDevice?.id == device.id {
                    Text("PRIMARY")
                        .font(designSystem.typography.captionSmall)
                        .foregroundColor(designSystem.colors.success)
                        .padding(.horizontal, designSystem.spacing.xs)
                        .padding(.vertical, 2)
                        .background(designSystem.colors.success.opacity(0.1))
                        .cornerRadius(designSystem.cornerRadius.sm)
                }
            }

            // Battery Level
            if let battery = device.batteryLevel {
                HStack(spacing: designSystem.spacing.xs) {
                    Image(systemName: batteryIcon(for: battery))
                        .foregroundColor(batteryColor(for: battery))

                    Text("\(battery)%")
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }

            // Firmware Version
            if let firmware = device.firmwareVersion {
                HStack(spacing: designSystem.spacing.xs) {
                    Image(systemName: "info.circle")
                        .foregroundColor(designSystem.colors.textTertiary)

                    Text("Firmware: \(firmware)")
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }

            // Set Primary Button
            if deviceManager.primaryDevice?.id != device.id {
                Button("Set as Primary") {
                    deviceManager.setPrimaryDevice(device)
                }
                .font(designSystem.typography.buttonSmall)
                .foregroundColor(designSystem.colors.textSecondary)
            }
        }
        .padding(.vertical, designSystem.spacing.xs)
    }

    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 75...100: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        default: return "battery.25"
        }
    }

    private func batteryColor(for level: Int) -> Color {
        switch level {
        case 50...100: return designSystem.colors.success
        case 20..<50: return designSystem.colors.warning
        default: return designSystem.colors.error
        }
    }
}

// MARK: - Sensor Reading Row View

struct SensorReadingRowView: View {
    let reading: SensorReading
    @EnvironmentObject var designSystem: DesignSystem

    var body: some View {
        HStack {
            Image(systemName: reading.sensorType.iconName)
                .font(.system(size: DesignSystem.Sizing.Icon.md))
                .foregroundColor(designSystem.colors.textPrimary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(reading.sensorType.displayName)
                    .font(designSystem.typography.bodyMedium)
                    .foregroundColor(designSystem.colors.textPrimary)

                Text(timeAgo(from: reading.timestamp))
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(reading.formattedValue)
                    .font(designSystem.typography.labelLarge)
                    .foregroundColor(designSystem.colors.textPrimary)

                if reading.isValid {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DesignSystem.Sizing.Icon.xs))
                        .foregroundColor(designSystem.colors.success)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: DesignSystem.Sizing.Icon.xs))
                        .foregroundColor(designSystem.colors.error)
                }
            }
        }
        .padding(.vertical, designSystem.spacing.xxs)
    }
    
    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 2 {
            return "Just now"
        } else if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }
}

// MARK: - Preview

#Preview {
    DeviceTestView()
        .environmentObject(DesignSystem())
}

#Preview("With Mock Data") {
    let mockDeviceManager = DeviceManager()
    let demoDevices: [DeviceInfo] = [
        DeviceInfo.demo(type: .oralable),
        DeviceInfo.demo(type: .anr)
    ]
    mockDeviceManager.discoveredDevices = demoDevices

    return DeviceTestView(previewDeviceManager: mockDeviceManager)
        .environmentObject(DesignSystem()) as any View
}
