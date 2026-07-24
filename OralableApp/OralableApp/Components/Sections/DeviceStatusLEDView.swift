//
//  DeviceStatusLEDView.swift
//  OralableApp
//
//  Live mirror of firmware status LED (green/red PPG channels).
//

import SwiftUI
import OralableCore

struct DeviceStatusLEDView: View {
    @EnvironmentObject var designSystem: DesignSystem

    let representation: DeviceStatusLEDRepresentation

    @State private var flashVisible = true

    var body: some View {
        HStack(spacing: designSystem.spacing.sm) {
            ledGlyph
            VStack(alignment: .leading, spacing: 2) {
                Text("Device LED")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
                Text(representation.detail)
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(representation.accessibilityLabel)
        .onAppear { syncFlashAnimation() }
        .onChange(of: representation) { _ in syncFlashAnimation() }
    }

    @ViewBuilder
    private var ledGlyph: some View {
        let baseColor = ledColor
        let opacity = representation.pattern == .flashing
            ? (flashVisible ? 1.0 : 0.2)
            : (representation.pattern == .solid ? 1.0 : 0.25)

        ZStack {
            Circle()
                .fill(baseColor.opacity(0.15))
                .frame(width: 28, height: 28)
            Circle()
                .fill(baseColor.opacity(opacity))
                .frame(width: 14, height: 14)
                .shadow(color: baseColor.opacity(representation.pattern == .solid ? 0.45 : 0.2),
                        radius: representation.pattern == .solid ? 4 : 2)
        }
    }

    private var ledColor: Color {
        switch representation.color {
        case .red: return designSystem.colors.error
        case .green: return designSystem.colors.success
        case .none: return designSystem.colors.gray400
        }
    }

    private func syncFlashAnimation() {
        flashVisible = true
        guard representation.pattern == .flashing else { return }

        let period: TimeInterval = representation.color == .red ? 2.35 : 1.55
        withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) {
            flashVisible = false
        }
    }
}
