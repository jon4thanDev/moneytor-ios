import SwiftData
import WidgetKit

/// Saves what the home-screen widget shows and asks it to redraw.
@MainActor
enum WidgetSync {
    static func refresh(categories: [BudgetCategory], incomes: [IncomeSource], payments: [ExpectedPayment]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let horizon = calendar.date(byAdding: .month, value: 2, to: today) ?? today

        // Later due dates too, so they still turn up as due if the app isn't opened before then.
        let bills = categories.flatMap { category in
            let id = BillReminders.encode(category.persistentModelID)
            return category.unpaidDues(until: horizon)
                .map { WidgetSnapshot.Bill(id: id, name: category.name, icon: category.icon, amount: $0.amount, due: $0.date) }
        }

        let events = bills.map { WidgetSnapshot.Event(name: $0.name, icon: $0.icon, amount: $0.amount, date: $0.due, isIncoming: false) }
            + incomes.flatMap { income in
                income.payDates(through: horizon).map {
                    WidgetSnapshot.Event(name: income.name, icon: "banknote.fill", amount: income.amount(inMonthOf: $0), date: $0, isIncoming: true)
                }
            }
            + payments.flatMap { payment in
                payment.paymentDates
                    .filter { calendar.startOfDay(for: $0) >= today && $0 <= horizon }
                    .map { WidgetSnapshot.Event(name: payment.name, icon: "arrow.down.circle.fill", amount: payment.amount, date: $0, isIncoming: true) }
            }

        WidgetSnapshot(bills: bills.sorted { $0.due < $1.due }, events: events.sorted { $0.date < $1.date }).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
