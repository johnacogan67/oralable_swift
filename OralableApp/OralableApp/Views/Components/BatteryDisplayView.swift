//
//  BatteryDisplayView.swift
//  OralableApp
//
//  Created: December 3, 2025
//

import SwiftUI
import OralableCore

struct BatteryDisplayView: View {
    @EnvironmentObject var designSystem: DesignSystem
    let millivolts: Int32
    let showVoltage: Bool

    init(millivolts: Int32, showVoltage: Bool = true) {
        self.millivolts = millivolts
        self.showVoltage = showVoltage
    }

    private var percentage: Double {
        BatteryConversion.voltageToPercentage(millivolts: millivolts)
    }

    private var status: BatteryStatus {
        BatteryConversion.batteryStatus(percentage: percentage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.buttonPadding) {
            HStack {
                Image(systemName: status.systemImageName)
                    .foregroundColor(status.color)
                    .font(designSystem.typography.h3)

                Text("Battery")
                    .font(designSystem.typography.headline)

                Spacer()

                Text(status.rawValue)
                    .font(designSystem.typography.captionSmall)
                    .fontWeight(.medium)
                    .padding(.horizontal, designSystem.spacing.sm)
                    .padding(.vertical, designSystem.spacing.xs)
                    .background(status.color.opacity(0.2))
                    .foregroundColor(status.color)
                    .cornerRadius(designSystem.cornerRadius.medium)
            }

            BatteryBarView(percentage: percentage, status: status)

            HStack {
                Text(BatteryConversion.formatPercentage(percentage))
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)

                Spacer()

                if showVoltage {
                    VStack(alignment: .trailing, spacing: designSystem.spacing.xxs) {
                        Text(BatteryConversion.formatVoltage(millivolts: millivolts))
                            .font(.system(.body, design: .monospaced))
                        Text("voltage")
                            .font(designSystem.typography.caption2)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                }
            }

            if BatteryConversion.needsCharging(percentage: percentage) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(BatteryConversion.isCritical(percentage: percentage) ? designSystem.colors.error : designSystem.colors.warning)
                    Text(BatteryConversion.isCritical(percentage: percentage) ? "Battery critically low!" : "Battery low - charge soon")
                        .font(designSystem.typography.captionSmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.large)
        .designShadow(.medium)
    }
}

struct BatteryBarView: View {
    @EnvironmentObject var designSystem: DesignSystem
    let percentage: Double
    let status: BatteryStatus

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: designSystem.cornerRadius.sm)
                    .fill(designSystem.colors.gray300.opacity(0.2))

                RoundedRectangle(cornerRadius: designSystem.cornerRadius.sm)
                    .fill(status.color)
                    .frame(width: max(0, geometry.size.width * CGFloat(percentage / 100.0)))
            }
        }
        .frame(height: designSystem.spacing.lg)
    }
}

struct BatteryCompactView: View {
    @EnvironmentObject var designSystem: DesignSystem
    let millivolts: Int32

    private var percentage: Double {
        BatteryConversion.voltageToPercentage(millivolts: millivolts)
    }

    private var status: BatteryStatus {
        BatteryConversion.batteryStatus(percentage: percentage)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.systemImageName)
                .foregroundColor(status.color)

            Text(BatteryConversion.formatPercentage(percentage))
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
        }
    }
}

struct BatteryCardView: View {
    @EnvironmentObject var designSystem: DesignSystem
    let millivolts: Int32
    let isCharging: Bool

    init(millivolts: Int32, isCharging: Bool = false) {
        self.millivolts = millivolts
        self.isCharging = isCharging
    }

    private var percentage: Double {
        BatteryConversion.voltageToPercentage(millivolts: millivolts)
    }

    private var status: BatteryStatus {
        BatteryConversion.batteryStatus(percentage: percentage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            HStack {
                ZStack {
                    Circle()
                        .fill(status.color.opacity(0.1))
                        .frame(width: 40, height: 40)

                    Image(systemName: isCharging ? "battery.100.bolt" : status.systemImageName)
                        .foregroundColor(status.color)
                }

                VStack(alignment: .leading, spacing: designSystem.spacing.xxs) {
                    Text("Battery")
                        .font(designSystem.typography.headline)
                    Text(isCharging ? "Charging" : status.rawValue)
                        .font(designSystem.typography.captionSmall)
                        .foregroundColor(isCharging ? designSystem.colors.success : status.color)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: designSystem.spacing.xxs) {
                    Text(String(format: "%.0f", percentage))
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                    Text("%")
                        .font(designSystem.typography.captionSmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }

            BatteryBarView(percentage: percentage, status: status)

            HStack {
                Text("Voltage:")
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.textSecondary)
                Spacer()
                Text(BatteryConversion.formatVoltage(millivolts: millivolts))
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.xl)
        .designShadow(.medium)
    }
}

#if DEBUG
struct BatteryDisplayView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                BatteryDisplayView(millivolts: 4150)
                BatteryDisplayView(millivolts: 3750)
                BatteryDisplayView(millivolts: 3450)
                BatteryDisplayView(millivolts: 3200)

                HStack(spacing: 20) {
                    BatteryCompactView(millivolts: 4100)
                    BatteryCompactView(millivolts: 3700)
                    BatteryCompactView(millivolts: 3300)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

                BatteryCardView(millivolts: 4000, isCharging: false)
                BatteryCardView(millivolts: 3800, isCharging: true)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}
#endif
