import SwiftUI

struct HeartRateView: View {
    @Binding var wornStatus: WornStatus
    @Binding var heartRateResult: HeartRateService.HRResult?

    @State private var isBeating = false

    var body: some View {
        VStack {
            switch wornStatus {
            case .initializing:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                Text("Initializing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .repositioning:
                VStack {
                    Image(systemName: "person.fill.questionmark")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text("Adjust Sensor Position")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            case .active:
                if let result = heartRateResult, result.bpm > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .scaleEffect(isBeating ? 1.2 : 1.0)
                            .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isBeating)
                        Text("\(Int(result.bpm))")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("BPM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .onAppear {
                        isBeating = true
                    }
                } else {
                    Text("-- BPM")
                        .font(.title)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }
}
