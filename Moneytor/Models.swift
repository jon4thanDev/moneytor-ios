import Foundation
import SwiftData

let currencyCode = Locale.current.currency?.identifier ?? "USD"

@Model
final class BudgetCategory {
    var name: String
    var icon: String
    var limit: Decimal
    var createdAt: Date
    /// Hidden from the budget after "Start Fresh", but kept so past spending isn't lost.
    var isArchived = false
    /// Day of the month a bill in this category is due (1–31). Only used for monthly limits.
    var dueDay: Int?
    /// Stored as an optional raw value because categories saved before schedules existed have no
    /// value, and SwiftData crashes reading a missing non-optional enum. Nil means monthly.
    private var frequencyRawValue: String?
    /// Nil when the limit has no custom schedule and applies from the day it was created; see `starts`.
    var startDate: Date?
    /// When a temporary limit stops. Always set for one-time limits; nil means it keeps repeating.
    var endDate: Date?
    @Relationship(deleteRule: .cascade, inverse: \SpendLog.category)
    var logs: [SpendLog] = []

    init(name: String, icon: String, limit: Decimal) {
        self.name = name
        self.icon = icon
        self.limit = limit
        self.createdAt = .now
    }

    /// How often the limit resets. One-time limits cover everything from `starts` to `endDate`.
    var frequency: Frequency {
        get { frequencyRawValue.flatMap(Frequency.init(rawValue:)) ?? .monthly }
        set { frequencyRawValue = newValue.rawValue }
    }

    var starts: Date { startDate ?? createdAt }

    enum Status { case upcoming, active, ended }

    var status: Status {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if today < calendar.startOfDay(for: starts) { return .upcoming }
        if let endDate, today > calendar.startOfDay(for: endDate) { return .ended }
        return .active
    }

