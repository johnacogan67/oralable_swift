//
//  MainDashboardView.swift
//  OralableApp
//
//  Sleep-study gate: overnight entry requires Temporalis fit guide + 10-minute calibration
//  for the currently connected REV10. Also links to legacy debug menu.
//

import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var historicalDataManager: HistoricalDataManager
    @EnvironmentObject var recordingSessionManager: RecordingSessionManager
    @EnvironmentObject var deviceManagerAdapter: DeviceManagerAdapter
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var sessionHistoryStore: SessionHistoryStore
    @EnvironmentObject var sensorDataProcessor: SensorDataProcessor
    @EnvironmentObject var memoryFlushStatus: MemoryFlushStatus
    @EnvironmentObject var firstLaunchManager: FirstLaunchManager

    @State private var showTemporalisFitGuide = false
    @State private var showOvernightNotice = false

    private var rev10PrimaryConnected: Bool {
        guard deviceManagerAdapter.isConnected,
              (deviceManager.primaryBLEDevice as? OralableDevice) != nil,
              let pid = deviceManager.primaryDevice?.peripheralIdentifier else { return false }
        return deviceManager.connectedDevices.contains {
            $0.peripheralIdentifier == pid && $0.connectionState == .connected
        }
    }

    private var overnightSessionAllowed: Bool {
        sessionHistoryStore.isOvernightSessionAllowed(
            primaryPeripheralId: deviceManager.primaryDevice?.peripheralIdentifier,
            isPrimaryConnected: rev10PrimaryConnected
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: designSystem.spacing.lg) {
                    Text("Sleep study")
                        .font(designSystem.typography.h2)
                        .foregroundColor(designSystem.colors.textPrimary)

                    Text("Sessions recorded: \(recordingSessionManager.sessions.count)")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                    Text("REV10 connected: \(rev10PrimaryConnected ? "Yes" : "No")")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.textSecondary)

                    if let cal = sessionHistoryStore.temporalisSleepCalibration {
                        Text("Last calibration: \(cal.completedAt.formatted(date: .abbreviated, time: .shortened)), baseline \(String(format: "%.2f", cal.baselineVoltage)) V")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }

                    Button {
                        showTemporalisFitGuide = true
                    } label: {
                        Label("Temporalis fit & 10-minute calibration", systemImage: "camera.viewfinder")
                            .font(designSystem.typography.labelMedium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(designSystem.colors.primaryBlack)
                            .foregroundColor(designSystem.colors.primaryWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(!rev10PrimaryConnected)
                    .opacity(rev10PrimaryConnected ? 1 : 0.45)

                    if !rev10PrimaryConnected {
                        Text("Connect your Oralable REV10 as the primary device to run the fit guide.")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }

                    Button {
                        showOvernightNotice = true
                    } label: {
                        Label("Start overnight session", systemImage: "moon.stars.fill")
                            .font(designSystem.typography.labelMedium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(overnightSessionAllowed ? designSystem.colors.success.opacity(0.2) : designSystem.colors.gray200)
                            .foregroundColor(overnightSessionAllowed ? designSystem.colors.textPrimary : designSystem.colors.textDisabled)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(!overnightSessionAllowed)

                    if !overnightSessionAllowed {
                        Text("Complete the Temporalis fit guide and calibration for this headset before starting an overnight session.")
                            .font(designSystem.typography.caption)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }

                    NavigationLink {
                        DebugMenuView()
                    } label: {
                        Text("Debug menu")
                            .font(designSystem.typography.labelMedium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(designSystem.colors.backgroundTertiary)
                            .foregroundColor(designSystem.colors.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(designSystem.spacing.lg)
            }
            .background(designSystem.colors.backgroundSecondary)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if deviceManagerAdapter.batteryLevel > 0 {
                            Label(
                                "\(Int(deviceManagerAdapter.batteryLevel))%",
                                systemImage: "battery.100"
                            )
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(designSystem.colors.textPrimary)
                        }
                        HStack(spacing: 5) {
                            Circle()
                                .fill(
                                    memoryFlushStatus.lastApplicationSupportFlushAt != nil
                                        ? Color.green
                                        : designSystem.colors.gray400.opacity(0.45)
                                )
                                .frame(width: 8, height: 8)
                            Text("Cloud Sync")
                                .font(.caption2)
                                .foregroundStyle(designSystem.colors.textSecondary)
                        }
                        .accessibilityLabel(
                            memoryFlushStatus.lastApplicationSupportFlushAt != nil
                                ? "Cloud Sync: hourly memory flush saved"
                                : "Cloud Sync: waiting for hourly memory flush"
                        )
                    }
                    .help("Cloud Sync turns green after an hourly memory-flush CSV is written under Application Support.")
                }
            }
        }
        .sheet(isPresented: $showTemporalisFitGuide) {
            TemporalisFitGuideView {
                showTemporalisFitGuide = false
            }
            .environmentObject(designSystem)
            .environmentObject(deviceManagerAdapter)
            .environmentObject(deviceManager)
            .environmentObject(sessionHistoryStore)
            .environmentObject(sensorDataProcessor)
            .environmentObject(firstLaunchManager)
        }
        .alert("Overnight session", isPresented: $showOvernightNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Overnight capture hooks to your existing automatic recording session when this flag is wired to Product. Calibration for this REV10 is on file.")
        }
    }
}
