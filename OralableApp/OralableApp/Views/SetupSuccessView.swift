//
//  SetupSuccessView.swift
//  OralableApp
//
//  Shown after Temporalis IR-DC calibration completes successfully.
//  Uses PrimaryBlack / PrimaryWhite for an Apple Health–style monochrome read.
//

import SwiftUI

struct SetupSuccessView: View {
    @EnvironmentObject var designSystem: DesignSystem
    /// Invoked when the user continues to the main dashboard / dismisses the fit flow.
    let onContinue: () -> Void
    @State private var hasContinued = false

    private var colors: ColorSystem { designSystem.colors }

    var body: some View {
        NavigationStack {
            VStack(spacing: designSystem.spacing.xl) {
                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(colors.primaryBlack.opacity(0.08))
                        .frame(width: 120, height: 120)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(colors.primaryBlack)
                }

                VStack(spacing: designSystem.spacing.sm) {
                    Text("Setup complete")
                        .font(designSystem.typography.h2)
                        .foregroundColor(colors.primaryBlack)
                    Text(
                        "Your Oralable REV10 Node is paired, fitted, and calibrated for the Temporalis muscle."
                    )
                    .font(designSystem.typography.body)
                    .foregroundColor(colors.primaryBlack.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, designSystem.spacing.lg)
                }

                VStack(alignment: .leading, spacing: designSystem.spacing.md) {
                    readinessRow(icon: "waveform.path.ecg", title: "50 Hz signal locked")
                    readinessRow(icon: "scope", title: "Baseline verified (1.5 V – 2.5 V)")
                    readinessRow(icon: "chart.bar.fill", title: "TFI & SASHB metrics enabled")
                }
                .font(designSystem.typography.bodySmall)
                .foregroundColor(colors.primaryBlack)
                .padding(designSystem.spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: designSystem.cornerRadius.card, style: .continuous)
                        .fill(colors.primaryWhite)
                        .shadow(color: colors.primaryBlack.opacity(0.06), radius: 8, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: designSystem.cornerRadius.card, style: .continuous)
                        .stroke(colors.primaryBlack.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, designSystem.spacing.md)

                Spacer(minLength: 0)

                Button {
                    continueIfNeeded()
                } label: {
                    Text("Go to dashboard")
                        .font(designSystem.typography.labelMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(colors.primaryBlack)
                        .foregroundColor(colors.primaryWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, designSystem.spacing.md)
                .padding(.bottom, designSystem.spacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.primaryWhite.ignoresSafeArea())
            .navigationTitle("Ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(colors.primaryWhite, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    continueIfNeeded()
                }
            }
        }
    }

    private func readinessRow(icon: String, title: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(colors.primaryBlack)
        }
    }

    private func continueIfNeeded() {
        guard !hasContinued else { return }
        hasContinued = true
        onContinue()
    }
}
