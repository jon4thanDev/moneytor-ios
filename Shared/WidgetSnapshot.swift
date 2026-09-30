import Foundation

let currencyCode = Locale.current.currency?.identifier ?? "USD"

/// What the home-screen widget shows. The app saves it to the shared App Group whenever bills or
/// income change, so the widget never has to open the app's database.
struct WidgetSnapshot: Codable {
    static let appGroup = "group.com.tan.moneytor.app"
    private static let key = "widgetSnapshot"

    struct Bill: Codable, Hashable {
        /// The category's encoded ID, used in the Pay link.
        var id: String
        var name: String
        var icon: String
        /// What's left to pay.
        var amount: Decimal
        var due: Date
    }

    struct Event: Codable, Hashable {
        var name: String
        var icon: String
        var amount: Decimal
        var date: Date
        var isIncoming: Bool
    }

    /// Unpaid bills, including ones not due yet, so the widget can move them to past due as days pass.
    var bills: [Bill]
    /// Money coming in and bills going out over the next two months, soonest first.
    var events: [Event]

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }

    /// Bills due on or before `day`, oldest first.
    func pastDue(on day: Date) -> [Bill] {
        let day = Calendar.current.startOfDay(for: day)
        return bills.filter { Calendar.current.startOfDay(for: $0.due) <= day }
    }

    /// The soonest money in or out from `day` on, leaving out bills already shown as due.
    func next(on day: Date) -> Event? {
        let day = Calendar.current.startOfDay(for: day)
        return events.first {
            let date = Calendar.current.startOfDay(for: $0.date)
            return $0.isIncoming ? date >= day : date > day
        }
    }

    /// Opens the app to pay this bill.
    static func payURL(for bill: Bill) -> URL {
        var components = URLComponents()
        components.scheme = "moneytor"
        components.host = "pay"
        components.queryItems = [URLQueryItem(name: "id", value: bill.id)]
        return components.url ?? upcomingURL
    }

    static let upcomingURL = URL(string: "moneytor://upcoming")!
}
