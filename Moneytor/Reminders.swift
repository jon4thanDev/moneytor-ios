import SwiftData
import SwiftUI
import UserNotifications

/// A simple to-do list, so small things to remember don't need the Reminders app. Type at the top to
/// add one quickly, or use the add button for one with a date.
struct RemindersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]
    @State private var newTitle = ""
    @FocusState private var isTypingNew: Bool
    @State private var editing: Reminder?
    @State private var isAdding = false
    @State private var isAddingWithDate = false
    @State private var searchText = ""
    @AppStorage("showsCompletedReminders") private var showsCompleted = false
    @Environment(\.scenePhase) private var scenePhase
    /// When the app was last opened. Reminders checked since then stay where they are, in case of a
    /// mistaken tap, and move to Completed once the user leaves the app.
    @State private var openedAt = Date.now

    var body: some View {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matching = reminders.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query)
        }
        let isJustChecked = { (reminder: Reminder) in reminder.completedAt.map { $0 >= openedAt } ?? false }
        // Soonest first; reminders without a date go last, oldest first.
        let open = matching.filter { !$0.isDone || isJustChecked($0) }
            .sorted { ($0.dueDate ?? .distantFuture, $0.createdAt) < ($1.dueDate ?? .distantFuture, $1.createdAt) }
        let overdue = open.filter(\.isPastDue)
        let today = open.filter { !$0.isPastDue && $0.dueDate.map { $0 < tomorrow } == true }
        let later = open.filter { $0.dueDate.map { $0 >= tomorrow } == true }
        let anytime = open.filter { $0.dueDate == nil }
        let completed = matching.filter { $0.isDone && !isJustChecked($0) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.tint)
                            TextField("New Reminder", text: $newTitle)
                                .focused($isTypingNew)
                                .submitLabel(.done)
                                .onSubmit {
                                    let title = newTitle.trimmingCharacters(in: .whitespaces)
                                    guard !title.isEmpty else { return }
                                    withAnimation { context.insert(Reminder(title: title)) }
                                    newTitle = ""
                                    // Stay in the field so several can be added in a row.
                                    isTypingNew = true
                                }
                            Button("Add with Date", systemImage: "calendar.badge.plus") { isAddingWithDate = true }
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .buttonStyle(.borderless)
                        }
                    } footer: {
                        Text("Press Done to add it without a date, or tap the calendar to pick a date and get a notification.")
                    }
                }

                if !query.isEmpty && open.isEmpty && (completed.isEmpty || !showsCompleted) {
                    ContentUnavailableView.search(text: query)
                } else if reminders.isEmpty {
                    ContentUnavailableView {
                        Label("No Reminders", systemImage: "checklist")
                    } description: {
                        Text("Type above to add one, or tap + to add one with a date and get a notification.")
                    }
                } else if open.isEmpty && query.isEmpty {
                    ContentUnavailableView("All Done", systemImage: "checkmark.circle",
                                           description: Text("Nothing left to remember for now."))
                }

                if !overdue.isEmpty {
                    Section("Overdue") { rows(overdue) }
                }
                if !today.isEmpty {
                    Section("Today") { rows(today) }
                }
                if !later.isEmpty {
                    Section("Later") { rows(later) }
                }
                if !anytime.isEmpty {
                    Section("No Date") { rows(anytime) }
                }
                if showsCompleted && !completed.isEmpty {
                    Section {
                        rows(completed)
                    } header: {
                        HStack {
                            Text("Completed")
                            Spacer()
                            Button("Clear", role: .destructive) {
                                withAnimation { completed.forEach(context.delete) }
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Reminders")
            .collapsesTabBarOnScroll()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search reminders")
            // From iOS 26 the add button sits beside the tab bar instead (see RootView).
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                if #available(iOS 26, *) {
                } else {
                    Button { isAdding = true } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    }
                    .accessibilityLabel("Add Reminder")
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $showsCompleted.animation()) {
                        Label(showsCompleted ? "Hide Completed" : "Show Completed",
                              systemImage: showsCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .toggleStyle(.button)
                }
            }
            .sheet(isPresented: $isAdding) { ReminderEditor(reminder: nil) }
            .sheet(isPresented: $isAddingWithDate) {
                ReminderEditor(reminder: nil, title: newTitle, startsWithDate: true) { newTitle = "" }
            }
            .sheet(item: $editing) { ReminderEditor(reminder: $0) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { openedAt = .now }
            }
        }
    }

    private func rows(_ reminders: [Reminder]) -> some View {
        ForEach(reminders) { reminder in
            ReminderRow(reminder: reminder) { editing = reminder }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        withAnimation { context.delete(reminder) }
                    }
                }
        }
    }
}

