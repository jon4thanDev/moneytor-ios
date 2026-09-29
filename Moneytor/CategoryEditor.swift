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
    @State private var icon: String?
    @State private var hasDueDate = false
    @State private var dueDay = 1
    @State private var isCustomSchedule = false
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
        // With no name yet, suggest names that fit the chosen icon; otherwise match what's typed.
        let matches: [Suggestion] = if query.isEmpty {
            Self.suggestions.filter { $0.icon == icon }
        } else if exactSuggestion != nil {
            []
        } else {
            Array(Self.suggestions
                .filter { $0.name.lowercased().contains(query) || $0.keywords.contains { $0.hasPrefix(query) } }
                .sorted { $0.name.lowercased().hasPrefix(query) && !$1.name.lowercased().hasPrefix(query) }
                .prefix(6))
        }
        let showsDetail = exactSuggestion?.allowsDetail == true
        let fullName = showsDetail && !trimmedDetail.isEmpty ? "\(trimmedName) (\(trimmedDetail))" : trimmedName

        NavigationStack {
            Form {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.icons, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .frame(width: 40, height: 40)
                                .foregroundStyle(icon == symbol ? .white : .primary)
                                .background(icon == symbol ? Color.accentColor : Color(.tertiarySystemFill),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .onTapGesture { withAnimation { icon = symbol } }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Icon")
                } footer: {
                    if icon == nil {
                        Text("Choose an icon for this category.")
                    }
                }

                Section {
                    TextField("Name (e.g. Groceries)", text: $name)
                        .textInputAutocapitalization(.words)
                    ForEach(matches, id: \.name) { suggestion in
                        Button {
                            name = suggestion.name
                            icon = suggestion.icon
                            isDetailFocused = suggestion.allowsDetail
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
                    }
                }

                Section {
                    HStack {
                        Text(Locale.current.currencySymbol ?? "$")
                            .foregroundStyle(.secondary)
                        MoneyField(value: $limit)
                    }
                } header: {
                    Text("Expense Limit")
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
                            ForEach(Frequency.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                            .closesWhenPicked(startDate)
                        if frequency != .once {
                            Toggle("Has an End Date", isOn: $hasEndDate.animation())
                        }
                        if frequency == .once || hasEndDate {
                            DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                                .closesWhenPicked(endDate)
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
                        Text("One limit for everything from \(startDate.formatted(.dateTime.month(.abbreviated).day())) to \(endDate.formatted(.dateTime.month(.abbreviated).day())). It doesn't reset.")
                    case .daily:
                        Text("Resets every day\(until).")
                    case .weekly:
                        Text("Resets every week\(until).")
                    case .monthly where !isCustomSchedule:
                        Text("Resets on the 1st of every month. Tap Custom for a one-time, daily, or weekly limit, or to set start and end dates.")
                    case .monthly:
                        Text("Resets on the 1st of every month\(until).")
                    }
                }

                if !isCustomSchedule || frequency == .monthly {
                    Section {
                        Toggle("Has a Due Date", isOn: $hasDueDate.animation())
                        if hasDueDate {
                            Picker("Due Every Month On", selection: $dueDay) {
                                ForEach(1...31, id: \.self) { Text("Day \($0)") }
                            }
                        }
                    } footer: {
                        Text(hasDueDate
                            ? "Shows in Upcoming until you've logged the full limit for the month. In shorter months, days past the end fall on the last day."
                            : "Turn on for bills like rent, electricity, or subscriptions to see them in Upcoming.")
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
            .navigationTitle(category == nil ? "New Category" : "Edit Limit")
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
                        guard let limit, let icon else { return }
                        let target = category ?? BudgetCategory(name: fullName, icon: icon, limit: limit)
                        target.name = fullName
                        target.limit = limit
                        target.icon = icon
                        let repeats = isCustomSchedule ? frequency : .monthly
                        target.dueDay = repeats == .monthly && hasDueDate ? dueDay : nil
                        target.frequency = repeats
                        target.startDate = isCustomSchedule ? startDate : nil
                        target.endDate = isCustomSchedule && (repeats == .once || hasEndDate) ? endDate : nil
                        if category == nil { context.insert(target) }
                        dismiss()
                    }
                    .disabled(icon == nil || trimmedName.isEmpty || limit == nil || limit! < 0)
                }
            }
            .onAppear {
                guard let category else { return }
                name = category.name
                limit = category.limit
                icon = category.icon
                hasDueDate = category.dueDay != nil
                dueDay = category.dueDay ?? 1
                frequency = category.frequency
                startDate = category.starts
                hasEndDate = category.endDate != nil
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
}
