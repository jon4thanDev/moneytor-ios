import Foundation
import SwiftData

@Model
final class BudgetCategory {
    var name: String
    var icon: String
    var limit: Decimal
    var createdAt: Date
    /// Hidden from the budget after "Start Fresh", but kept so past spending isn't lost.
    var isArchived = false
    /// Day of the month a bill in this category is due (1–31, or `monthEnd`); the earliest one when it's
    /// due on several days. For every-2-weeks limits any value just marks it as a bill, due at the start
    /// of each cycle. Nil for limits that aren't bills.
    var dueDay: Int?
    /// The rest of a monthly bill's due days after `dueDay`, in order; nil when it's due once a month.
    var moreDueDays: [Int]?
    /// A new limit that takes over from `scheduledLimitMonth` (the first moment of that month), like a
    /// rent increase from next month. Becomes `limit` once that month arrives; see `applyScheduledChange()`.
    var scheduledLimit: Decimal?
    var scheduledLimitMonth: Date?
    /// A due day meaning the last day of every month, whether that's the 28th, 29th, 30th or 31st.
    /// Past every month's length, so `dueDate(inMonthOf:)` always lands it on the last day.
    static let monthEnd = 32
    /// Stored as an optional raw value because categories saved before schedules existed have no
    /// value, and SwiftData crashes reading a missing non-optional enum. Nil means monthly.
    private var frequencyRawValue: String?
    /// Nil when the limit has no custom schedule and applies from the day it was created; see `starts`.
    var startDate: Date?
    /// When a temporary limit stops. Always set for one-time limits; nil means it keeps repeating.
    var endDate: Date?
    @Relationship(deleteRule: .cascade, inverse: \SpendLog.category)
    var logs: [SpendLog] = []
    /// Money moved out of this limit into another one.
    @Relationship(deleteRule: .nullify, inverse: \Transfer.from)
    var transfersOut: [Transfer] = []
    /// Money moved into this limit from another one.
    @Relationship(deleteRule: .nullify, inverse: \Transfer.to)
    var transfersIn: [Transfer] = []

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

    /// The limit in effect in the month containing `date`, counting a scheduled change.
    func limitAmount(inMonthOf date: Date) -> Decimal {
        guard let scheduledLimit, let scheduledLimitMonth, date >= scheduledLimitMonth else { return limit }
        return scheduledLimit
    }

    /// Makes a scheduled limit the real one once its month has arrived.
    func applyScheduledChange() {
        guard let scheduledLimit, let scheduledLimitMonth, Date.now >= scheduledLimitMonth else { return }
        limit = scheduledLimit
        self.scheduledLimit = nil
        self.scheduledLimitMonth = nil
    }

    enum Status { case upcoming, active, ended }

    var status: Status {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if today < calendar.startOfDay(for: starts) { return .upcoming }
        if let endDate, today > calendar.startOfDay(for: endDate) { return .ended }
        return .active
    }

    /// Ended with nothing left to pay: a bill whose last due date is paid, or a limit that just ran its course.
    var isFinished: Bool {
        guard status == .ended, let endDate else { return false }
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
        guard let lastDue = dueDates(in: DateInterval(start: starts, end: max(starts, end))).last else { return true }
        return remaining(in: period(containing: lastDue)) <= 0
    }

    /// The stretch of time whose spending counts against the limit right now.
    var currentPeriod: DateInterval { period(containing: .now) }

