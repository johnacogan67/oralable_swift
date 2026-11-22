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
import OralableCore

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
    @State private var nrfLogStatus: String = ""
    @State private var nrfExportURL: URL?
    @State private var showNRFExportSheet = false
    @State private var edfExportURL: URL?
    @State private var showEDFExportSheet = false
    @State private var edfStatus: String = ""
    @State private var simNightStatus: String = ""
    @State private var isWritingSimNight = false

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
                Toggle("Overnight Hypnogram", isOn: $featureFlags.showOvernightHypnogram)
            }

            // Share Features Section
            Section("Share Features") {
                Toggle("CloudKit Sharing", isOn: $featureFlags.showCloudKitShare)
            }

            // Subscription Section
            Section("Subscription") {
                Toggle("Subscription UI", isOn: $featureFlags.showSubscription)
            }

            Section("Other Features") {
                Toggle("Detection Settings", isOn: $featureFlags.showDetectionSettings)
                Toggle("Vitals phase (HR + SpO₂)", isOn: $featureFlags.vitalsPhaseEnabled)
                Toggle("Require Protocol A Setup", isOn: $featureFlags.requireProtocolASetup)
                if featureFlags.vitalsPhaseEnabled {
                    Text("Dual Protocol A is off in vitals / Beacon builds (MAM only). Turn off Vitals phase to enable Dual for lab use.")
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                } else {
                    Toggle("Dual Protocol A (research)", isOn: $featureFlags.showDualProtocolA)
                }
            }

            Section {
                Text("Require Protocol A Setup (default OFF for Beacon): pair then dashboard. Turn ON only for the ~6 min couple seat-QC session.")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
                Text("Dual Protocol A: lab only (~6 min + ANR). Default OFF. Not a Beacon patient path. Dual A Share includes session.edf with ANR EMG.")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            }

            Section("Simulated night") {
                Text("4 h worn script: quiet, clench, grind, and oxygen drops. Local only. Not a recorded night.")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
                Button("Load simulated 4 h worn night") {
                    loadSimulatedNight()
                }
                .disabled(isWritingSimNight)
                if !simNightStatus.isEmpty {
                    Text(simNightStatus)
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }

            Section("Research EDF+") {
                Text("MAM-only EDF from live history (no EMG). For Dual A with ANR EMG, use Dual Protocol A Share.")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
                Button("Export MAM-only session.edf") {
                    exportOralableOnlyEDF()
                }
                if !edfStatus.isEmpty {
                    Text(edfStatus)
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }
            .sheet(isPresented: $showEDFExportSheet) {
                if let edfExportURL {
                    ShareSheet(items: [edfExportURL])
                }
            }

            Section("Bench recovery") {
                Stepper(value: Binding(
                    get: { Int(featureFlags.debugRebootIntervalMinutes) },
                    set: { featureFlags.debugRebootIntervalMinutes = UInt16(max(0, $0)) }
                ), in: 0...60) {
                    Text("FW reboot interval: \(featureFlags.debugRebootIntervalMinutes) min (0=off)")
                }
                Text("Sends opcode 0x0A on connect. Use only when BLE advertising hangs.")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            }

            // Reset Section
            Section {
                Button("Reset to Defaults") {
                    featureFlags.resetToDefaults()
                }
                .foregroundColor(designSystem.colors.error)
            }

            Section("nRF Connect BLE Log") {
                Text("CSV format: Timestamp,Source,Level,Line — matches nRF Connect exports for side-by-side comparison.")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)

                Toggle("Enable fw-log notify (00A) on connect", isOn: $featureFlags.enableFirmwareLogNotify)

                Text("Lines captured: \(NRFConnectBLELogger.shared.lineCount())")
                    .font(designSystem.typography.bodySmall)

                Toggle("Log all notify values (no 1 Hz throttle)", isOn: Binding(
                    get: { !NRFConnectBLELogger.shared.throttleHighRateNotifications },
                    set: { NRFConnectBLELogger.shared.throttleHighRateNotifications = !$0 }
                ))

                Button("Export nRF-style CSV") {
                    exportNRFConnectLog()
                }

                Button("Clear BLE session log") {
                    NRFConnectBLELogger.shared.clear()
                    nrfLogStatus = "Log cleared"
                }

                if !nrfLogStatus.isEmpty {
                    Text(nrfLogStatus)
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }

            Section("Firmware (MAM)") {
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

                Button("Dump firmware diagnostics") {
                    Task { await dumpFirmwareDiagnostics() }
                }
            }
        }
        .navigationTitle("Developer Settings")
        .sheet(isPresented: $showNRFExportSheet) {
            if let url = nrfExportURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func exportNRFConnectLog() {
        do {
            let url = try NRFConnectBLELogger.shared.exportToFile()
            nrfExportURL = url
            nrfLogStatus = "Exported \(NRFConnectBLELogger.shared.lineCount()) lines"
            showNRFExportSheet = true
        } catch {
            nrfLogStatus = "Export failed: \(error.localizedDescription)"
        }
    }

    private func applyFirmwareSettings() async {
        guard let oralable = dependencies.deviceManager.primaryBLEDevice as? OralableDevice else {
            lastFwConfigStatus = "No primary MAM connected"
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
            lastFwConfigStatus = "No primary MAM connected"
            return
        }
        do {
            try oralable.requestFirmwareConnParamUpdate()
            lastFwConfigStatus = "Requested conn param update @ \(Date().formatted(date: .omitted, time: .standard))"
        } catch {
            lastFwConfigStatus = "Request failed: \(error.localizedDescription)"
        }
    }

    private func loadSimulatedNight() {
        isWritingSimNight = true
        simNightStatus = "Writing the night…"
        Task {
            do {
                _ = try await SimulatedWornNight.load(using: dependencies.recordingSessionManager)
                featureFlags.showOvernightHypnogram = true
                simNightStatus = "Loaded. Open the dashboard. Simulated — not a recorded night."
            } catch {
                simNightStatus = error.localizedDescription
            }
            isWritingSimNight = false
        }
    }

    private func exportOralableOnlyEDF() {
        let history = SensorDataProcessor.shared.sensorDataHistory
        do {
            let url = try ResearchEDFExport.writeOralableOnly(from: history)
            edfExportURL = url
            edfStatus = "Wrote \(url.lastPathComponent)"
            showEDFExportSheet = true
        } catch {
            edfStatus = error.localizedDescription
        }
    }

    private func dumpFirmwareDiagnostics() async {
        guard let oralable = dependencies.deviceManager.primaryBLEDevice as? OralableDevice else {
            lastFwConfigStatus = "No primary MAM connected"
            return
        }
        do {
            try await oralable.requestFirmwareDiagnosticsDump()
            lastFwConfigStatus = "Diagnostics dump @ \(Date().formatted(date: .omitted, time: .standard)) — export nRF CSV for [FW] lines"
        } catch {
            lastFwConfigStatus = "Diagnostics failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        DeveloperSettingsView()
    }
}
