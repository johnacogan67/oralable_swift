//
//  DeveloperSettingsView.swift
//  OralableApp
//
//  Created: December 4, 2025
//  Purpose: Hidden developer settings for enabling feature flags
//  Access: Tap "About" row 7 times in Settings
//  Updated: December 13, 2025 - Simplified for pre-launch
//

import SwiftUI

struct DeveloperSettingsView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var dependencies: AppDependencies
    @ObservedObject private var featureFlags = FeatureFlags.shared
    @State private var fwGreenPA: Double = 5
    @State private var fwIrPA: Double = 128
    @State private var fwRedPA: Double = 32
    @State private var fwStatsPeriod: Double = 5
    @State private var fwBatteryInterval: Double = 10
    @State private var fwTempInterval: Double = 1
    @State private var fwEnablePPG: Bool = true
    @State private var fwEnableACC: Bool = true
    @State private var lastFwConfigStatus: String?

    var body: some View {
        Form {
            // Dashboard Features Section
            Section("Dashboard Features") {
                Toggle("EMG Card", isOn: $featureFlags.showEMGCard)
                Toggle("Movement Card", isOn: $featureFlags.showMovementCard)
                Toggle("Temperature Card", isOn: $featureFlags.showTemperatureCard)
                Toggle("Heart Rate Card", isOn: $featureFlags.showHeartRateCard)
                Toggle("SpO2 Card", isOn: $featureFlags.showSpO2Card)
                Toggle("Battery Card", isOn: $featureFlags.showBatteryCard)
            }

            // Share Features Section
            Section("Share Features") {
                Toggle("CloudKit Sharing", isOn: $featureFlags.showCloudKitShare)
            }

            // Subscription Section
            Section("Subscription") {
                Toggle("Subscription UI", isOn: $featureFlags.showSubscription)
            }

            // Other Features Section
            Section("Other Features") {
                Toggle("Detection Settings", isOn: $featureFlags.showDetectionSettings)
            }

            // Reset Section
            Section {
                Button("Reset to Defaults") {
                    featureFlags.resetToDefaults()
                }
                .foregroundColor(designSystem.colors.error)
            }

            Section("Firmware (Oralable)") {
                Text(lastFwConfigStatus ?? "Not configured yet")
                    .font(designSystem.typography.bodySmall)
                    .foregroundColor(designSystem.colors.textSecondary)

                HStack {
                    Text("LED Green PA")
                    Spacer()
                    Text("\(Int(fwGreenPA))")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
                Slider(value: $fwGreenPA, in: 0...255, step: 1)

                HStack {
                    Text("LED IR PA")
                    Spacer()
                    Text("\(Int(fwIrPA))")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
                Slider(value: $fwIrPA, in: 0...255, step: 1)

                HStack {
                    Text("LED Red PA")
                    Spacer()
                    Text("\(Int(fwRedPA))")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
                Slider(value: $fwRedPA, in: 0...255, step: 1)

                Stepper(value: $fwStatsPeriod, in: 0...30, step: 1) {
                    Text("FW stats period: \(Int(fwStatsPeriod))s (0=off)")
                }

                Stepper(value: $fwBatteryInterval, in: 0...255, step: 1) {
                    Text("Battery interval: \(Int(fwBatteryInterval))s (0=off)")
                }

                Stepper(value: $fwTempInterval, in: 0...255, step: 1) {
                    Text("Temp interval: \(Int(fwTempInterval))s (0=off)")
                }

                Toggle("Enable PPG streaming", isOn: $fwEnablePPG)
                Toggle("Enable ACC streaming", isOn: $fwEnableACC)

                Button("Apply firmware settings") {
                    Task { await applyFirmwareSettings() }
                }

                Button("Request conn param update now") {
                    Task { await requestConnParamUpdate() }
                }
            }
        }
        .navigationTitle("Developer Settings")
    }

    private func applyFirmwareSettings() async {
        guard let oralable = dependencies.deviceManager.primaryBLEDevice as? OralableDevice else {
            lastFwConfigStatus = "No primary Oralable device connected"
            return
        }
        do {
            try oralable.setFirmwareLedPA(.green, pa: UInt8(Int(fwGreenPA)))
            try oralable.setFirmwareLedPA(.ir, pa: UInt8(Int(fwIrPA)))
            try oralable.setFirmwareLedPA(.red, pa: UInt8(Int(fwRedPA)))
            try oralable.setFirmwareStreamStatsPeriodSeconds(UInt8(Int(fwStatsPeriod)))
            try oralable.setFirmwareBatteryIntervalSeconds(UInt8(Int(fwBatteryInterval)))
            try oralable.setFirmwareTempIntervalSeconds(UInt8(Int(fwTempInterval)))
            var mask: UInt8 = 0
            if fwEnablePPG { mask |= 0x01 }
            if fwEnableACC { mask |= 0x02 }
            try oralable.setFirmwareStreamEnableMask(mask)
            lastFwConfigStatus = "Applied @ \(Date().formatted(date: .omitted, time: .standard))"
        } catch {
            lastFwConfigStatus = "Apply failed: \(error.localizedDescription)"
        }
    }

    private func requestConnParamUpdate() async {
        guard let oralable = dependencies.deviceManager.primaryBLEDevice as? OralableDevice else {
            lastFwConfigStatus = "No primary Oralable device connected"
            return
        }
        do {
            try oralable.requestFirmwareConnParamUpdate()
            lastFwConfigStatus = "Requested conn param update @ \(Date().formatted(date: .omitted, time: .standard))"
        } catch {
            lastFwConfigStatus = "Request failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        DeveloperSettingsView()
    }
}
