//
//  BatteryIndicator.swift
//  OralableApp
//
//  Minimal battery status indicator.
//

import SwiftUI

struct BatteryIndicator: View {
    @EnvironmentObject var designSystem: DesignSystem
    let level: Int  // 0-100
    let isCharging: Bool

    private var batteryColor: Color {
        if isCharging { return designSystem.colors.success }
        if level <= 20 { return designSystem.colors.error }
        if level <= 40 { return designSystem.colors.warning }
        return designSystem.colors.textPrimary
    }

    private var iconName: String {
        if isCharging { return "battery.100.bolt" }
        if level <= 10 { return "battery.0" }
        if level <= 25 { return "battery.25" }
        if level <= 50 { return "battery.50" }
        if level <= 75 { return "battery.75" }
        return "battery.100"
    }

    var body: some View {
        HStack(spacing: designSystem.spacing.xs) {
            Image(systemName: iconName)
                .font(designSystem.typography.labelSmall)
                .foregroundColor(batteryColor)

            Text("\(level)%")
                .font(designSystem.typography.labelSmall)
                .foregroundColor(designSystem.colors.textSecondary)
        }
    }
}

// MARK: - Preview

struct BatteryIndicator_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            BatteryIndicator(level: 100, isCharging: false)
            BatteryIndicator(level: 75, isCharging: false)
            BatteryIndicator(level: 50, isCharging: true)
            BatteryIndicator(level: 25, isCharging: false)
            BatteryIndicator(level: 10, isCharging: false)
        }
        .padding()
    }
}
