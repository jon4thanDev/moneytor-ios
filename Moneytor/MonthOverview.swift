import SwiftUI
import SwiftData

/// Steps through months in Expenses, from the first month with anything in it up to a year ahead.
struct MonthSwitcher: View {
    @Binding var month: Date
    let first: Date
    let last: Date

    var body: some View {
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let offset = calendar.dateComponents([.month], from: thisMonth, to: month).month ?? 0
        let months = (0...max(calendar.dateComponents([.month], from: first, to: last).month ?? 0, 0))
            .compactMap { calendar.date(byAdding: .month, value: $0, to: first) }
        let years = Dictionary(grouping: months) { calendar.component(.year, from: $0) }
        let relative = switch offset {
        case 0: "This Month"
        case -1: "Last Month"
        case 1: "Next Month"
        case ..<0: "\(-offset) months ago"
        default: "In \(offset) months"
        }

        HStack {
            stepButton(by: -1, systemImage: "chevron.left", label: "Previous Month")
                .disabled(month <= first)
            Spacer()
            Menu {
                if offset != 0 {
                    Button("Back to This Month", systemImage: "calendar") {
                        withAnimation { month = thisMonth }
                    }
                }
                Picker("Month", selection: $month.animation()) {
                    ForEach(years.keys.sorted(), id: \.self) { year in
                        Section(String(year)) {
                            ForEach(years[year] ?? [], id: \.self) { Text($0.formatted(.dateTime.month(.wide))).tag($0) }
                        }
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(month.formatted(.dateTime.month(.wide).year()))
                            .font(.headline)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    Text(relative)
                        .font(.caption)
                        .foregroundStyle(offset == 0 ? Color.secondary : Color.accentColor)
                }
                .contentTransition(.numericText())
            }
            Spacer()
            stepButton(by: 1, systemImage: "chevron.right", label: "Next Month")
                .disabled(month >= last)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private func stepButton(by months: Int, systemImage: String, label: String) -> some View {
        Button {
            guard let next = Calendar.current.date(byAdding: .month, value: months, to: month) else { return }
            withAnimation { month = next }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
        }
        .accessibilityLabel(label)
    }
}

/// Expenses for a month other than this one: what was spent in a past month, or what's planned for a coming one.
struct MonthOverview: View {
    /// The first moment of the month shown.
    let month: Date
    /// Every category, including archived ones, whose spending still belongs to past months.
    let categories: [BudgetCategory]
    let logs: [SpendLog]
    let incomes: [IncomeSource]
    let payments: [ExpectedPayment]
    let query: String
    @State private var shownLogCount: Int?

    var body: some View {
        Group {
            if month < Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now {
                past
            } else {
                coming
            }
        }
        .onChange(of: month) { shownLogCount = nil }
    }

    private var monthName: String {
        month.formatted(Calendar.current.isDate(month, equalTo: .now, toGranularity: .year)
            ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
    }

    private func matches(_ text: String) -> Bool {
        query.isEmpty || text.localizedCaseInsensitiveContains(query)
    }

    // MARK: Past months

    @ViewBuilder private var past: some View {
        let calendar = Calendar.current
        let monthLogs = logs
            .filter { calendar.isDate($0.effectiveDate, equalTo: month, toGranularity: .month) }
            .sorted { $0.effectiveDate > $1.effectiveDate }
        // Against limits, a payment made in advance counts in the month it was for.
        let countedLogs = logs.filter { calendar.isDate($0.countedDate, equalTo: month, toGranularity: .month) }
        let rows = categories.compactMap { category -> (category: BudgetCategory, spent: Decimal, limit: Decimal)? in
            let spent = countedLogs.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
            // Archived categories don't record when they stopped, so they only count in months they were used.
            let limit = category.isArchived && spent == 0 ? 0 : category.limit(inMonthOf: month)
            return spent == 0 && limit == 0 ? nil : (category, spent, limit)
        }
        let spent = countedLogs.reduce(0) { $0 + $1.amount }
        let planned = rows.reduce(0) { $0 + $1.limit }
        let shownRows = rows.filter { matches($0.category.name) }.sorted { $0.spent > $1.spent }
        let shownLogs = monthLogs.filter { matches($0.note) || matches($0.category?.name ?? "") }

        if rows.isEmpty && monthLogs.isEmpty {
            ContentUnavailableView("Nothing in \(monthName)", systemImage: "calendar",
                                   description: Text("You had no limits or expenses that month."))
        } else {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Spent in \(monthName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(spent, format: .currency(code: currencyCode))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(planned > 0 && spent > planned ? .red : .primary)
                    if planned > 0 {
                        let isOver = spent > planned
                        ProgressView(value: min(NSDecimalNumber(decimal: spent / planned).doubleValue, 1))
                            .tint(isOver ? .red : .green)
                        Text("\(abs(planned - spent).formatted(.currency(code: currencyCode))) \(isOver ? "over" : "under") the \(planned.formatted(.currency(code: currencyCode))) you planned")
                            .font(.caption)
                            .foregroundStyle(isOver ? .red : .secondary)
                    }
                    Text(monthLogs.count == 1 ? "1 expense" : "\(monthLogs.count) expenses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if !shownRows.isEmpty {
                Section {
                    ForEach(shownRows, id: \.category.persistentModelID) { row in
                        let isOver = row.limit > 0 && row.spent > row.limit
                        HStack(spacing: 12) {
                            IconTile(icon: row.category.icon)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(row.category.name)
                                    Spacer()
                                    Text(row.spent, format: .currency(code: currencyCode))
                                        .monospacedDigit()
                                        .bold()
                                        .foregroundStyle(isOver ? .red : .primary)
                                }
                                if row.limit > 0 {
                                    ProgressView(value: min(NSDecimalNumber(decimal: row.spent / row.limit).doubleValue, 1))
                                        .tint(isOver ? .red : .accentColor)
                                    Text("of \(row.limit.formatted(.currency(code: currencyCode))) limit"
                                         + (isOver ? " · \((row.spent - row.limit).formatted(.currency(code: currencyCode))) over" : ""))
                                        .font(.caption)
                                        .foregroundStyle(isOver ? .red : .secondary)
                                } else {
                                    Text("No limit that month")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("By Category")
                } footer: {
                    Text("Limits show their current amounts.")
                }
            }

            Section("\(monthName) Logs") {
                if shownLogs.isEmpty {
                    Text(query.isEmpty ? "No expenses in \(monthName)." : "No matching expenses.")
                        .foregroundStyle(.secondary)
                } else {
                    let count = query.isEmpty ? min(shownLogCount ?? LoadMoreButton.pageSize, shownLogs.count) : shownLogs.count
                    ForEach(shownLogs.prefix(count)) { LogRow(log: $0) }
                    if query.isEmpty {
                        LoadMoreButton(dates: shownLogs.map(\.effectiveDate),
                                       shown: Binding(get: { shownLogCount ?? LoadMoreButton.pageSize }, set: { shownLogCount = $0 }))
                    }
                }
            }
        }
    }

    // MARK: Coming months

    @ViewBuilder private var coming: some View {
        let calendar = Calendar.current
        let shortDate = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        let planned = categories
            .filter { !$0.isArchived }
            .map { (category: $0, amount: $0.limit(inMonthOf: month)) }
            .filter { $0.amount > 0 }
        let monthInterval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 0)
        let bills = planned
            .flatMap { row in
                let unpaid = Set(row.category.unpaidDues(until: monthInterval.end).map(\.date))
                return row.category.dueDates(in: monthInterval).map {
                    (category: row.category, due: $0, amount: row.category.limitAmount(inMonthOf: $0), isPaid: !unpaid.contains($0))
                }
            }
            .sorted { $0.due < $1.due }
        let paidAhead = bills.filter(\.isPaid).reduce(0) { $0 + $1.amount }
        let billIDs = Set(bills.map(\.category.persistentModelID))
        let limits = planned.filter { !billIDs.contains($0.category.persistentModelID) }.sorted { $0.amount > $1.amount }
        let income = incomes.map { income in
            (name: income.name, icon: "banknote.fill", amount: income.amount(inMonthOf: month),
             detail: income.payDay.flatMap { monthDay($0, inMonthOf: month) }.map { "Paid \($0.formatted(shortDate))" } ?? "Monthly income")
        } + payments.flatMap { payment in
            let dates = payment.paymentDates
            return dates.enumerated()
                .filter { calendar.isDate($0.element, equalTo: month, toGranularity: .month) }
                .map { (name: payment.name, icon: "arrow.down.circle.fill", amount: payment.amount,
                        detail: "Payment \($0.offset + 1) of \(dates.count) · \($0.element.formatted(shortDate))") }
        }
        let totalPlanned = planned.reduce(0) { $0 + $1.amount }
        let totalIncome = income.reduce(0) { $0 + $1.amount }
        let leftOver = totalIncome - totalPlanned

        if planned.isEmpty && income.isEmpty {
            ContentUnavailableView("Nothing planned for \(monthName)", systemImage: "calendar",
                                   description: Text("Limits and income that carry into \(monthName) will show here."))
        } else {
            Section {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Planned for \(monthName)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(totalPlanned, format: .currency(code: currencyCode))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("\(planned.count) \(planned.count == 1 ? "category" : "categories") · \(bills.count) \(bills.count == 1 ? "bill" : "bills") due")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if paidAhead > 0 {
                            Label("\(paidAhead.formatted(.currency(code: currencyCode))) already paid in advance", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                    HStack(spacing: 12) {
                        SummaryStat(title: "Expected Income", amount: totalIncome, icon: "arrow.down.circle.fill", tint: .green)
                        SummaryStat(title: leftOver < 0 ? "Short By" : "Left Over", amount: abs(leftOver),
                                    icon: leftOver < 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                                    tint: leftOver < 0 ? .orange : .accentColor)
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            let shownBills = bills.filter { matches($0.category.name) }
            if !shownBills.isEmpty {
                Section("Bills Due") {
                    ForEach(Array(shownBills.enumerated()), id: \.offset) { _, bill in
                        HStack(spacing: 12) {
                            IconTile(icon: bill.category.icon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bill.category.name)
                                Text("Due \(bill.due.formatted(shortDate))" + (bill.isPaid ? " · Paid in advance" : ""))
                                    .font(.caption)
                                    .foregroundStyle(bill.isPaid ? .green : .secondary)
                            }
                            Spacer()
                            Text(bill.amount, format: .currency(code: currencyCode))
                                .monospacedDigit()
                                .strikethrough(bill.isPaid)
                                .foregroundStyle(bill.isPaid ? .secondary : .primary)
                        }
                    }
                }
            }

            let shownLimits = limits.filter { matches($0.category.name) }
            if !shownLimits.isEmpty {
                Section("Spending Limits") {
                    ForEach(shownLimits, id: \.category.persistentModelID) { row in
                        let category = row.category
                        let each = category.limitAmount(inMonthOf: month).formatted(.currency(code: currencyCode))
                        let schedule = switch category.frequency {
                        case .daily: "\(each) a day"
                        case .weekly: "\(each) a week"
                        case .biweekly: "\(each) every 2 weeks"
                        case .monthly: "Monthly"
                        case .once: "Once · \(category.starts.formatted(shortDate))"
                        }
                        HStack(spacing: 12) {
                            IconTile(icon: category.icon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                Text(schedule)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(row.amount, format: .currency(code: currencyCode))
                                .monospacedDigit()
                        }
                    }
                }
            }

            let shownIncome = income.filter { matches($0.name) }
            Section {
                ForEach(Array(shownIncome.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 12) {
                        IconTile(icon: item.icon, tint: .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.amount, format: .currency(code: currencyCode).sign(strategy: .always()))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                if !shownIncome.isEmpty { Text("Expected Income") }
            } footer: {
                Text("Based on your current limits and income, so any change you make shows up here.")
            }
        }
    }
}

private struct IconTile: View {
    let icon: String
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: icon)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(tint, in: RoundedRectangle(cornerRadius: 9))
    }
}
