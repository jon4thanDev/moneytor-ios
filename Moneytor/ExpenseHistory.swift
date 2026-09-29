import SwiftUI
import SwiftData

/// A category's past expenses, newest first. Swipe to delete one logged by mistake.
struct ExpenseHistory: View {
    let category: BudgetCategory

    @Environment(\.modelContext) private var context

    var body: some View {
        let logs = category.logs.sorted { $0.effectiveDate > $1.effectiveDate }
        let isBill = category.dueDay != nil

        Section {
            if logs.isEmpty {
                Text(isBill ? "No payments yet." : "No expenses yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(logs) { log in
                let incomeNames = log.fundings.compactMap(\.income?.name)
                let paidFrom = incomeNames.isEmpty ? log.paidFrom : incomeNames.joined(separator: ", ")
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.note.isEmpty ? (isBill ? "Payment" : "Expense") : log.note)
                        HStack(spacing: 4) {
                            LogDateLabel(log: log)
                            if let paidFrom {
                                Text("· from \(paidFrom)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(log.amount, format: .currency(code: currencyCode))
                        .monospacedDigit()
                        .foregroundStyle(category.isInCurrentPeriod(log.effectiveDate) ? .primary : .secondary)
                }
            }
            .onDelete { offsets in
                offsets.forEach { context.delete(logs[$0]) }
            }
        } header: {
            HStack {
                Text(isBill ? "Payment History" : "Expense History")
                Spacer()
                if !logs.isEmpty {
                    Text(logs.reduce(0) { $0 + $1.amount }, format: .currency(code: currencyCode))
                        .textCase(nil)
                }
            }
        } footer: {
            if !logs.isEmpty {
                Text("A calendar means you set the date. A clock shows when it was logged.")
            }
        }
    }
}

/// The date the user set for an expense, or when it was logged if they didn't set one.
struct LogDateLabel: View {
    let log: SpendLog

    var body: some View {
        let date = log.effectiveDate
        let isThisYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let day = isThisYear ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(.dateTime.month(.abbreviated).day().year())

        if log.date != nil {
            Label(day, systemImage: "calendar")
                .labelStyle(CompactLabelStyle())
        } else {
            Label("\(day), \(date.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                .labelStyle(CompactLabelStyle())
        }
    }
}

/// Icon and text sitting close together, for small captions.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
