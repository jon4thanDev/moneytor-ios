import SwiftUI
import SwiftData

enum BudgetMode: String, CaseIterable {
    case log = "Log Expenses"
    case set = "Set Limits"
}

enum CategorySort: String, CaseIterable {
    case name = "Name"
    case dueDate = "Due Date"
}

struct BudgetView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<BudgetCategory> { !$0.isArchived }, sort: \BudgetCategory.createdAt)
    private var categories: [BudgetCategory]
    @Query private var incomes: [IncomeSource]
    @Query private var allLogs: [SpendLog]

    @State private var mode: BudgetMode = .log
    @State private var searchText = ""
    @AppStorage("categorySort") private var sort: CategorySort = .name
    @AppStorage("linksExpensesToIncome") private var linksExpenses = false
    /// The month ("2026-09") the budget was last set up for.
    @AppStorage("budgetMonth") private var budgetMonth = ""
    @State private var isLinkingExpenses = false
    @State private var relinkingLog: SpendLog?
    @State private var isShowingNewMonth = false
    @State private var newMonthChoice: NewMonthChoice?
    @State private var isAddingCategory = false
    @State private var editingCategory: BudgetCategory?
    @State private var loggingCategory: BudgetCategory?

    var body: some View {
        let logsThisMonth = allLogs
            .filter { Calendar.current.isDate($0.effectiveDate, equalTo: .now, toGranularity: .month) }
            .sorted { $0.effectiveDate > $1.effectiveDate }
        let unlinkedCount = linksExpenses ? logsThisMonth.filter { !$0.isLinked }.count : 0
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let shownLogs = query.isEmpty ? logsThisMonth : logsThisMonth.filter {
            $0.note.localizedCaseInsensitiveContains(query) || ($0.category?.name.localizedCaseInsensitiveContains(query) ?? false)
        }
        let sortedCategories = categories.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { a, b in
            switch sort {
            case .name:
                a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .dueDate:
                // Categories without a due date go last, alphabetically.
                (a.dueDay ?? .max, a.name.lowercased()) < (b.dueDay ?? .max, b.name.lowercased())
            }
        }
        // Limits that haven't started or have ended can't take new spending.
        let listedCategories = mode == .log ? sortedCategories.filter { $0.status == .active } : sortedCategories
        // In Log Spending, limits that are fully used move below the ones still to pay.
        let isComplete = { (category: BudgetCategory) in category.limit > 0 && category.remainingThisPeriod <= 0 }
        let pendingCategories = listedCategories.filter { !isComplete($0) }
        let completedCategories = mode == .log ? listedCategories.filter(isComplete) : []
        let topCategories = mode == .log ? pendingCategories : listedCategories

        NavigationStack {
            List {
                Section {
                    SummaryCard(
                        totalIncome: incomes.reduce(0) { $0 + $1.amount },
                        totalLimit: categories.reduce(0) { $0 + $1.limitThisMonth },
                        remaining: categories.reduce(0) { $0 + $1.remainingThisMonth }
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if unlinkedCount > 0 {
                    Section {
                        Button {
                            isLinkingExpenses = true
                        } label: {
                            Label("\(unlinkedCount) expense\(unlinkedCount == 1 ? "" : "s") need\(unlinkedCount == 1 ? "s" : "") an income",
                                  systemImage: "exclamationmark.triangle.fill")
                        }
                        .tint(.orange)
                    }
                }

                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(BudgetMode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    if categories.isEmpty {
                        ContentUnavailableView {
                            Label("No Categories", systemImage: "square.grid.2x2")
                        } description: {
                            Text("Add a category and give it an expense limit.")
                        } actions: {
                            Button("Add Category") { isAddingCategory = true }
                        }
                    }
                    if !query.isEmpty && topCategories.isEmpty && completedCategories.isEmpty && shownLogs.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    if query.isEmpty && mode == .log && pendingCategories.isEmpty && !completedCategories.isEmpty {
                        Label("Everything is complete for now.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    ForEach(topCategories) { category in
                        Button {
                            if mode == .set {
                                editingCategory = category
                            } else {
                                loggingCategory = category
                            }
                        } label: {
                            CategoryRow(category: category, mode: mode)
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        offsets.forEach { context.delete(topCategories[$0]) }
                    }
                    .deleteDisabled(mode == .log)
                } header: {
                    HStack {
                        Text(mode == .set ? "Expense Limits" : "Tap a category to add an expense")
                        Spacer()
                        Menu {
                            Picker("Sort By", selection: $sort) {
                                ForEach(CategorySort.allCases, id: \.self) { Text($0.rawValue) }
                            }
                        } label: {
                            Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                                .font(.caption)
                        }
                        .textCase(nil)
                    }
                }

                if mode == .log && !completedCategories.isEmpty {
                    Section("Complete") {
                        ForEach(completedCategories) { category in
                            Button {
                                loggingCategory = category
                            } label: {
                                CategoryRow(category: category, mode: mode)
                            }
                            .tint(.primary)
                        }
                    }
                }

                if mode == .log && !shownLogs.isEmpty {
                    Section(Date.now.formatted(.dateTime.month(.wide)) + " Logs") {
                        ForEach(shownLogs) { log in
                            if linksExpenses {
                                Button { relinkingLog = log } label: { LogRow(log: log) }
                                    .tint(.primary)
                            } else {
                                LogRow(log: log)
                            }
                        }
                        .onDelete { offsets in
                            offsets.forEach { context.delete(shownLogs[$0]) }
                        }
                    }
                }
            }
            .navigationTitle("Moneytor")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: mode == .log ? "Search expenses" : "Search limits")
            .animation(.default, value: mode)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("Moneytor")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Add Category", systemImage: "plus") { isAddingCategory = true }
                    Button { AssistantRouter.shared.isShowing = true } label: { AIIcon() }
                        .accessibilityLabel("Assistant")
                }
            }
            .sheet(isPresented: $isAddingCategory) { CategoryEditor(category: nil) }
            .sheet(item: $editingCategory) { CategoryEditor(category: $0) }
            .sheet(item: $loggingCategory) { LogSpendingSheet(category: $0) }
            .sheet(isPresented: $isLinkingExpenses) { LinkExpensesSheet() }
            .sheet(item: $relinkingLog) { LinkLogEditor(log: $0) }
            .sheet(isPresented: $isShowingNewMonth, onDismiss: startNewMonth) {
                NewMonthSheet(categories: categories) { newMonthChoice = $0 }
            }
        }
        .onAppear(perform: checkForNewMonth)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { checkForNewMonth() }
        }
    }

    private var currentMonth: String {
        Date.now.formatted(.iso8601.year().month())
    }

    private func checkForNewMonth() {
        guard budgetMonth != currentMonth, !isShowingNewMonth else { return }
        // Nothing to carry over on first launch or with no categories, so skip the prompt.
        if budgetMonth.isEmpty || categories.isEmpty {
            budgetMonth = currentMonth
        } else {
            isShowingNewMonth = true
        }
    }

    /// Runs after the new-month sheet closes. Swiping it away counts as keeping the budget.
    private func startNewMonth() {
        budgetMonth = currentMonth
        switch newMonthChoice {
        case .keepAndAdd:
            mode = .set
            isAddingCategory = true
        case .startFresh:
            categories.forEach { $0.isArchived = true }
            mode = .set
            isAddingCategory = true
        case .keep, nil:
            break
        }
        newMonthChoice = nil
    }
}

