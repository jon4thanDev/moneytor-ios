import SwiftUI
import SwiftData

enum IncomeSort: String, CaseIterable {
    case name = "Name"
    case amount = "Amount"
}

struct IncomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \IncomeSource.createdAt) private var incomes: [IncomeSource]
    @Query(sort: \ExpectedPayment.startDate) private var payments: [ExpectedPayment]

    @State private var isAdding = false
    @State private var editing: IncomeSource?
    @State private var isAddingPayment = false
    @State private var editingPayment: ExpectedPayment?
    @State private var searchText = ""
    @AppStorage("incomeSort") private var sort: IncomeSort = .name
    @AppStorage("linksExpensesToIncome") private var linksExpenses = false

    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let sortedIncomes = incomes.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted {
            sort == .name ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.amount > $1.amount
        }
        let sortedPayments = payments.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted {
            sort == .name ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.amount > $1.amount
        }
        let today = Calendar.current.startOfDay(for: .now)
        let payDayHorizon = Calendar.current.date(byAdding: .month, value: 3, to: today) ?? today
        // Money coming in from pay days and expected payments, one timeline entry per day however much lands on it.
        let incomeArrivals = sortedIncomes.flatMap { income in
            income.payDates(through: payDayHorizon).map {
                IncomeOnDay(day: Calendar.current.startOfDay(for: $0), name: income.name, amount: income.amount(inMonthOf: $0),
                            detail: "Monthly income", income: income)
            }
        }
        let paymentArrivals = sortedPayments.flatMap { payment in
            let dates = payment.paymentDates
            return dates.indices
                .filter { Calendar.current.startOfDay(for: dates[$0]) >= today }
                .map {
                    IncomeOnDay(day: Calendar.current.startOfDay(for: dates[$0]), name: payment.name, amount: payment.amount,
                                detail: dates.count > 1 ? "Payment \($0 + 1) of \(dates.count)" : nil, payment: payment)
                }
        }
        let paymentDays = Dictionary(grouping: incomeArrivals + paymentArrivals, by: \.day).sorted { $0.key < $1.key }
        let shownDays = Array(paymentDays.prefix(8))
        let sortMenu = Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(IncomeSort.allCases, id: \.self) { Text($0.rawValue) }
            }
        } label: {
            Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                .font(.caption)
        }
        .textCase(nil)

        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Total Income", systemImage: "sum")
                            .font(.headline)
                        Spacer()
                        Text(incomes.reduce(0) { $0 + $1.amount }, format: .currency(code: currencyCode))
                            .font(.title3.bold())
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    if !query.isEmpty && sortedIncomes.isEmpty && sortedPayments.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    if incomes.isEmpty {
                        ContentUnavailableView {
                            Label("No Income Yet", systemImage: "banknote")
                        } description: {
                            Text("Add your salary, side hustles, or any other income.")
                        } actions: {
                            Button("Add Income") { isAdding = true }
                        }
                    }
                    ForEach(sortedIncomes) { income in
                        Button {
                            editing = income
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(income.name)
                                    if let payDay = income.payDay, let next = income.payDates(through: payDayHorizon).first {
                                        let isToday = Calendar.current.isDateInToday(next)
                                        Text((payDay == BudgetCategory.monthEnd ? "Paid at month end" : "Paid on day \(payDay)")
                                             + " · " + (isToday ? "today" : "next \(next.formatted(.dateTime.month(.abbreviated).day()))"))
                                            .font(.caption)
                                            .foregroundStyle(isToday ? .green : .secondary)
                                    }
                                    if linksExpenses {
                                        let left = income.remainingThisMonth
                                        Text("\(left.formatted(.currency(code: currencyCode))) left this month")
                                            .font(.caption)
                                            .foregroundStyle(left < 0 ? .red : .secondary)
                                    }
                                }
                                Spacer()
                                Text(income.amount, format: .currency(code: currencyCode))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        offsets.forEach { context.delete(sortedIncomes[$0]) }
                    }
                } header: {
                    HStack {
                        Text("Monthly Income Sources")
                        Spacer()
                        sortMenu
                    }
                }

                if !shownDays.isEmpty {
                    Section {
                        ForEach(Array(shownDays.enumerated()), id: \.element.key) { index, group in
                            let entries = group.value
                            TimelineDayRow(day: group.key, isFirst: index == 0, isLast: index == shownDays.count - 1, tint: .green) {
                                if entries.count > 1 {
                                    Text(entries.reduce(0) { $0 + $1.amount }, format: .currency(code: currencyCode))
                                        .foregroundStyle(.green)
                                }
                            } content: {
                                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                                    Button {
                                        if let payment = entry.payment { editingPayment = payment } else { editing = entry.income }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(entry.name)
                                                if let detail = entry.detail {
                                                    Text(detail)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Text(entry.amount, format: .currency(code: currencyCode))
                                                .monospacedDigit()
                                                .foregroundStyle(entries.count > 1 ? .secondary : Color.green)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } header: {
                        Text("Coming Up")
                    } footer: {
                        if paymentDays.count > shownDays.count {
                            Text("Showing the next \(shownDays.count) days with money coming in.")
                        }
                    }
                }

                Section {
                    if payments.isEmpty {
                        Button("Add Expected Payment", systemImage: "plus.circle") { isAddingPayment = true }
                    }
                    ForEach(sortedPayments) { payment in
                        Button {
                            editingPayment = payment
                        } label: {
                            ExpectedPaymentRow(payment: payment)
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        offsets.forEach { context.delete(sortedPayments[$0]) }
                    }
                } header: {
                    HStack {
                        Text("Expected Payments")
                        Spacer()
                        if !payments.isEmpty { sortMenu }
                    }
                } footer: {
                    Text("For money that comes in only a few times and then stops, like a friend paying back a loan in 3 installments, a one-time bonus, or a refund. Unlike your salary, it isn't counted in your monthly income.")
                }
            }
            .navigationTitle("Income")
            .collapsesTabBarOnScroll()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search income")
            // From iOS 26 the add button sits beside the tab bar instead (see RootView).
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                if #available(iOS 26, *) {
                } else {
                    Menu {
                        Button("Monthly Income", systemImage: "banknote") { isAdding = true }
                        Button("Expected Payment", systemImage: "calendar.badge.plus") { isAddingPayment = true }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    }
                    .accessibilityLabel("Add Income")
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { AssistantRouter.shared.isShowing = true } label: { AIIcon() }
                        .accessibilityLabel("Assistant")
                }
            }
            .sheet(isPresented: $isAdding) { IncomeEditor(income: nil) }
            .sheet(item: $editing) { IncomeEditor(income: $0) }
            .sheet(isPresented: $isAddingPayment) { ExpectedPaymentEditor(payment: nil) }
            .sheet(item: $editingPayment) { ExpectedPaymentEditor(payment: $0) }
        }
    }
}

