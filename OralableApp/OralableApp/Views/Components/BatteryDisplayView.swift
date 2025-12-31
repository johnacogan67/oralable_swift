//
//  BatteryDisplayView.swift
//  OralableApp
//
//  Created: December 3, 2025
//

import SwiftUI
import OralableCore

struct BatteryDisplayView: View {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: status.systemImageName)
                    .foregroundColor(status.color)
                    .font(.title2)

                Text("Battery")
                    .font(.headline)

                Spacer()

                Text(status.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status.color.opacity(0.2))
                    .foregroundColor(status.color)
                    .cornerRadius(8)
            }

            BatteryBarView(percentage: percentage, status: status)

            HStack {
                Text(BatteryConversion.formatPercentage(percentage))
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)

                Spacer()

                if showVoltage {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(BatteryConversion.formatVoltage(millivolts: millivolts))
                            .font(.system(.body, design: .monospaced))
                        Text("voltage")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if BatteryConversion.needsCharging(percentage: percentage) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(BatteryConversion.isCritical(percentage: percentage) ? .red : .orange)
                    Text(BatteryConversion.isCritical(percentage: percentage) ? "Battery critically low!" : "Battery low - charge soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct BatteryBarView: View {
    let percentage: Double
    let status: BatteryStatus

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))

                RoundedRectangle(cornerRadius: 6)
                    .fill(status.color)
                    .frame(width: max(0, geometry.size.width * CGFloat(percentage / 100.0)))
            }
        }
        .frame(height: 24)
    }
}

struct BatteryCompactView: View {
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    Circle()
                        .fill(status.color.opacity(0.1))
                        .frame(width: 40, height: 40)

                    Image(systemName: isCharging ? "battery.100.bolt" : status.systemImageName)
                        .foregroundColor(status.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery")
                        .font(.headline)
                    Text(isCharging ? "Charging" : status.rawValue)
                        .font(.caption)
                        .foregroundColor(isCharging ? .green : status.color)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f", percentage))
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                    Text("%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            BatteryBarView(percentage: percentage, status: status)

            HStack {
                Text("Voltage:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(BatteryConversion.formatVoltage(millivolts: millivolts))
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
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
