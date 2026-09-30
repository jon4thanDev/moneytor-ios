import SwiftUI

enum NewMonthChoice {
    case keep, keepAndAdd, startFresh
}

/// Shown once when a new month starts, so the user decides how to set up this month's budget.
struct NewMonthSheet: View {
    let categories: [BudgetCategory]
    let onChoose: (NewMonthChoice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        let spentLastMonth = categories
            .flatMap(\.logs)
            .filter { Calendar.current.isDate($0.countedDate, equalTo: lastMonth, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
        let totalLimit = categories.reduce(0) { $0 + $1.limitThisMonth }

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to \(Date.now.formatted(.dateTime.month(.wide)))!")
                            .font(.title2.bold())
                        Text("In \(lastMonth.formatted(.dateTime.month(.wide))) your expenses were \(spentLastMonth.formatted(.currency(code: currencyCode))) of your \(totalLimit.formatted(.currency(code: currencyCode))) budget. How do you want to set up this month?")
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    NewMonthOption(
                        title: "Keep My Budget",
                        detail: "Same categories and limits. Expenses start again at \(Decimal(0).formatted(.currency(code: currencyCode))).",
                        icon: "arrow.clockwise",
                        isRecommended: true
                    ) { choose(.keep) }
                    NewMonthOption(
                        title: "Keep & Add Categories",
                        detail: "Keep everything from last month, then add new categories.",
                        icon: "plus.square.on.square"
                    ) { choose(.keepAndAdd) }
                    NewMonthOption(
                        title: "Start Fresh",
                        detail: "Build a new set of categories from scratch. Your past expenses stay saved.",
                        icon: "square.and.pencil"
                    ) { choose(.startFresh) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func choose(_ choice: NewMonthChoice) {
        onChoose(choice)
        dismiss()
    }
}

private struct NewMonthOption: View {
    let title: String
    let detail: String
    let icon: String
    var isRecommended = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                        if isRecommended {
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .tint(.primary)
    }
}
