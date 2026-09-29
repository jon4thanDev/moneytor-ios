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
        // Coming payment dates, one timeline entry per day however many payments land on it.
        let paymentDays = Dictionary(grouping: sortedPayments.flatMap { payment in
            let dates = payment.paymentDates
            return dates.indices
                .filter { Calendar.current.startOfDay(for: dates[$0]) >= today }
                .map { PaymentOnDay(day: Calendar.current.startOfDay(for: dates[$0]), payment: payment, number: $0 + 1, count: dates.count) }
        }, by: \.day).sorted { $0.key < $1.key }
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
                                    Text(entries.reduce(0) { $0 + $1.payment.amount }, format: .currency(code: currencyCode))
                                        .foregroundStyle(.green)
                                }
                            } content: {
                                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                                    Button { editingPayment = entry.payment } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(entry.payment.name)
                                                if entry.count > 1 {
                                                    Text("Payment \(entry.number) of \(entry.count)")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Text(entry.payment.amount, format: .currency(code: currencyCode))
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
                            Text("Showing the next \(shownDays.count) payment days.")
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
                    Text("Money someone owes you or other temporary income, paid once or for a set time. Not counted in your monthly total.")
                }
            }
            .navigationTitle("Income")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search income")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { AssistantRouter.shared.isShowing = true } label: { AIIcon() }
                        .accessibilityLabel("Assistant")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("Add", systemImage: "plus") {
                        Button("Monthly Income", systemImage: "banknote") { isAdding = true }
                        Button("Expected Payment", systemImage: "calendar.badge.plus") { isAddingPayment = true }
                    }
                }
            }
            .sheet(isPresented: $isAdding) { IncomeEditor(income: nil) }
            .sheet(item: $editing) { IncomeEditor(income: $0) }
            .sheet(isPresented: $isAddingPayment) { ExpectedPaymentEditor(payment: nil) }
            .sheet(item: $editingPayment) { ExpectedPaymentEditor(payment: $0) }
        }
    }
}

private struct PaymentOnDay {
    let day: Date
    let payment: ExpectedPayment
    /// Which payment this is, like 2 of 6.
    let number: Int
    let count: Int
}

private struct IncomeEditor: View {
    let income: IncomeSource?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount: Decimal?

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
                        if let income {
                            income.name = trimmedName
                            income.amount = amount
                        } else {
                            context.insert(IncomeSource(name: trimmedName, amount: amount))
                        }
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || amount == nil || amount! < 0)
                }
            }
            .onAppear {
                guard let income else { return }
                name = income.name
                amount = income.amount
            }
        }
        .presentationDetents([.medium])
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

private struct ExpectedPaymentEditor: View {
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
                Section("From") {
                    TextField("Who or what (e.g. Juan – loan)", text: $name)
                        .textInputAutocapitalization(.words)
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
                        ForEach(Frequency.allCases, id: \.self) { Text($0.rawValue) }
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
