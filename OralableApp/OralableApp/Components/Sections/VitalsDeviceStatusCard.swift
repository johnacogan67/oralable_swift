//
//  VitalsDeviceStatusCard.swift
//  OralableApp
//
//  Phase 0 vitals dashboard: firmware status + HR/SpO2 quality without user calibration.
//

import SwiftUI
import OralableCore

struct VitalsDeviceStatusCard: View {
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var deviceManager: DeviceManager

    let heartRate: Int
    let heartRateQuality: Double
    let spo2: Int
    let spo2Quality: Double
    let placementMode: FeatureFlags.DevicePlacementMode
    let rssi: Int?

    private var firmwareStatus: TGMDeviceStatus? {
        deviceManager.primaryFirmwareDeviceStatus
    }

    private var operationalState: DeviceOperationalState {
        firmwareStatus?.operationalState(
            userPlacementMode: placementMode.rawValue,
            heartRateQuality: heartRateQuality,
            spo2Quality: spo2Quality
        ) ?? .benchIdle
    }

    private var statusLED: DeviceStatusLEDRepresentation? {
        firmwareStatus?.statusLED(userPlacementMode: placementMode.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            HStack {
                statusDot
                Text(operationalState.title)
                    .font(designSystem.typography.headline)
                Spacer()
                if let pct = firmwareStatus?.batteryPercent {
                    Text("\(pct)%")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }

            Text(operationalState.detail)
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)

            if let status = firmwareStatus {
                HStack(spacing: designSystem.spacing.md) {
                    flagChip("Dock", active: status.onDock)
                    flagChip(
                        status.chargeActive ? "Charging" : (status.onDock ? "Taper" : "Charge"),
                        active: status.chargeActive
                    )
                    flagChip("Worn", active: status.worn)
                }
            }

            if let fw = deviceManager.primaryFirmwareVersion() {
                Text(
                    FirmwareGate.supportsAutomaticDockDetect(fw)
                        ? "FW \(fw) — STAT blink drives dock/charge."
                        : "FW \(fw) — recommend \(FirmwareGate.recommendedOralableSemanticVersion) for Automatic dock."
                )
                .font(designSystem.typography.captionSmall)
                .foregroundColor(
                    FirmwareGate.supportsAutomaticDockDetect(fw)
                        ? designSystem.colors.textTertiary
                        : designSystem.colors.warning
                )
            }

            if let statusLED {
                DeviceStatusLEDView(representation: statusLED)
            }

            Divider()

            HStack {
                vitalsColumn(
                    title: "Heart rate",
                    value: heartRate > 0 ? "\(heartRate)" : "—",
                    unit: "BPM",
                    quality: heartRateQuality
                )
                Spacer()
                vitalsColumn(
                    title: "SpO₂",
                    value: spo2 > 0 ? "\(spo2)" : "—",
                    unit: "%",
                    quality: spo2Quality
                )
            }

            HStack {
                Text("Placement: \(placementMode.title)")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textTertiary)
                Spacer()
                if let rssi {
                    Text("RSSI \(rssi) dBm")
                        .font(designSystem.typography.caption)
                        .foregroundColor(rssiColor(rssi))
                }
            }

            if placementMode == .offDockIdle {
                Text("Green LED on device (dimmed for battery). App mirror above shows live state.")
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.warning)
            } else if placementMode == .onCharger || placementMode == .auto {
                Text("Red LED on Oralable case: flash while charging (STAT blink), solid on charge taper. Battery % is a rough voltage estimate.")
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.textSecondary)
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.card)
        .designShadow(.small)
        .accessibilityElement(children: .combine)
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 10, height: 10)
    }

    private var dotColor: Color {
        switch operationalState {
        case .onCharger: return designSystem.colors.warning
        case .benchIdle: return designSystem.colors.gray400
        case .onBody: return designSystem.colors.info
        case .vitalsReady: return designSystem.colors.success
        }
    }

    private func flagChip(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(designSystem.typography.captionSmall)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? designSystem.colors.success.opacity(0.15) : designSystem.colors.gray100)
            .foregroundColor(active ? designSystem.colors.success : designSystem.colors.textSecondary)
            .cornerRadius(8)
    }

    private func vitalsColumn(title: String, value: String, unit: String, quality: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(designSystem.typography.h3)
                Text(unit)
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            }
            Text(qualityLabel(quality))
                .font(designSystem.typography.captionSmall)
                .foregroundColor(qualityColor(quality))
        }
    }

    private func qualityLabel(_ q: Double) -> String {
        if q >= 0.7 { return "Good signal" }
        if q >= 0.4 { return "Fair signal" }
        if q > 0 { return "Poor signal" }
        return "Searching…"
    }

    private func qualityColor(_ q: Double) -> Color {
        if q >= 0.7 { return designSystem.colors.success }
        if q >= 0.4 { return designSystem.colors.warning }
        return designSystem.colors.textSecondary
    }

    private func rssiColor(_ rssi: Int) -> Color {
        if rssi >= -70 { return designSystem.colors.success }
        if rssi >= -85 { return designSystem.colors.warning }
        return designSystem.colors.error
    }
}
