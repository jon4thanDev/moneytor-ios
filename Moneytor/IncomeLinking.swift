import SwiftUI
import SwiftData

/// Splits an expense across income sources, showing what each income has left this month.
struct FundingPicker: View {
    let total: Decimal
    /// The expense being edited, so its current links don't count against the incomes.
    var log: SpendLog?
    @Binding var amounts: [PersistentIdentifier: Decimal]

    @Query(sort: \IncomeSource.createdAt) private var incomes: [IncomeSource]

    var body: some View {
        let assigned = amounts.values.reduce(0, +)
        let missing = total - assigned

        Section {
            if incomes.isEmpty {
                Text("Add an income in the Income tab first.")
                    .foregroundStyle(.secondary)
            }
            ForEach(incomes) { income in
                let id = income.persistentModelID
                let alreadyUsed = log?.fundings.filter { $0.income == income }.reduce(0) { $0 + $1.amount } ?? 0
                let left = income.remainingThisMonth + alreadyUsed - (amounts[id] ?? 0)

                HStack {
                    Button {
                        amounts[id] = (amounts[id] ?? 0) + max(missing, 0)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(income.name)
                            Text("\(left.formatted(.currency(code: currencyCode))) left after this")
                                .font(.caption)
                                .foregroundStyle(left < 0 ? .red : .secondary)
                        }
                    }
                    .tint(.primary)
                    Spacer()
                    MoneyField(value: Binding(get: { amounts[id] }, set: { amounts[id] = $0 }))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
            }
        } header: {
            Text("Paid From")
        } footer: {
            if !incomes.isEmpty {
                if missing > 0 {
                    Text("Assign \(missing.formatted(.currency(code: currencyCode))) more. Tap an income to put the rest on it.")
                        .foregroundStyle(.red)
                } else if missing < 0 {
                    Text("That's \((-missing).formatted(.currency(code: currencyCode))) more than the expense. Lower an amount.")
                        .foregroundStyle(.red)
                } else {
                    Text("Covered. An expense can be split across several incomes.")
                }
            }
        }
        // Until the user splits it, the whole amount follows the one chosen income (salary by default).
        .onChange(of: total, initial: true) { _, newTotal in
            guard amounts.count <= 1 else { return }
            let chosen = amounts.keys.first.flatMap { id in incomes.first { $0.persistentModelID == id } }
                ?? incomes.first { $0.name.localizedCaseInsensitiveContains("salary") }
                ?? incomes.first
            if let chosen { amounts = [chosen.persistentModelID: newTotal] }
        }
    }
}

/// Lists this month's expenses that aren't fully paid from income yet, so every one gets linked.
struct LinkExpensesSheet: View {
    @AppStorage("linksExpensesToIncome") private var linksExpenses = false
    @Environment(\.dismiss) private var dismiss
    @Query private var logs: [SpendLog]
    @Query private var incomes: [IncomeSource]
    @State private var editing: SpendLog?

    var body: some View {
        let unlinked = logs
            .filter { Calendar.current.isDate($0.effectiveDate, equalTo: .now, toGranularity: .month) && !$0.isLinked }
            .sorted { $0.effectiveDate > $1.effectiveDate }

        NavigationStack {
            List {
                if unlinked.isEmpty {
                    ContentUnavailableView("All Linked", systemImage: "checkmark.circle",
                                           description: Text("Every expense this month is paid from an income."))
                } else if incomes.isEmpty {
                    ContentUnavailableView("No Income Yet", systemImage: "banknote",
                                           description: Text("Add an income in the Income tab so your expenses have somewhere to come from."))
                } else {
                    Section {
                        ForEach(unlinked) { log in
                            Button {
                                editing = log
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: log.category?.icon ?? "questionmark")
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(log.note.isEmpty ? (log.category?.name ?? "Expense") : log.note)
                                        LogDateLabel(log: log)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(log.amount, format: .currency(code: currencyCode))
                                        .monospacedDigit()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .tint(.primary)
                        }
                    } header: {
                        Text("\(unlinked.count) to link")
                    } footer: {
                        Text("Choose which income paid for each of this month's expenses so every income's balance adds up.")
                    }
                }
            }
            .navigationTitle("Link Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !unlinked.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Turn Off Linking") {
                            linksExpenses = false
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(!unlinked.isEmpty)
                }
            }
            .interactiveDismissDisabled(!unlinked.isEmpty)
            .sheet(item: $editing) { LinkLogEditor(log: $0) }
        }
    }
}

/// Chooses which incomes paid for one existing expense.
struct LinkLogEditor: View {
    let log: SpendLog

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var incomes: [IncomeSource]
    @State private var amounts: [PersistentIdentifier: Decimal]

    init(log: SpendLog) {
        self.log = log
        // Start from the current links so partly linked expenses can be finished.
        var amounts: [PersistentIdentifier: Decimal] = [:]
        for funding in log.fundings {
            guard let income = funding.income else { continue }
            amounts[income.persistentModelID, default: 0] += funding.amount
        }
        _amounts = State(initialValue: amounts)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(log.note.isEmpty ? (log.category?.name ?? "Expense") : log.note) {
                        Text(log.amount, format: .currency(code: currencyCode))
                            .monospacedDigit()
                    }
                } footer: {
                    LogDateLabel(log: log)
                }
                FundingPicker(total: log.amount, log: log, amounts: $amounts)
            }
            .navigationTitle("Paid From")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        log.setFundings(amounts, from: incomes, in: context)
                        dismiss()
                    }
                    .disabled(amounts.values.reduce(0, +) != log.amount)
                }
            }
        }
    }
}
