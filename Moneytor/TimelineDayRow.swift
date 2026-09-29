import SwiftUI

/// One day on a timeline: a date badge, the line joining the days, and everything that falls on that day.
/// Rows sit edge to edge in a List, so the line reads as one line across days.
struct TimelineDayRow<Total: View, Content: View>: View {
    let day: Date
    let isFirst: Bool
    let isLast: Bool
    var tint: Color = .accentColor
    @ViewBuilder var total: Total
    @ViewBuilder var content: Content

    var body: some View {
        let calendar = Calendar.current
        let daysAway = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: day)).day ?? 0
        let when = switch daysAway {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        case ..<0: "\(day.formatted(.dateTime.weekday(.wide))) · \(-daysAway) days ago"
        default: "\(day.formatted(.dateTime.weekday(.wide))) · in \(daysAway) days"
        }
        let dayTint = daysAway < 0 ? Color.red : tint
        let rail = tint.opacity(0.3)

        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(day, format: .dateTime.month(.abbreviated))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                Text(day, format: .dateTime.day())
                    .font(.title3.bold())
                    .monospacedDigit()
            }
            .frame(width: 44, height: 48)
            .foregroundStyle(daysAway == 0 ? .white : daysAway < 0 ? .red : .primary)
            .background(daysAway == 0 ? tint : daysAway < 0 ? Color.red.opacity(0.12) : Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10))
            .padding(.vertical, 8)

            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? .clear : rail).frame(width: 2, height: 18)
                Circle().fill(dayTint).frame(width: 10, height: 10)
                Rectangle().fill(isLast ? .clear : rail).frame(width: 2).frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(when)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(daysAway <= 0 ? dayTint : .primary)
                    Spacer()
                    total
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                content
            }
            .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
}
