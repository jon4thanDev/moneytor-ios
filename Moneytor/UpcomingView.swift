import SwiftUI
import SwiftData

/// Bills coming due and money expected in over the next 30 days, so nothing sneaks up on you.
struct UpcomingView: View {
    @Query(filter: #Predicate<BudgetCategory> { !$0.isArchived }, sort: \BudgetCategory.createdAt)
    private var categories: [BudgetCategory]
    @Query(sort: \ExpectedPayment.startDate) private var payments: [ExpectedPayment]
    @State private var payingCategory: BudgetCategory?
    @State private var searchText = ""

    private struct Item: Identifiable {
        let id = UUID()
        let date: Date
        let title: String
        let icon: String
        let amount: Decimal
        let isIncoming: Bool
        var note: String?
        /// The bill's category; nil for incoming payments.
        var category: BudgetCategory?
    }

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let horizon = calendar.date(byAdding: .day, value: 30, to: today) ?? today

        let bills: [Item] = categories.compactMap { category in
            guard category.frequency == .monthly, category.status == .active else { return nil }
            // Once the month's limit is fully logged, the bill counts as paid and next month's due date shows instead.
            let isPaid = category.limit > 0 && category.remainingThisPeriod <= 0
            let month = isPaid ? calendar.date(byAdding: .month, value: 1, to: today) ?? today : today
            guard let due = category.dueDate(inMonthOf: month), due <= horizon,
                  category.endDate.map({ calendar.startOfDay(for: due) <= calendar.startOfDay(for: $0) }) ?? true
            else { return nil }
            return Item(date: due, title: category.name, icon: category.icon,
                        amount: isPaid ? category.limit : category.remainingThisPeriod,
                        isIncoming: false, note: isPaid ? "This month is paid" : nil, category: category)
        }
        let incoming: [Item] = payments.flatMap { payment in
            payment.paymentDates
                .filter { calendar.startOfDay(for: $0) >= today && $0 <= horizon }
                .map { Item(date: $0, title: payment.name, icon: "arrow.down.circle.fill", amount: payment.amount, isIncoming: true) }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let items = (bills + incoming)
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted { $0.date < $1.date }
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let overdue = items.filter { calendar.startOfDay(for: $0.date) < today }
        let thisWeek = items.filter { (today...weekEnd).contains(calendar.startOfDay(for: $0.date)) }
        let later = items.filter { calendar.startOfDay(for: $0.date) > weekEnd }
        // Same bills as the tab badge and reminders, regardless of search.
        let dueBills = categories
            .compactMap { category in category.unpaidDueDate.map { (category: category, due: calendar.startOfDay(for: $0)) } }
            .filter { $0.due <= today }
            .sorted { $0.due < $1.due }

        NavigationStack {
            List {
                if !dueBills.isEmpty {
                    Section {
                        let bannerTint: Color = dueBills.contains { $0.due < today } ? .red : .orange
                        VStack(alignment: .leading, spacing: 12) {
                            Label(dueBills.count == 1 ? "1 bill needs paying" : "\(dueBills.count) bills need paying",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(bannerTint)
                            ForEach(dueBills, id: \.category.persistentModelID) { bill in
                                let daysLate = calendar.dateComponents([.day], from: bill.due, to: today).day ?? 0
                                let tint: Color = daysLate > 0 ? .red : .orange
                                HStack(spacing: 10) {
                                    Image(systemName: bill.category.icon)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(tint, in: RoundedRectangle(cornerRadius: 7))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bill.category.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(daysLate == 0 ? "Due today"
                                             : "Overdue since \(bill.due.formatted(.dateTime.month(.abbreviated).day())) · \(daysLate == 1 ? "1 day" : "\(daysLate) days") late")
                                            .font(.caption)
                                            .foregroundStyle(tint)
                                    }
                                    Spacer()
                                    Text(bill.category.remainingThisPeriod, format: .currency(code: currencyCode))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                    Button("Pay") { payingCategory = bill.category }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .tint(tint)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(bannerTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(bannerTint.opacity(0.3)))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    HStack(spacing: 12) {
                        SummaryStat(title: "Going Out", amount: bills.reduce(0) { $0 + $1.amount },
                                    icon: "arrow.up.circle.fill", tint: .red)
                        SummaryStat(title: "Coming In", amount: incoming.reduce(0) { $0 + $1.amount },
                                    icon: "arrow.down.circle.fill", tint: .green)
                    }
                } footer: {
                    Text("Next 30 days, including anything overdue.")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if items.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if items.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Coming Up", systemImage: "calendar")
                    } description: {
                        Text("Give a category a due date, or add an expected payment in the Income tab.")
                    }
                }
                if !overdue.isEmpty {
                    Section("Overdue") { timeline(overdue) }
                }
                if !thisWeek.isEmpty {
                    Section("Next 7 Days") { timeline(thisWeek) }
                }
                if !later.isEmpty {
                    Section("Later This Month") { timeline(later) }
                }
            }
            .navigationTitle("Upcoming")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search bills and payments")
            .sheet(item: $payingCategory) { PayBillSheet(category: $0) }
        }
    }

    /// One timeline row per day, however many bills and payments land on it.
    private func timeline(_ items: [Item]) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }.sorted { $0.key < $1.key }

        return ForEach(Array(days.enumerated()), id: \.element.key) { index, group in
            let dayItems = group.value
            let net = dayItems.reduce(0) { $0 + ($1.isIncoming ? 1 : -1) * $1.amount }
            TimelineDayRow(day: group.key, isFirst: index == 0, isLast: index == days.count - 1) {
                if dayItems.count > 1 {
                    Text(net, format: .currency(code: currencyCode))
                        .foregroundStyle(net > 0 ? .green : .primary)
                }
            } content: {
                ForEach(dayItems) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(item.isIncoming ? Color.green : Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            if let note = item.note {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text((item.isIncoming ? 1 : -1) * item.amount, format: .currency(code: currencyCode))
                                .monospacedDigit()
                                .foregroundStyle(item.isIncoming ? .green : dayItems.count > 1 ? .secondary : .primary)
                            if group.key < today, let category = item.category {
                                Button("Pay") { payingCategory = category }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Logs an overdue bill as paid, noting which income the money came from.
private struct PayBillSheet: View {
    let category: BudgetCategory

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \IncomeSource.createdAt) private var incomes: [IncomeSource]
    @State private var amount: Decimal?
    /// Nil means the money came from somewhere else.
    @State private var paidFrom: String?
    @State private var otherSource = ""
    @AppStorage("linksExpensesToIncome") private var linksExpenses = false
    @State private var fundingAmounts: [PersistentIdentifier: Decimal] = [:]

    var body: some View {
        let salary = incomes.first { $0.name.localizedCaseInsensitiveContains("salary") }?.name ?? "Salary"
        let sources = [salary] + incomes.map(\.name).filter { $0 != salary }

        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(Locale.current.currencySymbol ?? "$")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        CalculatorField(
                            value: $amount,
                            font: .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .largeTitle).pointSize, weight: .bold)
                        )
                    }
                } header: {
                    Label(category.name, systemImage: category.icon)
                }

                if linksExpenses {
                    FundingPicker(total: amount ?? 0, amounts: $fundingAmounts)
                } else {
                    Section {
                        Picker("Paid From", selection: $paidFrom) {
                            ForEach(sources, id: \.self) { source in
                                HStack {
                                    Text(source)
                                    if source == salary {
                                        Text("Recommended")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .tag(Optional(source))
                            }
                            Text("Somewhere Else").tag(String?.none)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        if paidFrom == nil {
                            TextField("Where from? (optional)", text: $otherSource)
                                .textInputAutocapitalization(.words)
                        }
                    } header: {
                        Text("Paid From")
                    } footer: {
                        Text("Optional. Pick Somewhere Else if the money didn't come from your income.")
                    }
                }
            }
            .navigationTitle("Pay Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pay") {
                        guard let amount else { return }
                        let log = SpendLog(amount: amount, note: "", date: nil, category: category)
                        context.insert(log)
                        if linksExpenses {
                            log.setFundings(fundingAmounts, from: incomes, in: context)
                        } else if let income = incomes.first(where: { $0.name == paidFrom }) {
                            // Linking a real income now means nothing to fill in if linking is turned on later.
                            log.setFundings([income.persistentModelID: amount], from: [income], in: context)
                        } else {
                            let trimmedOther = otherSource.trimmingCharacters(in: .whitespaces)
                            log.paidFrom = paidFrom ?? (trimmedOther.isEmpty ? nil : trimmedOther)
                        }
                        dismiss()
                    }
                    .disabled(amount == nil || amount! <= 0
                              || (linksExpenses && fundingAmounts.values.reduce(0, +) != amount))
                }
            }
            .onAppear {
                amount = max(category.remainingThisPeriod, 0)
                paidFrom = salary
            }
        }
        .presentationDetents([.medium, .large])
    }
}
