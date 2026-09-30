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
    /// 0 for the current period; more to pay in advance starting from a later one, like 1 for next month.
    @State private var periodsAhead: Int
    /// How many periods in a row an advance payment covers, like 3 for three months of a loan at once.
    @State private var periodsCovered = 1
    /// The amount last filled in from what the covered periods need, so picking other periods can update
    /// it without overwriting one the user typed.
    @State private var suggestedAmount: Decimal?

    init(category: BudgetCategory, reminder: String? = nil, periodsAhead: Int = 0, onLogged: (() -> Void)? = nil) {
        self.category = category
        self.reminder = reminder
        self.onLogged = onLogged
        _periodsAhead = State(initialValue: category.canPayAhead ? periodsAhead : 0)
    }

    /// How many periods in a row from `periodsAhead` can be paid, stopping at the end date.
    private var coverablePeriods: Int {
        (0..<12).prefix { category.limit(for: category.period(after: periodsAhead + $0)) > 0 }.count
    }

    var body: some View {
        let periods = (0..<(periodsAhead > 0 ? min(periodsCovered, max(coverablePeriods, 1)) : 1)).map { category.period(after: periodsAhead + $0) }
        let period = periods[0]
        // Also a one-time payment that isn't due yet.
        let isAhead = period.start > .now
        let periodName = isAhead ? "for \(category.title(of: periods))" : category.periodName
        let remaining = periods.reduce(0) { $0 + category.remaining(in: $1) }
        let remainingAfter = remaining - (amount ?? 0)
        let isBill = category.dueDay != nil
        let showsPaid = category.limit > 0 && remaining <= 0 && !logsAnyway && !isAhead

        let spent = periods.reduce(0) { $0 + category.spent(in: $1) }
        let transferred = periods.reduce(0) { $0 + category.transferred(in: $1) }
        let periodLimit = periods.reduce(0) { $0 + category.limit(for: $1) }
        let available = periodLimit + transferred
        let entered = max(amount ?? 0, 0)
        let isPreviewing = entered > 0 && !showsPaid
        let shownRemaining = isPreviewing ? remainingAfter : remaining
        let usedRatio = available > 0 ? NSDecimalNumber(decimal: (spent + entered) / available).doubleValue : 1
        let tint: Color = shownRemaining < 0 ? .red : usedRatio >= 0.8 && shownRemaining > 0 ? .orange : .green
        let schedule = if isAhead {
            "Starts \(period.start.formatted(.dateTime.month(.abbreviated).day()))"
        } else {
            switch category.frequency {
            case .once: "Ends \(period.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))"
            case .daily: "Resets tomorrow"
            case .weekly: "Resets \(period.end.formatted(.dateTime.weekday(.wide)))"
            case .biweekly: "Resets \(period.end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
            case .monthly: "Resets \(period.end.formatted(.dateTime.month(.abbreviated).day()))"
            }
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
                     : periodName.prefix(1).uppercased() + periodName.dropFirst())
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
                Text("\(spent.formatted(.currency(code: currencyCode))) of \(periodLimit.formatted(.currency(code: currencyCode))) \(isBill ? "paid" : "used")")
                Spacer()
                Label(schedule, systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Transfers change what's left, not the category's own limit.
            if transferred != 0 {
                Label("\(transferred.formatted(.currency(code: currencyCode).sign(strategy: .always()))) transferred \(transferred > 0 ? "in" : "out") \(periodName)",
                      systemImage: transferred > 0 ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                    .font(.caption)
                    .foregroundStyle(transferred > 0 ? .green : .orange)
            }
        }
        .padding(.vertical, 6)
        .animation(.snappy, value: amount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(abs(shownRemaining).formatted(.currency(code: currencyCode))) \(shownRemaining < 0 ? "over" : "left") \(periodName)\(isPreviewing ? " after this" : ""). \(spent.formatted(.currency(code: currencyCode))) of \(periodLimit.formatted(.currency(code: currencyCode))) \(isBill ? "paid" : "used")\(transferred == 0 ? "" : ", \(transferred.formatted(.currency(code: currencyCode).sign(strategy: .always()))) transferred"). \(schedule).")

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
                        if category.canPayAhead, let nextUnpaid = category.nextUnpaidPeriodsAhead {
                            Button("Pay \(category.title(of: category.period(after: nextUnpaid))) in Advance", systemImage: "forward.circle") {
                                withAnimation { periodsAhead = nextUnpaid }
                            }
                        }
                        Button("Add Another Expense", systemImage: "plus.circle") {
                            logsAnyway = true
                        }
                        Button("Transfer Funds", systemImage: "arrow.left.arrow.right") { isTransferring = true }
                    } footer: {
                        Text(category.canPayAhead
                             ? "Paying in advance counts toward that \(category.frequency == .biweekly ? "period" : "month") instead of this one. Transfer Funds moves unused money from another expense into \(category.name)."
                             : "Move unused money from another expense into \(category.name).")
                    }

                    ExpenseHistory(category: category)
                } else {
                    Section {
                        summary
                    } header: {
                        Label("\(category.name) · \(periodName)", systemImage: category.icon)
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
                        if category.canPayAhead {
                            let unit = category.frequency == .biweekly ? "period" : "month"
                            // Only periods between the start and end dates.
                            let choices = [0] + (1...max(12, periodsAhead)).filter {
                                $0 == periodsAhead || category.limit(for: category.period(after: $0)) > 0
                            }
                            Picker(isAhead ? "Starting" : "For", selection: $periodsAhead.animation()) {
                                ForEach(choices, id: \.self) { ahead in
                                    Text(ahead == 0 ? category.periodName.prefix(1).uppercased() + category.periodName.dropFirst()
                                         : category.title(of: category.period(after: ahead)))
                                        .tag(ahead)
                                }
                            }
                            if isAhead && coverablePeriods > 1 {
                                Stepper("Covers \(periods.count) \(unit)\(periods.count == 1 ? "" : "s")",
                                        value: $periodsCovered.animation(), in: 1...coverablePeriods)
                            }
                        }
                        Toggle(isAhead ? "Set Date Paid" : "Set Date", isOn: $picksDate.animation())
                        if picksDate {
                            DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                                .closesWhenPicked(date)
                        }
                    } footer: {
                        if isAhead && category.frequency == .once {
                            Text("Paid early: counts toward \(category.name) on \(category.title(of: period)) even though you pay it now.")
                        } else if isAhead {
                            Text("Paid in advance: counts toward \(category.title(of: periods)) instead of \(category.periodName)\(isBill ? ", and marks \(periods.count == 1 ? "that bill" : "those bills") as paid" : "")."
                                 + (periods.count > 1 ? " It's split in order, each \(category.frequency == .biweekly ? "period" : "month") getting what it needs." : ""))
                        } else if !picksDate {
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
            .navigationTitle(showsPaid ? category.name : isAhead ? "Pay in Advance" : "Add Expense")
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
                            let trimmedNote = note.trimmingCharacters(in: .whitespaces)
                            if isAhead {
                                let logs = category.payAhead(amount, for: periods, note: trimmedNote, date: picksDate ? date : nil, in: context)
                                // Each month's expense takes its share of the chosen incomes, in order.
                                var unused = fundingAmounts
                                for log in logs where linksExpenses {
                                    var needed = log.amount
                                    var share: [PersistentIdentifier: Decimal] = [:]
                                    for income in incomes where needed > 0 {
                                        let taken = min(unused[income.persistentModelID] ?? 0, needed)
                                        guard taken > 0 else { continue }
                                        share[income.persistentModelID] = taken
                                        unused[income.persistentModelID, default: 0] -= taken
                                        needed -= taken
                                    }
                                    log.setFundings(share, from: incomes, in: context)
                                }
                            } else {
                                let log = SpendLog(amount: amount, note: trimmedNote, date: picksDate ? date : nil, category: category)
                                context.insert(log)
                                if linksExpenses { log.setFundings(fundingAmounts, from: incomes, in: context) }
                            }
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
        // Paying ahead fills in what the chosen periods still need, unless the user typed their own amount.
        .onChange(of: [periodsAhead, periodsCovered], initial: true) {
            periodsCovered = min(periodsCovered, max(coverablePeriods, 1))
            guard amount == nil || amount == suggestedAmount else { return }
            let periods = (0..<periodsCovered).map { category.period(after: periodsAhead + $0) }
            let owed = periods[0].start > .now ? periods.reduce(Decimal(0)) { $0 + max(category.remaining(in: $1), 0) } : 0
            suggestedAmount = owed > 0 ? owed : nil
            amount = suggestedAmount
        }
    }
}