private struct CategoryRow: View {
    let category: BudgetCategory
    let mode: BudgetMode

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9))

            if mode == .set {
                let shortDate = Date.FormatStyle.dateTime.month(.abbreviated).day()
                let schedule = switch category.status {
                case .upcoming: "\(category.frequency.rawValue) · starts \(category.starts.formatted(shortDate))"
                case .ended: "Ended \(category.endDate?.formatted(shortDate) ?? "")"
                case .active where category.frequency == .once:
                    "Once · \(category.starts.formatted(shortDate)) – \(category.endDate?.formatted(shortDate) ?? "")"
                case .active:
                    category.frequency.rawValue + (category.endDate.map { " · until \($0.formatted(shortDate))" } ?? "")
                        + (category.dueDay.map { " · due day \($0)" } ?? "")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                    Text(schedule)
                        .font(.caption)
                        .foregroundStyle(category.status == .active ? Color.secondary : Color.orange)
                }
                Spacer()
                Text(category.limit, format: .currency(code: currencyCode))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } else {
                let remaining = category.remainingThisPeriod
                let spent = category.spentThisPeriod
                let isOver = remaining < 0
                let isComplete = remaining == 0 && category.limit > 0

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(category.name)
                        Spacer()
                        if isComplete {
                            Label(category.dueDay == nil ? "Complete" : "Paid", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                        } else {
                            Text(abs(remaining), format: .currency(code: currencyCode))
                                .monospacedDigit()
                                .bold()
                                .foregroundStyle(isOver ? .red : .primary)
                            Text(isOver ? "over" : "left")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: category.limit > 0 ? min(NSDecimalNumber(decimal: spent / category.limit).doubleValue, 1) : 1)
                        .tint(isOver ? .red : isComplete ? .green : .accentColor)
                    Text("\(spent.formatted(.currency(code: currencyCode))) of \(category.limit.formatted(.currency(code: currencyCode))) used \(category.periodName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LogRow: View {
    let log: SpendLog

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: log.category?.icon ?? "questionmark")
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.note.isEmpty ? (log.category?.name ?? "Expense") : log.note)
                let incomeNames = log.fundings.compactMap(\.income?.name)
                let paidFrom = incomeNames.isEmpty ? log.paidFrom : incomeNames.joined(separator: ", ")
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
            Text(-log.amount, format: .currency(code: currencyCode))
                .monospacedDigit()
                .foregroundStyle(.red)
        }
    }
}
