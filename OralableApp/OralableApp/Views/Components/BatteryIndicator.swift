//
//  BatteryIndicator.swift
//  OralableApp
//
//  Minimal battery status indicator.
//

import SwiftUI

struct BatteryIndicator: View {
    let level: Int  // 0-100
    let isCharging: Bool

    private var batteryColor: Color {
        if isCharging { return .green }
        if level <= 20 { return .red }
        if level <= 40 { return .orange }
        return .primary
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
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(batteryColor)

            Text("\(level)%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
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