private struct ReminderRow: View {
    let reminder: Reminder
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation {
                    reminder.isDone.toggle()
                    reminder.completedAt = reminder.isDone ? .now : nil
                }
            } label: {
                Image(systemName: reminder.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(reminder.isDone ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reminder.isDone ? "Mark as Not Done" : "Mark as Done")

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.title)
                        .strikethrough(reminder.isDone)
                        .foregroundStyle(reminder.isDone ? .secondary : .primary)
                    if !reminder.notes.isEmpty {
                        Text(reminder.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let due = reminder.dueDate {
                        let calendar = Calendar.current
                        let day = calendar.isDateInToday(due) ? "Today"
                            : calendar.isDateInTomorrow(due) ? "Tomorrow"
                            : calendar.isDateInYesterday(due) ? "Yesterday"
                            : due.formatted(calendar.isDate(due, equalTo: .now, toGranularity: .year)
                                ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                                : .dateTime.month(.abbreviated).day().year())
                        Label(reminder.hasTime ? "\(day), \(due.formatted(date: .omitted, time: .shortened))" : day,
                              systemImage: reminder.hasTime ? "clock" : "calendar")
                            .font(.caption)
                            .foregroundStyle(reminder.isOverdue ? .red : .secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

struct ReminderEditor: View {
    let reminder: Reminder?
    var onSave: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var hasDate: Bool
    @State private var hasTime: Bool
    @State private var date: Date
    @FocusState private var isTitleFocused: Bool

    /// `title` and `startsWithDate` fill in a new reminder, like one typed in the list before tapping the calendar.
    init(reminder: Reminder?, title: String = "", startsWithDate: Bool = false, onSave: (() -> Void)? = nil) {
        self.reminder = reminder
        self.onSave = onSave
        _title = State(initialValue: reminder?.title ?? title)
        _notes = State(initialValue: reminder?.notes ?? "")
        _hasDate = State(initialValue: reminder.map { $0.dueDate != nil } ?? startsWithDate)
        _hasTime = State(initialValue: reminder?.hasTime ?? false)
        // A new time starts at the next full hour.
        let nextHour = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
        _date = State(initialValue: reminder?.dueDate ?? nextHour)
    }

    var body: some View {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)

        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($isTitleFocused)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...6)
                }

                Section {
                    Toggle(isOn: $hasDate.animation()) {
                        Label("Date", systemImage: "calendar")
                    }
                    if hasDate {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .closesWhenPicked(date)
                        Toggle(isOn: $hasTime.animation()) {
                            Label("Time", systemImage: "clock")
                        }
                        if hasTime {
                            DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                        }
                    }
                } footer: {
                    if !hasDate {
                        Text("Optional. Add a date to get a notification.")
                    } else if hasTime {
                        Text("You'll get a notification at \(date.formatted(date: .omitted, time: .shortened)) that day.")
                    } else {
                        Text("You'll get a notification at 9 AM that day.")
                    }
                }

                if let reminder {
                    Section {
                        Button("Delete Reminder", role: .destructive) {
                            context.delete(reminder)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(reminder == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let target = reminder ?? Reminder(title: trimmedTitle)
                        target.title = trimmedTitle
                        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        target.dueDate = !hasDate ? nil : hasTime ? date : Calendar.current.startOfDay(for: date)
                        target.hasTime = hasDate && hasTime
                        if reminder == nil { context.insert(target) }
                        onSave?()
                        dismiss()
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear { if reminder == nil && title.isEmpty { isTitleFocused = true } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Local notifications for reminders with a date, at their time or 9 AM on the day.
@MainActor
enum ReminderNotifications {
    nonisolated static let prefix = "reminder."

    /// Replaces all reminder notifications to match the current reminders. Safe to call often.
    static func refresh(for reminders: [Reminder]) {
        let calendar = Calendar.current
        let open = reminders.filter { !$0.isDone }
        // iOS keeps at most 64 pending notifications per app, shared with bill reminders.
        let requests = open
            .compactMap { reminder in reminder.alertDate.map { (reminder: reminder, date: $0) } }
            .filter { $0.date > .now }
            .sorted { $0.date < $1.date }
            .prefix(40)
            .map { reminder, date in
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.notes.isEmpty ? (reminder.hasTime ? "Reminder" : "Due today") : reminder.notes
                content.sound = .default
                content.threadIdentifier = "reminders"
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
                return UNNotificationRequest(identifier: prefix + BillReminders.encode(reminder.persistentModelID),
                                             content: content, trigger: trigger)
            }
        let openIDs = Set(open.map { prefix + BillReminders.encode($0.persistentModelID) })

        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            // Clear notifications already on screen for reminders since done or deleted.
            let stale = await center.deliveredNotifications().map(\.request.identifier)
                .filter { $0.hasPrefix(prefix) && !openIDs.contains($0) }
            center.removeDeliveredNotifications(withIdentifiers: stale)

            guard !requests.isEmpty, (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
            for request in requests { try? await center.add(request) }
        }
    }
}
