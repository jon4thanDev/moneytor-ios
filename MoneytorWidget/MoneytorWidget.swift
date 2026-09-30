import SwiftUI
import WidgetKit

@main
struct MoneytorWidgetBundle: WidgetBundle {
    var body: some Widget {
        BillsWidget()
    }
}

/// Bills that are due or past due, each with a Pay button, and the next money in or out underneath.
struct BillsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BillsWidget", provider: Provider()) { entry in
            BillsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Bills Due")
        .description("See bills that are due or past due and pay them in one tap, plus what's coming up next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    /// Nil until the app has been opened once.
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snapshot: WidgetSnapshot.load() ?? (context.isPreview ? .sample : nil)))
    }

    /// One entry now and one each midnight for a week, so bills move to past due as their day passes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let today = Calendar.current.startOfDay(for: .now)
        let midnights = (1...7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
        let entries = [Entry(date: .now, snapshot: snapshot)] + midnights.map { Entry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

private let accent = Color(red: 0.157, green: 0.690, blue: 0.478)

struct BillsWidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            let due = snapshot.pastDue(on: entry.date)
            let next = snapshot.next(on: entry.date)
            if family == .systemSmall {
                small(due: due, next: next)
            } else {
                full(due: due, next: next, limit: family == .systemLarge ? 5 : 2)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(accent)
                Text("Open Moneytor to see your bills here.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The whole small widget is one tap: it opens the oldest bill's pay screen.
    private func small(due: [WidgetSnapshot.Bill], next: WidgetSnapshot.Event?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let first = due.first {
                Label(due.count == 1 ? "Past due" : "\(due.count) past due", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Text(first.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(first.amount, format: .currency(code: currencyCode))
                    .font(.title3.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Tap to pay")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
            } else {
                Label("All paid", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text("No bills due")
                    .font(.headline)
            }
            Spacer(minLength: 0)
            if let next {
                NextLine(event: next, today: entry.date, isCompact: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(due.first.map(WidgetSnapshot.payURL) ?? WidgetSnapshot.upcomingURL)
    }

    private func full(due: [WidgetSnapshot.Bill], next: WidgetSnapshot.Event?, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if due.isEmpty {
                Label("All bills paid", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                Text("Nothing is due right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Label(due.count == 1 ? "1 bill past due" : "\(due.count) bills past due", systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Spacer()
                    if due.count > limit {
                        Text("+\(due.count - limit) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(due.prefix(limit), id: \.self) { bill in
                    BillRow(bill: bill, today: entry.date)
                }
            }
            Spacer(minLength: 0)
            if let next {
                Divider()
                NextLine(event: next, today: entry.date, isCompact: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetSnapshot.upcomingURL)
    }
}

private struct BillRow: View {
    let bill: WidgetSnapshot.Bill
    let today: Date

    var body: some View {
        let calendar = Calendar.current
        let daysLate = calendar.dateComponents([.day], from: calendar.startOfDay(for: bill.due), to: calendar.startOfDay(for: today)).day ?? 0

        HStack(spacing: 10) {
            Image(systemName: bill.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(daysLate > 0 ? Color.red : Color.orange, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(bill.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(daysLate == 0 ? "Due today" : daysLate == 1 ? "1 day late" : "\(daysLate) days late")
                    .font(.caption2)
                    .foregroundStyle(daysLate > 0 ? .red : .orange)
            }
            Spacer(minLength: 4)
            Text(bill.amount, format: .currency(code: currencyCode))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Link(destination: WidgetSnapshot.payURL(for: bill)) {
                Text("Pay")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(accent, in: Capsule())
            }
        }
    }
}

/// The soonest money in or out, like "Next · Salary +₱20,000 · Oct 15".
private struct NextLine: View {
    let event: WidgetSnapshot.Event
    let today: Date
    let isCompact: Bool

    var body: some View {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: event.date)).day ?? 0
        let when = switch days {
        case 0: "Today"
        case 1: "Tomorrow"
        default: event.date.formatted(.dateTime.month(.abbreviated).day())
        }
        let amount = Text(event.isIncoming ? event.amount : -event.amount,
                          format: .currency(code: currencyCode).sign(strategy: .always()))
            .monospacedDigit()
            .foregroundStyle(event.isIncoming ? accent : .primary)

        if isCompact {
            VStack(alignment: .leading, spacing: 1) {
                Text("Next · \(when)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(event.name).lineLimit(1)
                    Spacer(minLength: 2)
                    amount
                }
                .font(.caption2.weight(.semibold))
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: event.isIncoming ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                    .foregroundStyle(event.isIncoming ? accent : .orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next \(event.isIncoming ? "income" : "bill") · \(when)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(event.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer()
                amount
                    .font(.caption.weight(.semibold))
            }
        }
    }
}

extension WidgetSnapshot {
    /// Shown in the widget gallery before the app has saved anything.
    static let sample: WidgetSnapshot = {
        let today = Calendar.current.startOfDay(for: .now)
        let day = { (offset: Int) in Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today }
        return WidgetSnapshot(
            bills: [
                Bill(id: "", name: "Rent", icon: "house.fill", amount: 8000, due: day(-3)),
                Bill(id: "", name: "Electricity", icon: "bolt.fill", amount: 1850, due: day(0)),
            ],
            events: [Event(name: "Salary", icon: "banknote.fill", amount: 25000, date: day(5), isIncoming: true)]
        )
    }()
}

#Preview(as: .systemMedium) {
    BillsWidget()
} timeline: {
    Entry(date: .now, snapshot: .sample)
}
