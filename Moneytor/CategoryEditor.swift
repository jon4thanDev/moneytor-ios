import SwiftUI
import SwiftData

struct CategoryEditor: View {
    let category: BudgetCategory?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    /// Optional specific for categories like Subscriptions, saved as "Subscriptions (Netflix)".
    @State private var detail = ""
    @State private var limit: Decimal?
    /// The icon the user picked; nil means it follows the name.
    @State private var icon: String?
    @State private var isPickingIcon = false
    @State private var hasDueDate = false
    /// Days of the month a monthly bill is due; `BudgetCategory.monthEnd` for the last day.
    @State private var dueDays: Set<Int> = [1]
    @State private var isCustomSchedule = false
    /// False once the user cancels a limit change scheduled for a later month; cleared on Save.
    @State private var keepsScheduledChange = true
    @State private var frequency: Frequency = .monthly
    @State private var startDate = Date.now
    @State private var hasEndDate = false
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @FocusState private var isDetailFocused: Bool

    private static let icons = [
        "cart.fill", "fork.knife", "car.fill", "fuelpump.fill", "airplane", "house.fill",
        "bolt.fill", "drop.fill", "wifi", "antenna.radiowaves.left.and.right", "doc.text.fill", "repeat",
        "briefcase.fill", "bag.fill", "tshirt.fill", "gift.fill", "heart.fill", "beach.umbrella.fill",
        "cross.case.fill", "pawprint.fill", "cat.fill", "dog.fill", "graduationcap.fill", "book.fill",
        "gamecontroller.fill", "film.fill", "figure.run", "banknote.fill", "creditcard.fill", "ellipsis.circle.fill",
    ]

    private struct Suggestion {
        let name: String
        let icon: String
        var keywords: [String] = []
        var allowsDetail = false
    }

    private static let suggestions = [
        Suggestion(name: "Food", icon: "fork.knife", keywords: ["meals", "restaurant", "eating out"]),
        Suggestion(name: "Groceries", icon: "cart.fill", keywords: ["supermarket", "market"]),
        Suggestion(name: "Transportation", icon: "car.fill", keywords: ["commute", "fare", "taxi"]),
        Suggestion(name: "Gas", icon: "fuelpump.fill", keywords: ["fuel"]),
        Suggestion(name: "Work", icon: "briefcase.fill", keywords: ["office", "business"]),
        Suggestion(name: "Travel", icon: "airplane", keywords: ["trip", "vacation", "flight", "hotel"]),
        Suggestion(name: "Leisure", icon: "beach.umbrella.fill", keywords: ["fun", "hobby", "relax"]),
        Suggestion(name: "Rent", icon: "house.fill", keywords: ["housing", "home"]),
        Suggestion(name: "Bills", icon: "doc.text.fill", keywords: ["utilities"]),
        Suggestion(name: "Electricity", icon: "bolt.fill", keywords: ["power", "electric", "utilities"]),
        Suggestion(name: "Water", icon: "drop.fill", keywords: ["utilities"]),
        Suggestion(name: "Wi-Fi (Internet)", icon: "wifi", keywords: ["wifi", "internet", "broadband"]),
        Suggestion(name: "Mobile Data", icon: "antenna.radiowaves.left.and.right", keywords: ["load", "phone"]),
        Suggestion(name: "Subscriptions", icon: "repeat", keywords: ["netflix", "spotify", "streaming", "apps"], allowsDetail: true),
        Suggestion(name: "Pet Food", icon: "pawprint.fill", keywords: ["pets"]),
        Suggestion(name: "Cat Food", icon: "cat.fill", keywords: ["pets"]),
        Suggestion(name: "Dog Food", icon: "dog.fill", keywords: ["pets"]),
        Suggestion(name: "Gifts", icon: "gift.fill", keywords: ["present", "birthday"]),
        Suggestion(name: "Dates", icon: "heart.fill", keywords: ["date night", "romance", "partner"]),
        Suggestion(name: "Health", icon: "cross.case.fill", keywords: ["medicine", "doctor", "pharmacy"]),
        Suggestion(name: "Shopping", icon: "bag.fill", keywords: ["clothes", "mall"]),
        Suggestion(name: "Clothing", icon: "tshirt.fill", keywords: ["clothes", "shoes"]),
        Suggestion(name: "Entertainment", icon: "film.fill", keywords: ["movies", "games"]),
        Suggestion(name: "Games", icon: "gamecontroller.fill", keywords: ["gaming", "console"]),
        Suggestion(name: "Fitness", icon: "figure.run", keywords: ["gym", "sports", "exercise"]),
        Suggestion(name: "Education", icon: "graduationcap.fill", keywords: ["school", "tuition", "books"]),
        Suggestion(name: "Books", icon: "book.fill", keywords: ["reading"]),
        Suggestion(name: "Savings", icon: "banknote.fill", keywords: ["save", "emergency fund"]),
        Suggestion(name: "Credit Card", icon: "creditcard.fill", keywords: ["debt", "loan", "installment"]),
        Suggestion(name: "Miscellaneous", icon: "ellipsis.circle.fill", keywords: ["other", "misc"]),
    ]