    /// The stretch of time whose spending counts against the limit on `date`. One-time limits have just the one.
    func period(containing date: Date) -> DateInterval {
        let calendar = Calendar.current
        let component: Calendar.Component
        switch frequency {
        case .once:
            let start = calendar.startOfDay(for: starts)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate ?? starts)) ?? start
            return DateInterval(start: start, end: max(start, end))
        case .biweekly:
            // Two-week cycles counted from the start date.
            let anchor = calendar.startOfDay(for: starts)
            let days = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day ?? 0
            let cycle = Int((Double(days) / 14).rounded(.down))
            let start = calendar.date(byAdding: .day, value: cycle * 14, to: anchor) ?? anchor
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 14, to: start) ?? start)
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        }
        return calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 0)
    }

    /// The period `count` periods after the current one, like next month's for 1.
    func period(after count: Int) -> DateInterval {
        (0..<max(count, 0)).reduce(currentPeriod) { period, _ in self.period(containing: period.end) }
    }

    /// Monthly and every-2-weeks limits can be paid in advance for a later period, like next month's loan.
    var canPayAhead: Bool { frequency == .monthly || frequency == .biweekly }

    /// A period in words: "November" (with the year when it isn't this year), "Nov 14 – Nov 27" for
    /// every-2-weeks limits, or the day of a one-time one.
    func title(of period: DateInterval) -> String {
        let isThisYear = Calendar.current.isDate(period.start, equalTo: .now, toGranularity: .year)
        switch frequency {
        case .biweekly:
            let day = Date.FormatStyle.dateTime.month(.abbreviated).day()
            return "\(period.start.formatted(day)) – \(period.end.addingTimeInterval(-1).formatted(day))"
        case .once:
            return period.start.formatted(isThisYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
        default:
            return period.start.formatted(isThisYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
        }
    }

    /// How many periods from now the first later one that still needs paying is, like 2 when next month
    /// was already paid in advance; nil when none does before the end date.
    var nextUnpaidPeriodsAhead: Int? { (1...24).first { remaining(in: period(after: $0)) > 0 } }

    /// What can be paid early: the next unpaid period of a monthly or every-2-weeks limit, or a one-time
    /// one that hasn't come yet. Nil for anything ended, fully paid, or that resets too often.
    var earlyPaymentPeriod: DateInterval? {
        guard status != .ended, limit > 0 else { return nil }
        if frequency == .once {
            return status == .upcoming && remaining(in: currentPeriod) > 0 ? currentPeriod : nil
        }
        return canPayAhead ? nextUnpaidPeriodsAhead.map { period(after: $0) } : nil
    }

    /// Several periods in a row in words: "October – December", or "3 periods from Oct 1" for every-2-weeks limits.
    func title(of periods: [DateInterval]) -> String {
        guard let first = periods.first, let last = periods.last, periods.count > 1 else { return periods.first.map { title(of: $0) } ?? "" }
        if frequency == .biweekly {
            return "\(periods.count) periods from \(first.start.formatted(.dateTime.month(.abbreviated).day()))"
        }
        let sameYear = Calendar.current.isDate(first.start, equalTo: last.start, toGranularity: .year)
        return "\(sameYear ? first.start.formatted(.dateTime.month(.wide)) : title(of: first)) – \(title(of: last))"
    }

    /// Logs `amount` paid in advance for `periods`, one expense per period so each counts where it belongs.
    /// Each period gets what it still needs, in order, and the last one gets whatever is left.
    @discardableResult
    func payAhead(_ amount: Decimal, for periods: [DateInterval], note: String, date: Date?, in context: ModelContext) -> [SpendLog] {
        var left = amount
        return periods.enumerated().compactMap { index, period in
            let portion = index == periods.count - 1 ? left : min(left, max(remaining(in: period), 0))
            left -= portion
            guard portion > 0 else { return nil }
            let log = SpendLog(amount: portion, note: note, date: date, category: self)
            log.paidAheadFor = period.start
            context.insert(log)
            return log
        }
    }

    /// Finishes phrases like "₱200 left in Food ___".
    var periodName: String {
        switch frequency {
        case .once: "overall"
        case .daily: "today"
        case .weekly: "this week"
        case .biweekly: "these 2 weeks"
        case .monthly: "this month"
        }
    }

    func isInCurrentPeriod(_ date: Date) -> Bool {
        let period = currentPeriod
        return date >= period.start && date < period.end
    }

    /// Expenses counted in `period`, including ones paid ahead for it.
    func spent(in period: DateInterval) -> Decimal {
        logs.filter { $0.countedDate >= period.start && $0.countedDate < period.end }.reduce(0) { $0 + $1.amount }
    }

    var spentThisPeriod: Decimal { spent(in: currentPeriod) }

    /// Money moved in minus money moved out, counting transfers made in `period`.
    func transferred(in period: DateInterval) -> Decimal {
        let isIn = { (transfer: Transfer) in transfer.createdAt >= period.start && transfer.createdAt < period.end }
        return transfersIn.filter(isIn).reduce(0) { $0 + $1.amount } - transfersOut.filter(isIn).reduce(0) { $0 + $1.amount }
    }

    var transferredThisPeriod: Decimal { transferred(in: currentPeriod) }

    /// What `period` allows before transfers; nothing before the start date or after the end date. A
    /// monthly bill due on several days needs its amount for each of that month's due dates.
    func limit(for period: DateInterval) -> Decimal {
        let calendar = Calendar.current
        let lastDay = endDate.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
        guard period.end > calendar.startOfDay(for: starts), period.start < lastDay ?? .distantFuture else { return 0 }
        let amount = limitAmount(inMonthOf: period.start)
        return frequency == .monthly && dueDays.count > 1 ? amount * Decimal(max(dueDates(in: period).count, 1)) : amount
    }

    var periodLimit: Decimal { limit(for: currentPeriod) }

    /// The period's limit plus whatever was moved in (or minus what was moved out) this period.
    var availableThisPeriod: Decimal { periodLimit + transferredThisPeriod }

    func remaining(in period: DateInterval) -> Decimal {
        limit(for: period) + transferred(in: period) - spent(in: period)
    }

    var remainingThisPeriod: Decimal { remaining(in: currentPeriod) }

    /// How much this limit adds up to within the current month, so daily and weekly limits
    /// can be compared with monthly income.
    var limitThisMonth: Decimal { limit(inMonthOf: .now) }

    /// How much this limit adds up to within the month containing `date`; zero if it isn't active then.
    func limit(inMonthOf date: Date) -> Decimal {
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: date) else { return limit }
        let activeStart = max(month.start, calendar.startOfDay(for: starts))
        let activeEnd = endDate.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
            .map { min($0, month.end) } ?? month.end
        guard activeStart < activeEnd else { return 0 }
        let activeDays = Decimal(calendar.dateComponents([.day], from: activeStart, to: activeEnd).day ?? 0)
        let amount = limitAmount(inMonthOf: month.start)
        switch frequency {
        case .once: return amount
        case .monthly: return dueDays.count > 1 ? amount * Decimal(max(dueDates(in: month).count, 1)) : amount
        case .daily: return amount * activeDays
        case .weekly: return amount * activeDays / 7
        // A bill counts its actual due dates that month; a spending limit its share of the days.
        case .biweekly: return dueDay != nil ? amount * Decimal(dueDates(in: month).count) : amount * activeDays / 14
        }
    }

    /// What's still unspent of `limitThisMonth`. Ended limits have nothing left to spend.
    var remainingThisMonth: Decimal {
        guard status != .ended, limitThisMonth > 0 else { return 0 }
        if frequency == .once { return remainingThisPeriod }
        let isThisMonth = { (date: Date) in Calendar.current.isDate(date, equalTo: .now, toGranularity: .month) }
        let spent = logs.filter { isThisMonth($0.countedDate) }.reduce(0) { $0 + $1.amount }
        let transferred = transfersIn.filter { isThisMonth($0.createdAt) }.reduce(0) { $0 + $1.amount }
            - transfersOut.filter { isThisMonth($0.createdAt) }.reduce(0) { $0 + $1.amount }
        return limitThisMonth + transferred - spent
    }

    /// Days of the month a monthly bill is due, in order; empty for limits that aren't bills.
    var dueDays: [Int] {
        get { dueDay.map { [$0] + (moreDueDays ?? []) } ?? [] }
        set {
            let days = Set(newValue).sorted()
            dueDay = days.first
            moreDueDays = days.count > 1 ? Array(days.dropFirst()) : nil
        }
    }

    /// Due days in words, like "15th and 30th" or "5th and month end".
    static func describe(dueDays: [Int]) -> String {
        let ordinal = NumberFormatter()
        ordinal.numberStyle = .ordinal
        return dueDays.sorted()
            .map { $0 == monthEnd ? "month end" : ordinal.string(from: $0 as NSNumber) ?? "\($0)" }
            .formatted(.list(type: .and))
    }

    /// Every due date within `interval`, in order, up to the end date. Monthly due days count from the
    /// month the limit starts in, so a bill added mid-month can still be due earlier that month.
    func dueDates(in interval: DateInterval) -> [Date] {
        guard dueDay != nil else { return [] }
        let calendar = Calendar.current
        let lastDay = endDate.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
        let end = min(interval.end, lastDay ?? interval.end)
        var dates: [Date] = []
        switch frequency {
        case .monthly:
            let startMonth = calendar.dateInterval(of: .month, for: starts)?.start ?? starts
            let start = max(interval.start, startMonth)
            var month = calendar.dateInterval(of: .month, for: start)?.start ?? start
            while month < end, dates.count < 1000 {
                dates += dueDays.compactMap { monthDay($0, inMonthOf: month) }.filter { $0 >= start && $0 < end }
                guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
                month = next
            }
        case .biweekly:
            let anchor = calendar.startOfDay(for: starts)
            let skipped = max((calendar.dateComponents([.day], from: anchor, to: interval.start).day ?? 0) / 14, 0)
            var cycle = skipped
            while let date = calendar.date(byAdding: .day, value: cycle * 14, to: anchor), date < end, dates.count < 1000 {
                if date >= interval.start { dates.append(date) }
                cycle += 1
            }
        case .once, .daily, .weekly:
            break
        }
        return Set(dates).sorted()
    }

    /// The earliest due date this period that isn't paid yet, and what's left to pay for it. Payments
    /// cover due dates in order; nil once they're all paid, and for limits that aren't bills.
    var unpaidDue: (date: Date, amount: Decimal)? {
        guard status == .active, limit > 0 else { return nil }
        let dues = dueDates(in: currentPeriod)
        let remaining = remainingThisPeriod
        for (index, due) in dues.enumerated() {
            let owedForLater = limit * Decimal(dues.count - 1 - index)
            if remaining > owedForLater { return (due, remaining - owedForLater) }
        }
        return nil
    }

    var unpaidDueDate: Date? { unpaidDue?.date }

    /// Due dates from the start of this period until `end` that still need paying, with what each needs.
    /// Each period's payments, including any made ahead of time, cover its due dates in order.
    func unpaidDues(until end: Date) -> [(date: Date, amount: Decimal)] {
        guard status != .ended, limit > 0, dueDay != nil, canPayAhead else { return [] }
        var period = currentPeriod
        var unpaid: [(date: Date, amount: Decimal)] = []
        while period.start < end, unpaid.count < 1000 {
            let dues = dueDates(in: period)
            let each = limitAmount(inMonthOf: period.start)
            let owed = remaining(in: period)
            var isFirstUnpaid = true
            for (index, due) in dues.enumerated() {
                let owedForLater = each * Decimal(dues.count - 1 - index)
                guard owed > owedForLater else { continue }
                if due < end { unpaid.append((due, isFirstUnpaid ? owed - owedForLater : each)) }
                isFirstUnpaid = false
            }
            period = self.period(containing: period.end)
        }
        return unpaid
    }
}

