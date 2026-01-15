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
    let state: PositioningState
    let temperature: Double
    let isConnected: Bool
    let isCalibrating: Bool
    let calibrationProgress: Double

    var body: some View {
        VStack(spacing: 0) {
            // Main status area
            mainStatusArea

            // Bottom info bar
            bottomInfoBar
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .opacity(isConnected ? 1.0 : 0.5)
    }

    // MARK: - Main Status Area

    private var mainStatusArea: some View {
        VStack(spacing: 16) {
            if isCalibrating {
                // Calibration progress
                calibrationView
            } else {
                // Normal status display
                statusView
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(isCalibrating ? Color.blue : state.backgroundColor)
    }

    private var calibrationView: some View {
        VStack(spacing: 16) {
            ProgressView(value: calibrationProgress)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)

            Text("Calibrating...")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)

            Text("Please remain still")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))

            Text("\(Int(calibrationProgress * 100))%")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var statusView: some View {
        VStack(spacing: 16) {
            Image(systemName: state.iconName)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(state.textColor)

            Text(state.statusText)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(state.textColor)

            Text(state.description)
                .font(.system(size: 14))
                .foregroundColor(state.textColor.opacity(0.8))
        }
    }

    // MARK: - Bottom Info Bar

    private var bottomInfoBar: some View {
        HStack {
            // Temperature
            Label {
                Text(String(format: "%.1f°C", temperature))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            } icon: {
                Image(systemName: "thermometer")
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary)

            Spacer()

            // Positioning indicator
            if temperature >= 32.0 {
                Label("On Skin", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            } else {
                Label("Off Skin", systemImage: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
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
                state: .notPositioned,
                temperature: 30.0,
                isConnected: true,
                isCalibrating: true,
                calibrationProgress: 0.6
            )
        }
        .padding()
        .background(Color(.systemBackground))
    }
}
