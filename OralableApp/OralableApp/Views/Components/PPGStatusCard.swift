//
//  PPGStatusCard.swift
//  OralableApp
//
//  Single card showing device positioning and muscle activity status.
//  Color-coded: Black (not positioned), Green (rest), Red (activity)
//
//  Design: Apple-inspired, minimal
//

import SwiftUI

struct PPGStatusCard: View {
    @EnvironmentObject var designSystem: DesignSystem
    let state: PositioningState
    let temperature: Double
    let isConnected: Bool
    let isCalibrating: Bool
    let calibrationProgress: Double

    /// Whether the state is calibrating (from enum or explicit flag)
    private var isInCalibration: Bool {
        if case .calibrating = state { return true }
        return isCalibrating
    }

    /// Get calibration progress from state or explicit parameter
    private var effectiveCalibrationProgress: Double {
        if case .calibrating(let progress) = state {
            return progress
        }
        return calibrationProgress
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main status area
            mainStatusArea

            // Bottom info bar
            bottomInfoBar
        }
        .clipShape(RoundedRectangle(cornerRadius: designSystem.cornerRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: designSystem.cornerRadius.xl)
                .stroke(designSystem.colors.gray400, lineWidth: 0.5)
        )
        .opacity(isConnected ? 1.0 : 0.5)
    }

    // MARK: - Main Status Area

    private var mainStatusArea: some View {
        VStack(spacing: designSystem.spacing.md) {
            if isInCalibration {
                // Calibration progress
                calibrationView
            } else {
                // Normal status display
                statusView
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, designSystem.spacing.xxl)
        .background(state.backgroundColor)
    }

    private var calibrationView: some View {
        VStack(spacing: designSystem.spacing.md) {
            ProgressView(value: effectiveCalibrationProgress)
                .progressViewStyle(CircularProgressViewStyle(tint: designSystem.colors.primaryWhite))
                .scaleEffect(1.5)

            Text(state.statusText)
                .font(designSystem.typography.displaySmall)
                .foregroundColor(designSystem.colors.primaryWhite)

            Text(state.description)
                .font(designSystem.typography.caption)
                .foregroundColor(designSystem.colors.primaryWhite.opacity(0.8))
        }
    }

    private var statusView: some View {
        VStack(spacing: designSystem.spacing.md) {
            Image(systemName: state.iconName)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(state.textColor)

            Text(state.statusText)
                .font(designSystem.typography.displaySmall)
                .foregroundColor(state.textColor)

            Text(state.description)
                .font(designSystem.typography.caption)
                .foregroundColor(state.textColor.opacity(0.8))
        }
    }

    // MARK: - Bottom Info Bar

    private var bottomInfoBar: some View {
        HStack {
            // Temperature
            Label {
                Text(String(format: "%.1f°C", temperature))
                    .font(designSystem.typography.labelSmall)
            } icon: {
                Image(systemName: "thermometer")
                    .font(designSystem.typography.caption2)
            }
            .foregroundColor(designSystem.colors.textSecondary)

            Spacer()

            // Positioning indicator
            if temperature >= 32.0 {
                Label("On Skin", systemImage: "checkmark.circle.fill")
                    .font(designSystem.typography.labelSmall)
                    .foregroundColor(designSystem.colors.success)
            } else {
                Label("Off Skin", systemImage: "xmark.circle.fill")
                    .font(designSystem.typography.labelSmall)
                    .foregroundColor(designSystem.colors.textSecondary)
            }
        }
        .padding(.horizontal, designSystem.spacing.md)
        .padding(.vertical, designSystem.spacing.buttonPadding)
        .background(designSystem.colors.backgroundTertiary)
    }
}

// MARK: - Preview

struct PPGStatusCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            PPGStatusCard(
                state: .notPositioned,
                temperature: 28.5,
                isConnected: true,
                isCalibrating: false,
                calibrationProgress: 0
            )

            PPGStatusCard(
                state: .rest,
                temperature: 33.2,
                isConnected: true,
                isCalibrating: false,
                calibrationProgress: 0
            )

            PPGStatusCard(
                state: .activity,
                temperature: 33.5,
                isConnected: true,
                isCalibrating: false,
                calibrationProgress: 0
            )

            PPGStatusCard(
                state: .calibrating(progress: 0.6),
                temperature: 33.0,
                isConnected: true,
                isCalibrating: false,
                calibrationProgress: 0
            )
        }
        .padding()
        .background(Color(.systemBackground))
    }
}
