import SwiftUI

// MARK: - Date Navigation Component
struct HistoricalDateNavigation: View {
    @EnvironmentObject var designSystem: DesignSystem
    @Binding var selectedDate: Date
    let timeRange: TimeRange

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        switch timeRange {
        case .minute:
            formatter.dateFormat = "HH:mm:ss, dd MMM"
        case .hour:
            formatter.dateFormat = "HH:mm, dd MMM"
        case .day:
            formatter.dateFormat = "EEEE, dd MMMM"
        case .week:
            formatter.dateFormat = "dd MMM yyyy"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
        }
        return formatter
    }

    private var displayText: String {
        switch timeRange {
        case .minute:
            return "Minute View"
        case .hour:
            return "Hour View"
        case .day:
            return dateFormatter.string(from: selectedDate)
        case .week:
            let calendar = Calendar.current
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) {
                let endDate = calendar.date(byAdding: .day, value: -1, to: weekInterval.end) ?? weekInterval.end
                let startFormatter = DateFormatter()
                startFormatter.dateFormat = "dd MMM"
                let endFormatter = DateFormatter()
                endFormatter.dateFormat = "dd MMM yyyy"
                return "\(startFormatter.string(from: weekInterval.start)) - \(endFormatter.string(from: endDate))"
            }
            return "This Week"
        case .month:
            return dateFormatter.string(from: selectedDate)
        }
    }

    private func navigateBackward() {
        let calendar = Calendar.current
        switch timeRange {
        case .minute:
            selectedDate = calendar.date(byAdding: .minute, value: -1, to: selectedDate) ?? selectedDate
        case .hour:
            selectedDate = calendar.date(byAdding: .hour, value: -1, to: selectedDate) ?? selectedDate
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        }
    }

    private func navigateForward() {
        let calendar = Calendar.current
        switch timeRange {
        case .minute:
            selectedDate = calendar.date(byAdding: .minute, value: 1, to: selectedDate) ?? selectedDate
        case .hour:
            selectedDate = calendar.date(byAdding: .hour, value: 1, to: selectedDate) ?? selectedDate
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        }
    }

    private var canNavigateForward: Bool {
        let calendar = Calendar.current
        let today = Date()

        switch timeRange {
        case .minute:
            let currentMinuteStart = calendar.dateInterval(of: .minute, for: selectedDate)?.start ?? selectedDate
            let thisMinuteStart = calendar.dateInterval(of: .minute, for: today)?.start ?? today
            return currentMinuteStart < thisMinuteStart
        case .hour:
            let currentHourStart = calendar.dateInterval(of: .hour, for: selectedDate)?.start ?? selectedDate
            let thisHourStart = calendar.dateInterval(of: .hour, for: today)?.start ?? today
            return currentHourStart < thisHourStart
        case .day:
            return !calendar.isDate(selectedDate, inSameDayAs: today)
        case .week:
            let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
            let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            return currentWeekStart < thisWeekStart
        case .month:
            let currentMonth = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
            let thisMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
            return currentMonth < thisMonth
        }
    }

    var body: some View {
        HStack {
            Button(action: navigateBackward) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(designSystem.colors.info)
                    .frame(width: 44, height: 44)
                    .background(designSystem.colors.gray400.opacity(0.1))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Previous \(timeRange.rawValue)")
            .accessibilityHint("Navigate to the previous \(timeRange.rawValue)")

            Spacer()

            VStack {
                Text(displayText)
                    .font(.headline)
                    .fontWeight(.medium)

                if timeRange != .day {
                    Text(periodInfo)
                        .font(.caption)
                        .foregroundColor(designSystem.colors.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current period: \(displayText)")

            Spacer()

            Button(action: navigateForward) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundColor(canNavigateForward ? designSystem.colors.info : designSystem.colors.gray400)
                    .frame(width: 44, height: 44)
                    .background(designSystem.colors.gray400.opacity(0.1))
                    .clipShape(Circle())
            }
            .disabled(!canNavigateForward)
            .accessibilityLabel("Next \(timeRange.rawValue)")
            .accessibilityHint(canNavigateForward ? "Navigate to the next \(timeRange.rawValue)" : "No future data available")
        }
        .padding(.vertical, designSystem.spacing.sm)
    }

    private var periodInfo: String {
        let calendar = Calendar.current
        switch timeRange {
        case .minute:
            guard let interval = calendar.dateInterval(of: .minute, for: selectedDate) else { return "" }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let endTime = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            return "\(formatter.string(from: interval.start)) - \(formatter.string(from: endTime))"
        case .hour:
            guard let interval = calendar.dateInterval(of: .hour, for: selectedDate) else { return "" }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let endTime = calendar.date(byAdding: .minute, value: -1, to: interval.end) ?? interval.end
            return "\(formatter.string(from: interval.start)) - \(formatter.string(from: endTime))"
        case .day:
            return ""
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return "" }
            let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: interval.start)) - \(formatter.string(from: end))"
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: selectedDate) else { return "" }
            let daysInMonth = calendar.range(of: .day, in: .month, for: selectedDate)?.count ?? 0
            return "\(daysInMonth) days"
        }
    }
}
