import SwiftUI
import SwiftData

@main
struct MoneytorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(for: [BudgetCategory.self, SpendLog.self, IncomeSource.self, ExpectedPayment.self, Funding.self, Transfer.self, Reminder.self])
    }
}

/// The tabs, plus bill reminders: keeps notifications current and opens the bill a tapped one is about.
private struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<BudgetCategory> { !$0.isArchived }) private var categories: [BudgetCategory]
    @Query private var logs: [SpendLog]
    @Query private var incomes: [IncomeSource]
    @Query private var payments: [ExpectedPayment]
    @Query private var reminders: [Reminder]
    @State private var payingBill: BudgetCategory?
    /// Bills already opened in this run of reminders, so a partly paid one doesn't come back right away.
    @State private var shownBills: Set<PersistentIdentifier> = []
    @State private var didPay = false
    @State private var tab: AppTab = .expenses
    @State private var isAddingCategory = false
    /// The add button's menu on Expenses and Income.
    @State private var isChoosingAdd = false
    @State private var isAddingIncome = false
    @State private var isAddingPayment = false
    @State private var isAddingReminder = false
    @State private var payingAhead: BudgetCategory?

    private enum AppTab: Hashable {
        case expenses, income, upcoming, reminders
        /// Not a page: selecting it adds a reminder on the Reminders tab, and opens a menu of what to
        /// add on Expenses and Income.
        case add
    }

    var body: some View {
        tabs
            .background(TapOutsideDismissesKeyboard())
            .sheet(isPresented: Bindable(AssistantRouter.shared).isShowing) { AssistantView() }
            .sheet(isPresented: Bindable(SettingsRouter.shared).isShowing) { SettingsView() }
            .sheet(isPresented: $isAddingCategory) { CategoryEditor(category: nil) }
            .sheet(item: $payingAhead) { LogSpendingSheet(category: $0, periodsAhead: $0.nextUnpaidPeriodsAhead ?? 0) }
            .sheet(isPresented: $isAddingIncome) { IncomeEditor(income: nil) }
            .sheet(isPresented: $isAddingPayment) { ExpectedPaymentEditor(payment: nil) }
            .sheet(isPresented: $isAddingReminder) { ReminderEditor(reminder: nil) }
        .sheet(item: $payingBill, onDismiss: openNextDueBill) { bill in
            let calendar = Calendar.current
            let due = bill.unpaidDueDate ?? .now
            let isOverdue = calendar.startOfDay(for: due) < calendar.startOfDay(for: .now)
            let moreCount = dueBills.filter { $0 != bill && !shownBills.contains($0.persistentModelID) }.count
            let more = moreCount > 0 ? " · \(moreCount) more due" : ""
            LogSpendingSheet(
                category: bill,
                reminder: (isOverdue ? "Overdue since \(due.formatted(.dateTime.month(.abbreviated).day()))" : "Due today") + more,
                onLogged: { didPay = true }
            )
        }
        .onAppear(perform: openTappedBill)
        .onChange(of: BillRouter.shared.openedCategoryID) { openTappedBill() }
        .onChange(of: BillRouter.shared.opensReminders, initial: true) { _, opens in
            guard opens else { return }
            BillRouter.shared.opensReminders = false
            tab = .reminders
        }
        // Links from the home-screen widget: moneytor://pay?id=… and moneytor://upcoming.
        .onOpenURL { url in
            guard url.scheme == "moneytor" else { return }
            tab = .upcoming
            if url.host() == "pay", let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value {
                BillRouter.shared.openedCategoryID = BillReminders.decode(id)
            }
        }
        .task { refreshReminders() }
        .onChange(of: scenePhase) { refreshReminders() }
        .onChange(of: logs.count) { refreshReminders() }
        .onChange(of: categories.map(\.dueDays)) { refreshReminders() }
        .onChange(of: incomes.map(\.payDay)) { refreshReminders() }
        .onChange(of: payments.count) { refreshReminders() }
        .onChange(of: reminders.map { [$0.title, $0.notes, $0.alertDate?.description ?? "", "\($0.isDone)"] }) { refreshReminders() }
    }

    @ViewBuilder private var tabs: some View {
        // The receipt symbol only exists from iOS 18.2.
        let expensesIcon = UIImage(systemName: "receipt") == nil ? "creditcard" : "receipt"
        if #available(iOS 26, *) {
            TabView(selection: $tab) {
                Tab("Expenses", systemImage: expensesIcon, value: .expenses) { BudgetView() }
                Tab("Income", systemImage: "banknote", value: .income) { IncomeView() }
                Tab("Upcoming", systemImage: "calendar.badge.clock", value: .upcoming) { UpcomingView() }
                    // Same bills the reminders are about; zero hides the badge.
                    .badge(dueBills.count)
                Tab("Reminders", systemImage: "checklist", value: .reminders) { RemindersView() }
                    .badge(dueReminderCount)
                // The search role is what places a tab in its own circle beside the tab bar. Four pages plus
                // this is as many as fit before iOS adds a More tab, which is why Settings opens from a gear.
                Tab(tab == .income ? "Add Income" : tab == .reminders ? "Add Reminder" : "Add",
                    systemImage: "plus", value: .add, role: .search) { Color.clear }
                    .hidden(tab == .upcoming)
            }
            // The system shrinks the bar to the current tab while scrolling down, but only brings it back
            // near the top. Switching to .never on any scroll up makes it expand right away, with its own animation.
            .tabBarMinimizeBehavior(TabBarScroll.shared.isScrollingUp ? .never : .onScrollDown)
            .overlay(alignment: .bottomTrailing) {
                // A tab can't anchor a popover, so this stands where the add button sits on iPhone.
                Color.clear
                    .frame(width: 62, height: 62)
                    .padding(.trailing, 21)
                    .padding(.bottom, 21)
                    .ignoresSafeArea()
                    .popover(isPresented: $isChoosingAdd, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            if tab == .income {
                                Button {
                                    isChoosingAdd = false
                                    isAddingIncome = true
                                } label: {
                                    AddOption(title: "Monthly Income", icon: "banknote", detail: "Keeps coming every month, like your salary.")
                                }
                                Divider()
                                Button {
                                    isChoosingAdd = false
                                    isAddingPayment = true
                                } label: {
                                    AddOption(title: "Expected Payment", icon: "calendar.badge.plus",
                                              detail: "Comes a few times and then stops, like a loan being paid back or a bonus.")
                                }
                            } else {
                                // Bills first, soonest due day first.
                                let payable = categories.filter { $0.earlyPaymentPeriod != nil }
                                    .sorted { ($0.dueDay ?? .max, $0.name.lowercased()) < ($1.dueDay ?? .max, $1.name.lowercased()) }
                                Button {
                                    isChoosingAdd = false
                                    isAddingCategory = true
                                } label: {
                                    AddOption(title: "New Category", icon: "square.grid.2x2", detail: "A spending limit or a bill, like Food or Rent.")
                                }
                                Divider()
                                Menu {
                                    ForEach(payable) { category in
                                        let next = category.earlyPaymentPeriod ?? category.currentPeriod
                                        Button {
                                            isChoosingAdd = false
                                            payingAhead = category
                                        } label: {
                                            Text(category.name)
                                            Text("\(category.title(of: next)) · \(category.remaining(in: next).formatted(.currency(code: currencyCode))) \(category.dueDay != nil ? "to pay" : "left")")
                                        }
                                    }
                                } label: {
                                    AddOption(title: "Advance Payment", icon: "forward.circle",
                                              detail: payable.isEmpty ? "Nothing to pay early right now." : "Pay now for later months or a payment that isn't due yet.")
                                }
                                .disabled(payable.isEmpty)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(width: 290)
                        .presentationCompactAdaptation(.popover)
                    }
            }
            .onChange(of: tab) { oldTab, newTab in
                guard newTab == .add else { return }
                tab = oldTab
                if oldTab == .reminders {
                    isAddingReminder = true
                } else {
                    isChoosingAdd = true
                }
            }
        } else {
            // Older systems can't set a tab apart, so Expenses shows a floating add button instead.
            TabView(selection: $tab) {
                BudgetView()
                    .tabItem { Label("Expenses", systemImage: expensesIcon) }
                    .tag(AppTab.expenses)
                IncomeView()
                    .tabItem { Label("Income", systemImage: "banknote") }
                    .tag(AppTab.income)
                UpcomingView()
                    .tabItem { Label("Upcoming", systemImage: "calendar.badge.clock") }
                    .badge(dueBills.count)
                    .tag(AppTab.upcoming)
                RemindersView()
                    .tabItem { Label("Reminders", systemImage: "checklist") }
                    .badge(dueReminderCount)
                    .tag(AppTab.reminders)
            }
        }
    }

    /// Unpaid bills that are due today or overdue, oldest first.
    private var dueBills: [BudgetCategory] {
        let today = Calendar.current.startOfDay(for: .now)
        return categories
            .compactMap { category in category.unpaidDueDate.map { (category, $0) } }
            .filter { Calendar.current.startOfDay(for: $0.1) <= today }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Reminders not done yet that are due today or overdue.
    private var dueReminderCount: Int {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return reminders.filter { !$0.isDone && $0.dueDate.map { $0 < tomorrow } == true }.count
    }

    private func refreshReminders() {
        categories.forEach { $0.applyScheduledChange() }
        incomes.forEach { $0.applyScheduledChange() }
        // Notification IDs come from each bill's and reminder's saved ID, so save any new ones first.
        try? context.save()
        BillReminders.refresh(for: categories)
        ReminderNotifications.refresh(for: reminders)
        WidgetSync.refresh(categories: categories, incomes: incomes, payments: payments)
    }

    private func openTappedBill() {
        guard let id = BillRouter.shared.openedCategoryID else { return }
        BillRouter.shared.openedCategoryID = nil
        guard let bill = context.model(for: id) as? BudgetCategory, !bill.isDeleted else { return }
        shownBills = [id]
        payingBill = bill
    }

    /// After paying a bill from a reminder, move straight on to the next one that's due.
    private func openNextDueBill() {
        guard didPay else {
            shownBills = []
            return
        }
        didPay = false
        guard let next = dueBills.first(where: { !shownBills.contains($0.persistentModelID) }) else {
            shownBills = []
            return
        }
        shownBills.insert(next.persistentModelID)
        payingBill = next
    }
}

