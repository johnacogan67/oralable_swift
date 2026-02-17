import SwiftUI

// MARK: - Time Range Picker Component
struct HistoricalTimeRangePicker: View {
    @Binding var selectedRange: TimeRange

    var body: some View {
        HStack(spacing: 30) {
            ForEach([TimeRange.hour, TimeRange.day, TimeRange.week], id: \.self) { range in
                Button(action: {
                    selectedRange = range
                }) {
                    Text(range.rawValue)
                        .font(.system(size: 17, weight: selectedRange == range ? .semibold : .regular))
                        .foregroundColor(selectedRange == range ? .blue : .primary)
                }
                .accessibilityLabel("Time range: \(range.rawValue)")
                .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
                .accessibilityHint(selectedRange == range ? "Currently selected" : "Double tap to select \(range.rawValue) view")
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Time range selector")
    }
}
