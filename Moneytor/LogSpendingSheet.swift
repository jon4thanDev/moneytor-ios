import SwiftUI
import SwiftData

struct LogSpendingSheet: View {
    let category: BudgetCategory
    /// Shown at the top when opened from a bill reminder, like "Overdue since Sep 15".
    var reminder: String?
    var onLogged: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Decimal?
    @State private var note = ""
    @State private var date = Date.now
    @State private var picksDate = false
    @AppStorage("linksExpensesToIncome") private var linksExpenses = false
    @Query private var incomes: [IncomeSource]
    @State private var fundingAmounts: [PersistentIdentifier: Decimal] = [:]
    /// Lets the user add more to a limit that's already fully used.
    @State private var logsAnyway = false
    @State private var isTransferring = false

    var body: some View {
        let remaining = category.remainingThisPeriod
        let remainingAfter = remaining - (amount ?? 0)
        let isBill = category.dueDay != nil
        let showsPaid = category.limit > 0 && remaining <= 0 && !logsAnyway

        let spent = category.spentThisPeriod
        let available = category.availableThisPeriod
        let transferred = category.transferredThisPeriod
        let entered = max(amount ?? 0, 0)
        let isPreviewing = entered > 0 && !showsPaid
        let shownRemaining = isPreviewing ? remainingAfter : remaining
        let usedRatio = available > 0 ? NSDecimalNumber(decimal: (spent + entered) / available).doubleValue : 1
        let tint: Color = shownRemaining < 0 ? .red : usedRatio >= 0.8 && shownRemaining > 0 ? .orange : .green
        let period = category.currentPeriod
        let schedule = switch category.frequency {
        case .once: "Ends \(period.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))"
        case .daily: "Resets tomorrow"
        case .weekly: "Resets \(period.end.formatted(.dateTime.weekday(.wide)))"
        case .biweekly: "Resets \(period.end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        case .monthly: "Resets \(period.end.formatted(.dateTime.month(.abbreviated).day()))"
        }

        // One focal number (what's left), a bar that previews this expense, and the context underneath.
        let summary = VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(abs(shownRemaining), format: .currency(code: currencyCode))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: NSDecimalNumber(decimal: shownRemaining).doubleValue))
                        .foregroundStyle(shownRemaining < 0 ? .red : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(shownRemaining < 0 ? "over" : "left")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Text(isPreviewing
                     ? "after this · was \(abs(remaining).formatted(.currency(code: currencyCode)))\(remaining < 0 ? " over" : "")"
                     : category.periodName.prefix(1).uppercased() + category.periodName.dropFirst())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let spentWidth = available > 0
                    ? min(NSDecimalNumber(decimal: spent / available).doubleValue, 1) * geometry.size.width
                    : geometry.size.width
                let previewWidth = min(usedRatio, 1) * geometry.size.width - spentWidth
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    HStack(spacing: 0) {
                        Rectangle().fill(tint).frame(width: spentWidth)
                        Rectangle().fill(tint.opacity(0.4)).frame(width: max(previewWidth, 0))
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 10)

            HStack {
                Text("\(spent.formatted(.currency(code: currencyCode))) of \(category.periodLimit.formatted(.currency(code: currencyCode))) \(isBill ? "paid" : "used")")
                Spacer()
                Label(schedule, systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Transfers change what's left, not the category's own limit.
            if transferred != 0 {
                Label("\(transferred.formatted(.currency(code: currencyCode).sign(strategy: .always()))) transferred \(transferred > 0 ? "in" : "out") \(category.periodName)",
                      systemImage: transferred > 0 ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                    .font(.caption)
                    .foregroundStyle(transferred > 0 ? .green : .orange)
            }
        }
        .padding(.vertical, 6)
        .animation(.snappy, value: amount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(abs(shownRemaining).formatted(.currency(code: currencyCode))) \(shownRemaining < 0 ? "over" : "left")\(isPreviewing ? " after this" : ""). \(spent.formatted(.currency(code: currencyCode))) of \(category.periodLimit.formatted(.currency(code: currencyCode))) \(isBill ? "paid" : "used")\(transferred == 0 ? "" : ", \(transferred.formatted(.currency(code: currencyCode).sign(strategy: .always()))) transferred"). \(schedule).")

        NavigationStack {
            Form {
                if let reminder {
                    Label(reminder, systemImage: "bell.badge.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if showsPaid {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(.green)
                            Text(isBill ? "Already Paid" : "Limit Complete")
                                .font(.title3.bold())
                            Text("You've used the full \(category.name) limit \(category.periodName).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        summary
                    }

                    Section {
                        Button("Add Another Expense", systemImage: "plus.circle") {
                            logsAnyway = true
                        }
                        Button("Transfer Funds", systemImage: "arrow.left.arrow.right") { isTransferring = true }
                    } footer: {
                        Text("Move unused money from another expense into \(category.name).")
                    }

                    ExpenseHistory(category: category)
                } else {
                    Section {
                        summary
                    } header: {
                        Label("\(category.name) · \(category.periodName)", systemImage: category.icon)
                    }

                    Section {
                        HStack {
                            Text(Locale.current.currencySymbol ?? "$")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            CalculatorField(
                                value: $amount,
                                font: .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .largeTitle).pointSize, weight: .bold),
                                focusesOnAppear: true
                            )
                        }
                    } footer: {
                        if remainingAfter < 0 && entered > 0 {
                            Label("This goes \((-remainingAfter).formatted(.currency(code: currencyCode))) over your \(category.name) limit.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    Section {
                        TextField("Note (optional)", text: $note)
                        Toggle("Set Date", isOn: $picksDate.animation())
                        if picksDate {
                            DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                                .closesWhenPicked(date)
                        }
                    } footer: {
                        if !picksDate {
                            Text("Leave off to use the time you add it.")
                        }
                    }

                    if linksExpenses {
                        FundingPicker(total: amount ?? 0, amounts: $fundingAmounts)
                    }

                    Section {
                        Button("Transfer Funds", systemImage: "arrow.left.arrow.right") { isTransferring = true }
                    } footer: {
                        Text("Move money you won't use in \(category.name) to another expense, or bring some in.")
                    }

                    ExpenseHistory(category: category)
                }
            }
            .navigationTitle(showsPaid ? category.name : "Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            // Both items always exist and only their content changes: toolbar items inserted while
            // switching from the paid summary to the input could end up not responding to taps.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showsPaid ? "Close" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !showsPaid {
                        Button("Add") {
                            guard let amount else { return }
                            let log = SpendLog(
                                amount: amount,
                                note: note.trimmingCharacters(in: .whitespaces),
                                date: picksDate ? date : nil,
                                category: category
                            )
                            context.insert(log)
                            if linksExpenses { log.setFundings(fundingAmounts, from: incomes, in: context) }
                            onLogged?()
                            dismiss()
                        }
                        .disabled(amount == nil || amount! <= 0
                                  || (linksExpenses && fundingAmounts.values.reduce(0, +) != amount))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $isTransferring) { TransferSheet(category: category) }
    }
}
