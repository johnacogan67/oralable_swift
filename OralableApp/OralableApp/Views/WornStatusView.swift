//
//  WornStatusView.swift
//  OralableApp
//
//  Created by John A Cogan on 22/12/2025.
//


import SwiftUI

import SwiftUI

/// An Apple-inspired UI component to indicate sensor coupling and HR.
struct WornStatusView: View {
    @EnvironmentObject var designSystem: DesignSystem
    let result: HRResult?

    private var isWorn: Bool {
        (result?.confidence ?? 0) > 0.5
    }

    private var bpm: Int {
        Int(result?.bpm ?? 0)
    }

    private var confidence: Double {
        result?.confidence ?? 0
    }

    var body: some View {
        HStack(spacing: designSystem.spacing.buttonPadding) {
            // Pulse Circle
            ZStack {
                Circle()
                    .stroke(isWorn ? designSystem.colors.success.opacity(0.2) : designSystem.colors.gray400.opacity(0.1), lineWidth: 4)
                    .frame(width: 44, height: 44)

                if isWorn {
                    Image(systemName: "heart.fill")
                        .foregroundColor(designSystem.colors.error)
                        .scaleEffect(isWorn ? 1.1 : 1.0)
                        .animation(Animation.easeInOut(duration: 0.6).repeatForever(), value: isWorn)
                } else {
                    Image(systemName: "person.fill.viewfinder")
                        .foregroundColor(designSystem.colors.gray400)
                }
            }

            VStack(alignment: .leading, spacing: designSystem.spacing.xxs) {
                Text(isWorn ? "Sensor Coupled" : "Reposition Sensor")
                    .font(designSystem.typography.captionBold)
                    .foregroundColor(designSystem.colors.textPrimary)

                if isWorn {
                    Text(bpm > 0 ? "\(bpm) BPM" : "Measuring...")
                        .font(designSystem.typography.captionSmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                } else {
                    Text("Finding pulse at masseter...")
                        .font(designSystem.typography.captionSmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }

            Spacer()

            // Signal Quality Bar
            HStack(spacing: designSystem.spacing.xxs) {
                ForEach(0..<4) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(qualityColor(for: index))
                        .frame(width: 4, height: CGFloat(index + 1) * 4)
                }
            }
        }
        .padding(designSystem.spacing.md)
        .background(designSystem.colors.backgroundPrimary)
        .cornerRadius(designSystem.cornerRadius.large)
        .designShadow(.small)
    }

    private func qualityColor(for index: Int) -> Color {
        let barsToFill = Int(confidence * 4)
        if index < barsToFill {
            return isWorn ? designSystem.colors.success : designSystem.colors.warning
        }
        return designSystem.colors.gray400.opacity(0.2)
    }
}
