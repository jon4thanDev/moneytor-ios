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
        .modelContainer(for: [BudgetCategory.self, SpendLog.self, IncomeSource.self, ExpectedPayment.self, Funding.self])
    }
}

/// The tabs, plus bill reminders: keeps notifications current and opens the bill a tapped one is about.
private struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<BudgetCategory> { !$0.isArchived }) private var categories: [BudgetCategory]
    @Query private var logs: [SpendLog]
    @State private var payingBill: BudgetCategory?
    /// Bills already opened in this run of reminders, so a partly paid one doesn't come back right away.
    @State private var shownBills: Set<PersistentIdentifier> = []
    @State private var didPay = false

    var body: some View {
        TabView {
            BudgetView()
                // The wallet symbol only exists from iOS 18.
                .tabItem { Label("Budget", systemImage: UIImage(systemName: "wallet.bifold") == nil ? "creditcard" : "wallet.bifold") }
            IncomeView()
                .tabItem { Label("Income", systemImage: "chart.line.uptrend.xyaxis") }
            UpcomingView()
                .tabItem { Label("Upcoming", systemImage: "calendar.badge.clock") }
                // Same bills the reminders are about; zero hides the badge.
                .badge(dueBills.count)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .background(TapOutsideDismissesKeyboard())
        .sheet(isPresented: Bindable(AssistantRouter.shared).isShowing) { AssistantView() }
        .sheet(item: $payingBill, onDismiss: openNextDueBill) { bill in
            let calendar = Calendar.current
            let due = bill.dueDate(inMonthOf: .now) ?? .now
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
        .task { refreshReminders() }
        .onChange(of: scenePhase) { refreshReminders() }
        .onChange(of: logs.count) { refreshReminders() }
        .onChange(of: categories.map(\.dueDay)) { refreshReminders() }
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

    private func refreshReminders() {
        // Notification IDs come from each bill's saved ID, so save any new categories first.
        try? context.save()
        BillReminders.refresh(for: categories)
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

extension View {
    /// Closes a compact date picker's calendar as soon as a day is picked, rather than only on a tap
    /// outside it. Rebuilding the picker when its value changes is what closes the calendar.
    func closesWhenPicked(_ date: Date) -> some View {
        id(date)
    }
}