    var body: some View {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespaces)
        let query = trimmedName.lowercased()
        let exactSuggestion = Self.suggestions.first { $0.name.lowercased() == query }
        let matches: [Suggestion] = query.isEmpty || exactSuggestion != nil ? [] : Array(Self.suggestions
            .filter { $0.name.lowercased().contains(query) || $0.keywords.contains { $0.hasPrefix(query) } }
            .sorted { $0.name.lowercased().hasPrefix(query) && !$1.name.lowercased().hasPrefix(query) }
            .prefix(6))
        let showsDetail = exactSuggestion?.allowsDetail == true
        let fullName = showsDetail && !trimmedDetail.isEmpty ? "\(trimmedName) (\(trimmedDetail))" : trimmedName
        let shownIcon = icon ?? exactSuggestion?.icon ?? matches.first?.icon ?? "tag.fill"
        let repeats = isCustomSchedule ? frequency : .monthly
        let isPerPayment = repeats == .monthly && hasDueDate && dueDays.count > 1
        let pick = { (suggestion: Suggestion) in
            name = suggestion.name
            isDetailFocused = suggestion.allowsDetail
        }

        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Button { isPickingIcon = true } label: {
                            Image(systemName: shownIcon)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 11))
                                .contentTransition(.symbolEffect(.replace))
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 17))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color(.systemGray))
                                        .offset(x: 5, y: 5)
                                }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Change icon")
                        TextField("Name (e.g. Groceries)", text: $name)
                            .font(.title3)
                            .textInputAutocapitalization(.words)
                    }
                    .padding(.vertical, 4)
                    if query.isEmpty && category == nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.suggestions.prefix(12), id: \.name) { suggestion in
                                    Button { pick(suggestion) } label: {
                                        Label {
                                            Text(suggestion.name).foregroundStyle(.primary)
                                        } icon: {
                                            Image(systemName: suggestion.icon).foregroundStyle(Color.accentColor)
                                        }
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Color(.tertiarySystemFill), in: Capsule())
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    }
                    ForEach(matches, id: \.name) { suggestion in
                        Button {
                            pick(suggestion)
                        } label: {
                            Label {
                                Text(suggestion.name)
                            } icon: {
                                Image(systemName: suggestion.icon)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .tint(.primary)
                    }
                    if showsDetail {
                        TextField("Which one? (optional, e.g. Netflix)", text: $detail)
                            .textInputAutocapitalization(.words)
                            .focused($isDetailFocused)
                    }
                } header: {
                    Text("Category")
                } footer: {
                    if showsDetail {
                        Text(trimmedDetail.isEmpty
                            ? "Leave blank to keep it general, or name one to track it on its own."
                            : "Saved as “\(fullName)”.")
                    } else if icon == nil && category == nil {
                        Text("The icon follows the name. Tap it to choose another.")
                    }
                }

                Section {
                    HStack {
                        Text(Locale.current.currencySymbol ?? "$")
                            .foregroundStyle(.secondary)
                        CalculatorField(value: $limit)
                    }
                    if keepsScheduledChange, let category, let newLimit = category.scheduledLimit, let month = category.scheduledLimitMonth {
                        ScheduledChangeRow(amount: newLimit, month: month) { keepsScheduledChange = false }
                    }
                } header: {
                    Text(isPerPayment ? "Amount per Payment" : "Expense Limit")
                } footer: {
                    if isPerPayment {
                        let perMonth = ((limit ?? 0) * Decimal(dueDays.count)).formatted(.currency(code: currencyCode))
                        Text("Due \(dueDays.count) times a month, so \(perMonth) a month in total.")
                    }
                }

                Section {
                    if !isCustomSchedule {
                        Button {
                            withAnimation { isCustomSchedule = true }
                        } label: {
                            Label("Custom", systemImage: "calendar.badge.plus")
                        }
                    } else {
                        Picker("Repeats", selection: $frequency.animation()) {
                            ForEach(Frequency.allCases, id: \.self) { Text($0 == .biweekly ? "2 Weeks" : $0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        DatePicker(frequency == .once ? "Date" : "Starts", selection: $startDate, displayedComponents: .date)
                            .closesWhenPicked(startDate)
                        if frequency != .once {
                            Toggle("Has an End Date", isOn: $hasEndDate.animation())
                            if hasEndDate {
                                DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                                    .closesWhenPicked(endDate)
                            }
                        }
                        Button("Remove Custom Schedule", role: .destructive) {
                            withAnimation { isCustomSchedule = false }
                        }
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    let until = hasEndDate ? " until \(endDate.formatted(.dateTime.month(.abbreviated).day()))" : ""
                    switch isCustomSchedule ? frequency : .monthly {
                    case .once:
                        Text("A one-time limit just for \(startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())). It doesn't reset.")
                    case .daily:
                        Text("Resets every day\(until).")
                    case .weekly:
                        Text("Resets every week\(until).")
                    case .biweekly:
                        Text("Resets every 2 weeks, counting from \(startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))\(until).")
                    case .monthly where !isCustomSchedule:
                        Text("Resets on the 1st of every month. Tap Custom for a one-time, daily, weekly, or every-2-weeks limit, or to set start and end dates.")
                    case .monthly:
                        Text("Resets on the 1st of every month\(until).")
                    }
                }

                if repeats == .monthly || repeats == .biweekly {
                    Section {
                        Toggle("Has a Due Date", isOn: $hasDueDate.animation())
                        if hasDueDate && repeats == .monthly {
                            // Like the Calendar app's monthly repeat: tap every day it's due, or End for the last day.
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                                ForEach(Array(1...31) + [BudgetCategory.monthEnd], id: \.self) { day in
                                    let isOn = dueDays.contains(day)
                                    let isMonthEnd = day == BudgetCategory.monthEnd
                                    Button {
                                        if isOn { dueDays.remove(day) } else { dueDays.insert(day) }
                                    } label: {
                                        Text(isMonthEnd ? "End" : "\(day)")
                                            .font(.subheadline.weight(isOn ? .semibold : .regular))
                                            .monospacedDigit()
                                            .foregroundStyle(isOn ? .white : isMonthEnd ? Color.accentColor : .primary)
                                            .frame(width: 36, height: 36)
                                            .background(isOn ? Color.accentColor : Color.clear, in: Circle())
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(isMonthEnd ? "Last day of the month" : "Day \(day)")
                                    .accessibilityAddTraits(isOn ? .isSelected : [])
                                }
                            }
                            .padding(.vertical, 4)
                            .animation(.snappy, value: dueDays)
                        }
                    } header: {
                        if hasDueDate && repeats == .monthly { Text("Due Every Month On") }
                    } footer: {
                        let upcoming = "Each due date shows in Upcoming until it's paid."
                        if !hasDueDate {
                            Text("Turn on for bills like rent, electricity, or subscriptions to see them in Upcoming.")
                        } else if repeats == .biweekly {
                            Text("Due every other \(startDate.formatted(.dateTime.weekday(.wide))), starting \(startDate.formatted(.dateTime.month(.abbreviated).day())). Change Starts to move it. \(upcoming)")
                        } else if dueDays.isEmpty {
                            Text("Pick at least one day, or End for the last day of every month.")
                        } else {
                            Text("Due on the \(BudgetCategory.describe(dueDays: Array(dueDays))) of every month. \(upcoming)"
                                 + (dueDays.contains { (29...31).contains($0) } ? " In shorter months, days past the end fall on the last day." : ""))
                        }
                    }
                }

                if let category {
                    Section {
                        Button("Delete Category", role: .destructive) {
                            context.delete(category)
                            dismiss()
                        }
                    }

                    ExpenseHistory(category: category)
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isPickingIcon) {
                IconPicker(selection: shownIcon) { icon = $0 }
            }
            .onChange(of: startDate) { _, newStart in
                if endDate < newStart { endDate = newStart }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let limit else { return }
                        let target = category ?? BudgetCategory(name: fullName, icon: shownIcon, limit: limit)
                        target.name = fullName
                        target.limit = limit
                        target.icon = shownIcon
                        target.dueDays = !hasDueDate ? [] : repeats == .monthly ? Array(dueDays) : repeats == .biweekly ? [1] : []
                        target.frequency = repeats
                        target.startDate = isCustomSchedule ? startDate : nil
                        // A one-time limit covers a single day, so it ends the day it starts.
                        target.endDate = !isCustomSchedule ? nil : repeats == .once ? startDate : hasEndDate ? endDate : nil
                        if !keepsScheduledChange {
                            target.scheduledLimit = nil
                            target.scheduledLimitMonth = nil
                        }
                        if category == nil { context.insert(target) }
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || limit == nil || limit! < 0 || (hasDueDate && repeats == .monthly && dueDays.isEmpty))
                }
            }
            .onAppear {
                guard let category else { return }
                name = category.name
                limit = category.limit
                icon = category.icon
                hasDueDate = category.dueDay != nil
                dueDays = category.frequency == .monthly && !category.dueDays.isEmpty ? Set(category.dueDays) : [1]
                frequency = category.frequency
                startDate = category.starts
                hasEndDate = category.frequency != .once && category.endDate != nil
                endDate = category.endDate ?? endDate
                // A plain monthly limit that started when it was created has nothing custom to show.
                isCustomSchedule = category.frequency != .monthly || category.endDate != nil
                    || Calendar.current.startOfDay(for: category.starts) > Calendar.current.startOfDay(for: category.createdAt)
                // Split "Subscriptions (Netflix)" back into its name and detail fields.
                if let match = category.name.firstMatch(of: #/^(.+?) \((.+)\)$/#),
                   Self.suggestions.contains(where: { $0.allowsDetail && $0.name == match.output.1 }) {
                    name = String(match.output.1)
                    detail = String(match.output.2)
                }
            }
        }
    }

    /// A compact grid of icons in a half-height sheet; picking one closes it.
    private struct IconPicker: View {
        let selection: String
        let onPick: (String) -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 12)], spacing: 12) {
                        ForEach(CategoryEditor.icons, id: \.self) { symbol in
                            Button {
                                onPick(symbol)
                                dismiss()
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 48, height: 48)
                                    .foregroundStyle(selection == symbol ? .white : .primary)
                                    .background(selection == symbol ? Color.accentColor : Color(.tertiarySystemFill),
                                                in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .navigationTitle("Choose Icon")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
