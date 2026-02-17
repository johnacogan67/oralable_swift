import SwiftUI

struct HeartRateView: View {
    @EnvironmentObject var designSystem: DesignSystem
    @Binding var wornStatus: WornStatus
    @Binding var heartRateResult: HRResult?

    @State private var isBeating = false

    var body: some View {
        VStack {
            switch wornStatus {
            case .initializing:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                Text("Initializing...")
                    .font(designSystem.typography.captionSmall)
                    .foregroundColor(designSystem.colors.textSecondary)
            case .repositioning:
                VStack {
                    Image(systemName: "person.fill.questionmark")
                        .font(designSystem.typography.h1)
                        .foregroundColor(designSystem.colors.warning)
                    Text("Adjust Sensor Position")
                        .font(designSystem.typography.headline)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            case .active:
                if let result = heartRateResult, result.bpm > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: designSystem.spacing.xs) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(designSystem.colors.error)
                            .scaleEffect(isBeating ? 1.2 : 1.0)
                            .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isBeating)
                        Text("\(Int(result.bpm))")
                            .font(designSystem.typography.h2)
                            .fontWeight(.bold)
                        Text("BPM")
                            .font(designSystem.typography.captionSmall)
                            .foregroundColor(designSystem.colors.textSecondary)
                    }
                    .onAppear {
                        isBeating = true
                    }
                } else {
                    Text("-- BPM")
                        .font(designSystem.typography.h2)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(designSystem.colors.backgroundTertiary)
        .cornerRadius(designSystem.cornerRadius.large)
    }
}
