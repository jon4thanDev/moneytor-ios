import SwiftUI
import SwiftData

/// Moves unused money from one limit to another, like what's left of Daily Work into Daily Food.
struct TransferSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<BudgetCategory> { !$0.isArchived }, sort: \BudgetCategory.name)
    private var categories: [BudgetCategory]
    @State private var from: BudgetCategory?
    @State private var to: BudgetCategory?
    @State private var amount: Decimal?
    @State private var note = ""

    /// Opened from a category, it's the source when it has money left, otherwise the destination.
    init(category: BudgetCategory? = nil) {
        let hasMoneyLeft = (category?.remainingThisPeriod ?? 0) > 0
        _from = State(initialValue: hasMoneyLeft ? category : nil)
        _to = State(initialValue: hasMoneyLeft ? nil : category)
    }

    var body: some View {
        let active = categories.filter { $0.status == .active }
        let available = max(from?.remainingThisPeriod ?? 0, 0)
        let entered = amount ?? 0

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
                } footer: {
                    if let from, entered > available {
                        Label("\(from.name) only has \(available.formatted(.currency(code: currencyCode))) left \(from.periodName).",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("From", selection: $from) {
                        Text("Choose").tag(BudgetCategory?.none)
                        ForEach(active) { category in
                            Text("\(category.name) · \(max(category.remainingThisPeriod, 0).formatted(.currency(code: currencyCode))) left")
                                .tag(Optional(category))
                        }
                    }
                    Button("Swap", systemImage: "arrow.up.arrow.down") {
                        (from, to) = (to, from)
                    }
                    .disabled(from == nil && to == nil)
                    Picker("To", selection: $to) {
                        Text("Choose").tag(BudgetCategory?.none)
                        ForEach(active.filter { $0 != from }) { category in
                            Text(category.name).tag(Optional(category))
                        }
                    }
                } footer: {
                    if let from, available > 0 {
                        Button("Move all \(available.formatted(.currency(code: currencyCode))) left in \(from.name)") {
                            amount = available
                        }
                        .font(.footnote)
                    } else if let from {
                        Text("Nothing left in \(from.name) \(from.periodName) to move.")
                    } else {
                        Text("Move money you won't use, like a day you didn't commute, into another expense.")
                    }
                }

                Section {
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle("Transfer Funds")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: from) {
                if to == from { to = nil }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transfer") {
                        guard let from, let to else { return }
                        context.insert(Transfer(amount: entered, note: note.trimmingCharacters(in: .whitespaces), from: from, to: to))
                        dismiss()
                    }
                    .disabled(from == nil || to == nil || from == to || entered <= 0 || entered > available)
                }
            }
        }
    }
}

/// A note kept to one line, with an eye button to read all of it when it doesn't fit.
struct TruncatedNote: View {
    let note: String
    @State private var isShowingAll = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(note)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 6) {
                Text(note)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button { isShowingAll = true } label: {
                    Image(systemName: "eye")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Show full note")
            }
        }
        .popover(isPresented: $isShowingAll) {
            Text(note)
                .font(.body)
                .padding()
                .frame(maxWidth: 320, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
        }
    }
}