/// Day `day` of the month containing `date`. A day past the end of a short month (e.g. the 31st in
/// February, or `BudgetCategory.monthEnd`) falls on that month's last day.
func monthDay(_ day: Int, inMonthOf date: Date) -> Date? {
    let calendar = Calendar.current
    guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start,
          let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count
    else { return nil }
    return calendar.date(byAdding: .day, value: min(day, daysInMonth) - 1, to: monthStart)
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
    /// The start of the later period this was paid in advance for, like next month's loan paid today.
    /// Nil for everyday expenses, which count in the period of `effectiveDate`.
    var paidAheadFor: Date?

    init(amount: Decimal, note: String, date: Date?, category: BudgetCategory) {
        self.amount = amount
        self.note = note
        self.date = date
        self.createdAt = .now
        self.category = category
    }

    /// The day the expense counts on: the date the user set, otherwise when it was logged.
    var effectiveDate: Date { date ?? createdAt ?? .distantPast }

    /// The day the expense counts on against its limit: the period it was paid ahead for, otherwise
    /// `effectiveDate`. Income still pays for it on `effectiveDate`, when the money actually left.
    var countedDate: Date { paidAheadFor ?? effectiveDate }

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
    /// Day of the month this income arrives (1–31, or `BudgetCategory.monthEnd`); nil when not set.
    var payDay: Int?
    /// A new monthly amount that takes over from `scheduledAmountMonth` (the first moment of that month),
    /// like a raise from next month. Becomes `amount` once that month arrives.
    var scheduledAmount: Decimal?
    var scheduledAmountMonth: Date?

    init(name: String, amount: Decimal) {
        self.name = name
        self.amount = amount
        self.createdAt = .now
    }

    /// The amount coming in during the month containing `date`, counting a scheduled change.
    func amount(inMonthOf date: Date) -> Decimal {
        guard let scheduledAmount, let scheduledAmountMonth, date >= scheduledAmountMonth else { return amount }
        return scheduledAmount
    }

    /// Makes a scheduled amount the real one once its month has arrived.
    func applyScheduledChange() {
        guard let scheduledAmount, let scheduledAmountMonth, Date.now >= scheduledAmountMonth else { return }
        amount = scheduledAmount
        self.scheduledAmount = nil
        self.scheduledAmountMonth = nil
    }

    /// Pay dates from today through `end`, soonest first.
    func payDates(through end: Date) -> [Date] {
        guard let payDay else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var dates: [Date] = []
        var month = calendar.dateInterval(of: .month, for: today)?.start ?? today
        while month <= end, dates.count < 24 {
            if let date = monthDay(payDay, inMonthOf: month), date >= today, date <= end { dates.append(date) }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return dates
    }

    /// What's left after this month's expenses paid from this income.
    var remainingThisMonth: Decimal {
        amount - fundings
            .filter { $0.log.map { Calendar.current.isDate($0.effectiveDate, equalTo: .now, toGranularity: .month) } ?? false }
            .reduce(0) { $0 + $1.amount }
    }
}

/// Unused money moved from one limit to another, like what's left of Daily Work going to Daily Food.
/// It counts in the period it was made in.
@Model
final class Transfer {
    var amount: Decimal
    var note: String
    var createdAt: Date
    var from: BudgetCategory?
    var to: BudgetCategory?
    /// Kept so the history still reads right after either category is deleted.
    var fromName: String
    var toName: String

    init(amount: Decimal, note: String, from: BudgetCategory, to: BudgetCategory) {
        self.amount = amount
        self.note = note
        self.createdAt = .now
        self.from = from
        self.to = to
        self.fromName = from.name
        self.toName = to.name
    }
}

/// Something to remember, like "Renew car registration", so it doesn't need the Reminders app.
@Model
final class Reminder {
    var title: String
    var notes = ""
    /// When it's due; nil for reminders without a date. Only the day counts unless `hasTime` is on.
    var dueDate: Date?
    var hasTime = false
    var isDone = false
    var completedAt: Date?
    var createdAt: Date

    init(title: String, dueDate: Date? = nil, hasTime: Bool = false) {
        self.title = title
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.createdAt = .now
    }

    /// When its notification goes off: the time set, otherwise 9 AM on the day.
    var alertDate: Date? {
        guard let dueDate else { return nil }
        return hasTime ? dueDate : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate)
    }

    /// Past its time, or for a reminder without a time, past its day, whether done or not.
    var isPastDue: Bool {
        guard let dueDate else { return false }
        return hasTime ? dueDate < .now : dueDate < Calendar.current.startOfDay(for: .now)
    }

    var isOverdue: Bool { !isDone && isPastDue }
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
    case biweekly = "Every 2 Weeks"
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

    /// Every payment has come in: the last payment date is before today.
    var isFinished: Bool {
        (paymentDates.last ?? startDate) < Calendar.current.startOfDay(for: .now)
    }

    /// Every payment date from start to end, in order.
    static func paymentDates(frequency: Frequency, start: Date, end: Date) -> [Date] {
        let component: Calendar.Component
        var step = 1
        switch frequency {
        case .once: return [start]
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .biweekly:
            component = .weekOfYear
            step = 2
        case .monthly: component = .month
        }
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: end)
        var dates: [Date] = []
        // Counting from the start date each time keeps monthly payments on the right day (Jan 31 → Feb 28 → Mar 31).
        while dates.count < 1000,
              let date = calendar.date(byAdding: component, value: dates.count * step, to: start),
              calendar.startOfDay(for: date) <= lastDay {
            dates.append(date)
        }
        return dates
    }
}
