import SwiftUI

// MARK: - Clear Data Button Component
struct ShareClearDataButton: View {
    @Binding var showClearConfirmation: Bool
    @ObservedObject var sensorDataProcessor: SensorDataProcessor
    @EnvironmentObject var designSystem: DesignSystem

    private var hasData: Bool {
        !sensorDataProcessor.sensorDataHistory.isEmpty
    }

    var body: some View {
        Button(action: { showClearConfirmation = true }) {
            HStack(spacing: designSystem.spacing.sm) {
                Image(systemName: "trash")
                    .font(.system(size: DesignSystem.Sizing.Icon.sm))

                Text("Clear All Data")
                    .font(designSystem.typography.buttonMedium)
            }
            .foregroundColor(hasData ? .red : designSystem.colors.textDisabled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, designSystem.spacing.md)
            .background(hasData ? Color.red.opacity(0.1) : designSystem.colors.backgroundTertiary)
            .cornerRadius(designSystem.cornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: designSystem.cornerRadius.lg)
                    .stroke(hasData ? Color.red.opacity(0.3) : designSystem.colors.border, lineWidth: 1)
            )
        }
        .disabled(!hasData)
    }
}