/// Money arriving on one day: a monthly income's pay day or one of an expected payment's dates.
private struct IncomeOnDay {
    let day: Date
    let name: String
    let amount: Decimal
    /// Like "Monthly income" or "Payment 2 of 6".
    let detail: String?
    var income: IncomeSource?
    var payment: ExpectedPayment?
}

struct IncomeEditor: View {
    let income: IncomeSource?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount: Decimal?
    @State private var hasPayDay = false
    /// False once the user cancels a change scheduled for a later month; cleared on Save.
    @State private var keepsScheduledChange = true
    @State private var payDay = 15

    var body: some View {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        NavigationStack {
            Form {
                Section("Source") {
                    TextField("Name (e.g. Salary)", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section("Monthly Amount") {
                    HStack {
                        Text(Locale.current.currencySymbol ?? "$")
                            .foregroundStyle(.secondary)
                        MoneyField(value: $amount)
                    }
                    if keepsScheduledChange, let income, let newAmount = income.scheduledAmount, let month = income.scheduledAmountMonth {
                        ScheduledChangeRow(amount: newAmount, month: month) { keepsScheduledChange = false }
                    }
                }
                Section {
                    Toggle("Has a Pay Day", isOn: $hasPayDay.animation())
                    if hasPayDay {
                        Picker("Paid Every Month On", selection: $payDay) {
                            ForEach(1...31, id: \.self) { Text("Day \($0)") }
                            Text("Month End").tag(BudgetCategory.monthEnd)
                        }
                    }
                } footer: {
                    Text(hasPayDay
                         ? "Shows in Upcoming and Coming Up so you know when it arrives. In shorter months, days past the end fall on the last day."
                         : "Optional. Set the day it usually arrives to see it coming in Upcoming.")
                }
                if let income {
                    Section {
                        Button("Delete Income", role: .destructive) {
                            context.delete(income)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(income == nil ? "New Income" : "Edit Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount else { return }
                        let target = income ?? IncomeSource(name: trimmedName, amount: amount)
                        target.name = trimmedName
                        target.amount = amount
                        target.payDay = hasPayDay ? payDay : nil
                        if !keepsScheduledChange {
                            target.scheduledAmount = nil
                            target.scheduledAmountMonth = nil
                        }
                        if income == nil { context.insert(target) }
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || amount == nil || amount! < 0)
                }
            }
            .onAppear {
                guard let income else { return }
                name = income.name
                amount = income.amount
                hasPayDay = income.payDay != nil
                payDay = income.payDay ?? payDay
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A new amount set to take over in a later month, like "₱6,000 from November", with a way to cancel it.
struct ScheduledChangeRow: View {
    let amount: Decimal
    let month: Date
    let onCancel: () -> Void

    var body: some View {
        let isThisYear = Calendar.current.isDate(month, equalTo: .now, toGranularity: .year)
        HStack {
            Label {
                Text("Changes to \(amount.formatted(.currency(code: currencyCode))) from \(month.formatted(isThisYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year()))")
            } icon: {
                Image(systemName: "calendar.badge.clock").foregroundStyle(Color.accentColor)
            }
            .font(.subheadline)
            Spacer()
            Button("Cancel Change", role: .destructive, action: onCancel)
                .font(.subheadline)
                .buttonStyle(.borderless)
        }
    }
}

private struct ExpectedPaymentRow: View {
    let payment: ExpectedPayment

    var body: some View {
        let dates = payment.paymentDates
        let isFinished = (dates.last ?? payment.startDate) < Calendar.current.startOfDay(for: .now)
        let schedule = payment.frequency == .once
            ? "Once · \(payment.startDate.formatted(.dateTime.month(.abbreviated).day().year()))"
            : "\(payment.frequency.rawValue) · \(payment.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(payment.endDate.formatted(.dateTime.month(.abbreviated).day().year()))"

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.name)
                Text(isFinished ? "\(schedule) · Finished" : schedule)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(payment.amount, format: .currency(code: currencyCode))
                    .monospacedDigit()
                    .foregroundStyle(isFinished ? Color.secondary : Color.green)
                if dates.count > 1 {
                    Text("\(dates.count)× · \((payment.amount * Decimal(dates.count)).formatted(.currency(code: currencyCode))) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ExpectedPaymentEditor: View {
    let payment: ExpectedPayment?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount: Decimal?
    @State private var frequency: Frequency = .once
    @State private var startDate = Date.now
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 2, to: .now) ?? .now

    var body: some View {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let count = ExpectedPayment.paymentDates(frequency: frequency, start: startDate, end: endDate).count

        NavigationStack {
            Form {
                Section {
                    TextField("Who or what (e.g. Juan – loan)", text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("From")
                } footer: {
                    if payment == nil {
                        Text("Use this for money that comes in a set number of times and then ends, like a friend paying you back monthly for 3 months. For money that keeps coming every month, like your salary, add a Monthly Income instead.")
                    }
                }

                Section("Amount per Payment") {
                    HStack {
                        Text(Locale.current.currencySymbol ?? "$")
                            .foregroundStyle(.secondary)
                        MoneyField(value: $amount)
                    }
                }

                Section {
                    Picker("Repeats", selection: $frequency.animation()) {
                        ForEach(Frequency.allCases, id: \.self) { Text($0 == .biweekly ? "2 Weeks" : $0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker(frequency == .once ? "Date" : "Starts", selection: $startDate, displayedComponents: .date)
                        .closesWhenPicked(startDate)
                    if frequency != .once {
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                            .closesWhenPicked(endDate)
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    if frequency != .once {
                        let total = (amount ?? 0) * Decimal(count)
                        Text("\(count) payment\(count == 1 ? "" : "s") · \(total.formatted(.currency(code: currencyCode))) total")
                    }
                }

                if let payment {
                    Section {
                        Button("Delete Payment", role: .destructive) {
                            context.delete(payment)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(payment == nil ? "New Expected Payment" : "Edit Expected Payment")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: startDate) { _, newStart in
                if endDate < newStart { endDate = newStart }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount else { return }
                        let end = frequency == .once ? startDate : endDate
                        if let payment {
                            payment.name = trimmedName
                            payment.amount = amount
                            payment.frequency = frequency
                            payment.startDate = startDate
                            payment.endDate = end
                        } else {
                            context.insert(ExpectedPayment(name: trimmedName, amount: amount, frequency: frequency, startDate: startDate, endDate: end))
                        }
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || amount == nil || amount! <= 0)
                }
            }
            .onAppear {
                guard let payment else { return }
                name = payment.name
                amount = payment.amount
                frequency = payment.frequency
                startDate = payment.startDate
                endDate = payment.frequency == .once
                    ? Calendar.current.date(byAdding: .month, value: 2, to: payment.startDate) ?? payment.startDate
                    : payment.endDate
            }
        }
    }
}
