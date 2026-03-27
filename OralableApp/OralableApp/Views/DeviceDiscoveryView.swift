//
//  DeviceDiscoveryView.swift
//  OralableApp
//
//  Withings Health Mate–style onboarding: tall product cards, scan reticle, clear CTAs.
//

import SwiftUI

struct DeviceDiscoveryView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var designSystem: DesignSystem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: designSystem.spacing.md) {
                    Text("Add a device")
                        .font(designSystem.typography.h3)
                        .foregroundColor(designSystem.colors.textPrimary)
                        .padding(.horizontal, 4)

                    Text("Choose your sensor, then scan. We’ll connect using the right protocol for that product line.")
                        .font(designSystem.typography.bodySmall)
                        .foregroundColor(designSystem.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if deviceManager.isScanning {
                        HStack {
                            Spacer()
                            PulsingReticleView(accent: designSystem.colors.primaryBlack)
                                .frame(width: 80, height: 80)
                            Spacer()
                        }
                        .padding(.vertical, designSystem.spacing.sm)
                        .accessibilityLabel("Scanning for Bluetooth devices")
                    }

                    VStack(spacing: designSystem.spacing.lg) {
                        ForEach(DeviceManagerFactory.Product.allCases) { product in
                            discoveryCard(for: product)
                        }
                    }
                }
                .padding(designSystem.spacing.md)
            }
            .background(designSystem.colors.backgroundSecondary)
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(deviceManager.isScanning ? "Stop" : "Scan") {
                        if deviceManager.isScanning {
                            deviceManager.stopScanning()
                        } else {
                            Task { await deviceManager.startScanning() }
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func discoveryCard(for product: DeviceManagerFactory.Product) -> some View {
        let candidates = deviceManager.discoveredDevices.filter { $0.type == product.coreDeviceType }
        let found = candidates.first

        return VStack(alignment: .leading, spacing: designSystem.spacing.md) {
            HStack(alignment: .top, spacing: designSystem.spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(designSystem.colors.backgroundSecondary)
                        .frame(width: 56, height: 56)
                    Image(systemName: product.systemIcon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(designSystem.colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(product.cardTitle)
                        .font(designSystem.typography.headline)
                        .foregroundColor(designSystem.colors.textPrimary)
                    Text(product.subtitle)
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
                Spacer(minLength: 0)
            }

            if product == .temporalisHeadband {
                Text("50 Hz stream · Oralable REV10")
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.textTertiary)
            }

            if !product.isAvailableForPairing {
                Label("Coming in a future update", systemImage: "clock")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textSecondary)
            } else if let found {
                Text(found.name)
                    .font(designSystem.typography.bodySmall)
                    .foregroundColor(designSystem.colors.textSecondary)

                Button {
                    DeviceManagerFactory.performHandshake(for: product, deviceManager: deviceManager)
                    Task {
                        try? await deviceManager.connect(to: found)
                    }
                } label: {
                    Text("Connect")
                        .font(designSystem.typography.labelMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(designSystem.colors.primaryBlack)
                        .foregroundColor(designSystem.colors.primaryWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(deviceManager.isConnecting)
            } else if deviceManager.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Searching nearby…")
                        .font(designSystem.typography.caption)
                        .foregroundColor(designSystem.colors.textTertiary)
                }
            } else {
                Text("Tap Scan above, then bring this device close to your iPhone.")
                    .font(designSystem.typography.caption)
                    .foregroundColor(designSystem.colors.textTertiary)
            }
        }
        .padding(designSystem.spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(designSystem.colors.backgroundPrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(designSystem.colors.border.opacity(0.45), lineWidth: 1)
        )
        .designShadow(.small)
    }
}

// MARK: - Pulsing Reticle

private struct PulsingReticleView: View {
    var accent: Color
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.28), lineWidth: 2)
                .scaleEffect(animate ? 1.45 : 0.9)
                .opacity(animate ? 0 : 0.9)

            Circle()
                .stroke(accent.opacity(0.45), lineWidth: 2)
                .frame(width: 40, height: 40)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(accent, lineWidth: 2)
                .frame(width: 22, height: 22)
        }
        .onAppear {
            animate = false
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}