/// One choice in the add button's popover: an icon, a name, and a line on what it's for.
private struct AddOption: View {
    let title: String
    let icon: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Closes the keyboard (or the calculator keypad) when you tap anywhere outside a text field,
/// on every screen and sheet, since they all share the window this watches.
private struct TapOutsideDismissesKeyboard: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private var tap: UITapGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, tap == nil else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            // Buttons and rows under the tap still get it.
            tap.cancelsTouchesInView = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            self.tap = tap
        }

        @objc private func tapped(_ tap: UITapGestureRecognizer) {
            tap.view?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Tapping another field moves the focus there instead.
            guard let view = touch.view else { return true }
            return !sequence(first: view, next: \.superview).contains { $0 is UITextField || $0 is UITextView }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// Which way the current page last scrolled, so the tab bar can expand as soon as it scrolls up.
@Observable @MainActor
final class TabBarScroll {
    static let shared = TabBarScroll()
    var isScrollingUp = false
}

@available(iOS 18, *)
private struct CollapsesTabBarOnScroll: ViewModifier {
    /// Only a finger moving the list counts. Rows being added or a sheet resizing the page also move the
    /// offset, and changing the tab bar then throws the list out of step with the title and search bar.
    @State private var isUserScrolling = false

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Clamped so the bounce at either end doesn't count as a change of direction.
                let offset = geometry.contentOffset.y + geometry.contentInsets.top
                let maxOffset = geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom - geometry.containerSize.height
                return min(max(offset, 0), max(maxOffset, 0))
            } action: { old, new in
                let isScrollingUp = new < old
                guard isUserScrolling, new != old, TabBarScroll.shared.isScrollingUp != isScrollingUp else { return }
                TabBarScroll.shared.isScrollingUp = isScrollingUp
            }
    }
}

extension View {
    /// Lets the tab bar shrink while this list scrolls down and come back on any scroll up.
    @ViewBuilder func collapsesTabBarOnScroll() -> some View {
        if #available(iOS 18, *) {
            modifier(CollapsesTabBarOnScroll())
        } else {
            self
        }
    }

    /// Closes a compact date picker's calendar as soon as a day is picked, rather than only on a tap
    /// outside it. Rebuilding the picker when its value changes is what closes the calendar.
    func closesWhenPicked(_ date: Date) -> some View {
        id(date)
    }
}
