import SwiftUI
import SwiftData

/// A category's past expenses and transfers, newest first. Swipe to delete one made by mistake.
struct ExpenseHistory: View {
    let category: BudgetCategory

    @Environment(\.modelContext) private var context
    @State private var shownCount: Int?

    private enum Entry: Identifiable {
        case expense(SpendLog)
        case transfer(Transfer)

        var id: PersistentIdentifier {
            switch self {
            case .expense(let log): log.persistentModelID
            case .transfer(let transfer): transfer.persistentModelID
            }
        }

        var date: Date {
            switch self {
            case .expense(let log): log.effectiveDate
            case .transfer(let transfer): transfer.createdAt
            }
        }
    }

    var body: some View {
        let logs = category.logs
        let entries = (logs.map(Entry.expense) + (category.transfersIn + category.transfersOut).map(Entry.transfer))
            .sorted { $0.date > $1.date }
        let dates = entries.map(\.date)
        let shownEntries = Array(entries.prefix(min(shownCount ?? LoadMoreButton.initialCount(dates), entries.count)))
        let isBill = category.dueDay != nil

        Section {
            if entries.isEmpty {
                Text(isBill ? "No payments yet." : "No expenses yet.")
                    .foregroundStyle(.secondary)
            } else if shownEntries.isEmpty {
                Text(isBill ? "No payments this month." : "No expenses this month.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shownEntries) { entry in
                switch entry {
                case .expense(let log):
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
                case .transfer(let transfer):
                    let isIncoming = transfer.to == category
                    let isThisPeriod = category.isInCurrentPeriod(transfer.createdAt)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: isIncoming ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                                    .foregroundStyle(isIncoming ? .green : .orange)
                                Text(isIncoming ? "From \(transfer.from?.name ?? transfer.fromName)" : "To \(transfer.to?.name ?? transfer.toName)")
                            }
                            if !transfer.note.isEmpty {
                                TruncatedNote(note: transfer.note)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Label("Transfer · \(transfer.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))",
                                  systemImage: "arrow.left.arrow.right")
                                .labelStyle(CompactLabelStyle())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(isIncoming ? transfer.amount : -transfer.amount,
                             format: .currency(code: currencyCode).sign(strategy: .always()))
                            .monospacedDigit()
                            .foregroundStyle(!isThisPeriod ? .secondary : isIncoming ? Color.green : Color.orange)
                    }
                }
            }
            .onDelete { offsets in
                for offset in offsets {
                    switch shownEntries[offset] {
                    case .expense(let log): context.delete(log)
                    case .transfer(let transfer): context.delete(transfer)
                    }
                }
            }
            LoadMoreButton(dates: dates, shown: $shownCount)
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
            if !entries.isEmpty {
                Text("A calendar means you set the date. A clock shows when it was logged. Transfers count in the period they were made.")
            }
        }
    }
}

/// "Load More" for long histories. Loads 20 rows at a time, but never past the end of the month the
/// next row is in, so older months come in one at a time.
struct LoadMoreButton: View {
    static let pageSize = 20
    /// Every row's date, newest first.
    let dates: [Date]
    /// How many rows are showing; nil means the first page.
    @Binding var shown: Int?

    /// The first page: this month's rows, up to 20.
    static func initialCount(_ dates: [Date]) -> Int {
        min(pageSize, dates.prefix { Calendar.current.isDate($0, equalTo: .now, toGranularity: .month) }.count)
    }

    var body: some View {
        let current = min(shown ?? Self.initialCount(dates), dates.count)
        if current < dates.count {
            let month = dates[current]
            let batch = min(Self.pageSize, dates[current...].prefix { Calendar.current.isDate($0, equalTo: month, toGranularity: .month) }.count)
            let isThisYear = Calendar.current.isDate(month, equalTo: .now, toGranularity: .year)
            Button { shown = current + batch } label: {
                HStack {
                    Label("Load More", systemImage: "arrow.down.circle")
                    Spacer()
                    Text("\(batch) from \(month.formatted(isThisYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year()))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
