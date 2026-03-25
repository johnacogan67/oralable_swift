//
//  TFIFatigueGaugeView.swift
//  OralableApp
//
//  Oralable MAM — Temporalis Fatigue Index (0–100%) radial gauge for dashboard home.
//

import SwiftUI

struct TFIFatigueGaugeView: View {
    @EnvironmentObject var designSystem: DesignSystem
    /// 0 ... 100
    var valuePercent: Double
    var subtitle: String = "Morning-after muscle exhaustion proxy"

    private var clamped: Double {
        min(100, max(0, valuePercent))
    }

    var body: some View {
        VStack(spacing: designSystem.spacing.sm) {
            ZStack {
                Circle()
                    .stroke(designSystem.colors.gray200, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(clamped / 100.0))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                designSystem.colors.success,
                                designSystem.colors.warning,
                                designSystem.colors.error
                            ]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(String(format: "%.0f%%", clamped))
                        .font(designSystem.typography.displaySmall)
                        .foregroundColor(designSystem.colors.textPrimary)
                    Text("TFI")
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }
            .frame(width: 132, height: 132)

            Text("Temporalis Fatigue Index (TFI)")
                .font(designSystem.typography.labelMedium)
                .foregroundColor(designSystem.colors.textPrimary)
            Text(subtitle)
                .font(designSystem.typography.captionSmall)
                .foregroundColor(designSystem.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(designSystem.spacing.md)
        .frame(maxWidth: .infinity)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.card)
        .designShadow(.small)
    }
}
