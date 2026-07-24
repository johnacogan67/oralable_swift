//
//  VitalsPlacementPickerSection.swift
//  OralableApp
//
//  Pre-connect placement picker (Gen1 pcb00003 — set before BLE connect, not in Settings).
//

import SwiftUI

struct VitalsPlacementPickerSection: View {
    @ObservedObject private var featureFlags = FeatureFlags.shared
    @EnvironmentObject var designSystem: DesignSystem
    @EnvironmentObject var deviceManager: DeviceManager

    var showWornOption: Bool = true
    var compact: Bool = false

    private var firmwareVersion: String? {
        deviceManager.primaryFirmwareVersion()
    }

    private var automaticDockSupported: Bool {
        FirmwareGate.supportsAutomaticDockDetect(firmwareVersion)
    }

    private var selectableModes: [FeatureFlags.DevicePlacementMode] {
        FeatureFlags.DevicePlacementMode.allCases.filter { mode in
            if mode == .worn, !showWornOption { return false }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.sm) {
            Text("Where is the clip right now?")
                .font(compact ? designSystem.typography.headline : designSystem.typography.h3)
                .foregroundColor(designSystem.colors.textPrimary)

            Text("Pick this before you tap Connect. Gen1 cannot change placement safely during an active link.")
                .font(designSystem.typography.bodySmall)
                .foregroundColor(designSystem.colors.textSecondary)

            Picker("Placement", selection: $featureFlags.devicePlacementMode) {
                ForEach(selectableModes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.inline)

            Text(featureFlags.devicePlacementMode.detail)
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.textSecondary)

            if let firmwareVersion {
                Text("Firmware \(firmwareVersion)"
                    + (automaticDockSupported
                        ? " — Automatic dock detect OK."
                        : " — use manual placement until \(FirmwareGate.recommendedOralableSemanticVersion)."))
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(
                        automaticDockSupported
                            ? designSystem.colors.success
                            : designSystem.colors.warning
                    )
            } else if featureFlags.devicePlacementMode == .auto {
                Text("Automatic needs FW \(FirmwareGate.recommendedOralableSemanticVersion)+. If Connect fails dock detection, switch to On wireless charger.")
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.warning)
            }

            if featureFlags.devicePlacementMode == .onCharger {
                Label(
                    "Oralable case + USB-C only. Red flash = charging; solid red = charge taper (not always 4.2 V).",
                    systemImage: "circle.fill"
                )
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.warning)
            }
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(designSystem.colors.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: designSystem.spacing.sm, style: .continuous))
    }
}