    /// The stretch of time whose spending counts against the limit right now.
    var currentPeriod: DateInterval {
        let calendar = Calendar.current
        let component: Calendar.Component
        switch frequency {
        case .once:
            let start = calendar.startOfDay(for: starts)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate ?? starts)) ?? start
            return DateInterval(start: start, end: max(start, end))
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        }
        return calendar.dateInterval(of: component, for: .now) ?? DateInterval(start: .now, duration: 0)
    }

    /// Finishes phrases like "₱200 left in Food ___".
    var periodName: String {
        switch frequency {
        case .once: "overall"
        case .daily: "today"
        case .weekly: "this week"
        case .monthly: "this month"
        }
    }

    func isInCurrentPeriod(_ date: Date) -> Bool {
        let period = currentPeriod
        return date >= period.start && date < period.end
    }

    var spentThisPeriod: Decimal {
        logs.filter { isInCurrentPeriod($0.effectiveDate) }.reduce(0) { $0 + $1.amount }
    }

    var remainingThisPeriod: Decimal { limit - spentThisPeriod }

    /// How much this limit adds up to within the current month, so daily and weekly limits
    /// can be compared with monthly income.
    var limitThisMonth: Decimal {
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: .now) else { return limit }
        let activeStart = max(month.start, calendar.startOfDay(for: starts))
        let activeEnd = endDate.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
            .map { min($0, month.end) } ?? month.end
        guard activeStart < activeEnd else { return 0 }
        let activeDays = Decimal(calendar.dateComponents([.day], from: activeStart, to: activeEnd).day ?? 0)
        switch frequency {
        case .once, .monthly: return limit
        case .daily: return limit * activeDays
        case .weekly: return limit * activeDays / 7
        }
    }

    /// What's still unspent of `limitThisMonth`. Ended limits have nothing left to spend.
    var remainingThisMonth: Decimal {
        guard status != .ended, limitThisMonth > 0 else { return 0 }
        if frequency == .once { return remainingThisPeriod }
        let spent = logs
            .filter { Calendar.current.isDate($0.effectiveDate, equalTo: .now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
        return limitThisMonth - spent
    }

    /// This month's due date while the bill still has something left to pay; nil for paid bills and non-bills.
    var unpaidDueDate: Date? {
        guard frequency == .monthly, status == .active, limit > 0, remainingThisPeriod > 0,
              let due = dueDate(inMonthOf: .now) else { return nil }
        if let endDate, Calendar.current.startOfDay(for: due) > Calendar.current.startOfDay(for: endDate) { return nil }
        return due
    }

    /// The due date in the month containing `date`. A due day past the end of a short month
    /// (e.g. the 31st in February) falls on that month's last day.
    func dueDate(inMonthOf date: Date) -> Date? {
        guard let dueDay else { return nil }
        let calendar = Calendar.current
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start,
              let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count
        else { return nil }
        return calendar.date(byAdding: .day, value: min(dueDay, daysInMonth) - 1, to: monthStart)
    }
}

@Model
final class SpendLog {
    var amount: Decimal
    var note: String
    /// The date the user set for this expense; nil when they didn't pick one.
    var date: Date?
    /// When the expense was logged. Set by the app and never edited; nil only for expenses logged
    /// before this was tracked, which always have `date`.
    var createdAt: Date?
    var category: BudgetCategory?
    /// Where the money for a paid bill came from, like "Salary", when it isn't linked to an income.
    var paidFrom: String?
    /// Which incomes paid for this expense. One expense can be split across several incomes.
    @Relationship(deleteRule: .cascade, inverse: \Funding.log)
    var fundings: [Funding] = []

    init(amount: Decimal, note: String, date: Date?, category: BudgetCategory) {
        self.amount = amount
        self.note = note
        self.date = date
        self.createdAt = .now
        self.category = category
    }

    /// The day the expense counts on: the date the user set, otherwise when it was logged.
    var effectiveDate: Date { date ?? createdAt ?? .distantPast }

    /// True when linked incomes cover the full amount. Links to a deleted income don't count.
    var isLinked: Bool {
        fundings.filter { $0.income != nil }.reduce(0) { $0 + $1.amount } == amount
    }

    /// Replaces the income links with the given amount per income.
    func setFundings(_ amounts: [PersistentIdentifier: Decimal], from incomes: [IncomeSource], in context: ModelContext) {
        fundings.forEach(context.delete)
        fundings = incomes.compactMap { income in
            guard let amount = amounts[income.persistentModelID], amount > 0 else { return nil }
            let funding = Funding(amount: amount, income: income)
            context.insert(funding)
            return funding
        }
    }
}

@Model
final class IncomeSource {
    var name: String
    var amount: Decimal
    var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \Funding.income)
    var fundings: [Funding] = []

    init(name: String, amount: Decimal) {
        self.name = name
        self.amount = amount
        self.createdAt = .now
    }

    /// What's left after this month's expenses paid from this income.
    var remainingThisMonth: Decimal {
        amount - fundings
            .filter { $0.log.map { Calendar.current.isDate($0.effectiveDate, equalTo: .now, toGranularity: .month) } ?? false }
            .reduce(0) { $0 + $1.amount }
    }
}

/// The part of an expense paid from one income.
@Model
final class Funding {
    var amount: Decimal
    var income: IncomeSource?
    var log: SpendLog?

    init(amount: Decimal, income: IncomeSource) {
        self.amount = amount
        self.income = income
    }
}

enum Frequency: String, Codable, CaseIterable {
    case once = "Once"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
}

/// Money coming in for a limited time, like a friend paying back a loan in installments.
@Model
final class ExpectedPayment {
    var name: String
    /// Amount of each payment.
    var amount: Decimal
    var frequency: Frequency
    var startDate: Date
    /// Same as `startDate` for one-time payments.
    var endDate: Date
    var createdAt: Date

    init(name: String, amount: Decimal, frequency: Frequency, startDate: Date, endDate: Date) {
        self.name = name
        self.amount = amount
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = .now
    }

    var paymentDates: [Date] {
        Self.paymentDates(frequency: frequency, start: startDate, end: endDate)
    }

    /// Every payment date from start to end, in order.
    static func paymentDates(frequency: Frequency, start: Date, end: Date) -> [Date] {
        let component: Calendar.Component
        switch frequency {
        case .once: return [start]
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        }
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: end)
        var dates: [Date] = []
        // Counting from the start date each time keeps monthly payments on the right day (Jan 31 → Feb 28 → Mar 31).
        while dates.count < 1000,
              let date = calendar.date(byAdding: component, value: dates.count, to: start),
              calendar.startOfDay(for: date) <= lastDay {
            dates.append(date)
        }
        return dates
    }
}
