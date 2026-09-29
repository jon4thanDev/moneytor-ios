import SwiftData
import SwiftUI
import UserNotifications

/// Local notifications for bills that are due or overdue and not fully paid yet.
@MainActor
enum BillReminders {
    nonisolated private static let prefix = "bill."

    /// Replaces all bill notifications to match the current bills. Safe to call often.
    static func refresh(for categories: [BudgetCategory]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var dueCount = 0
        let requests = categories.compactMap { category -> UNNotificationRequest? in
            guard let due = category.unpaidDueDate else { return nil }
            let isDue = calendar.startOfDay(for: due) <= today
            if isDue { dueCount += 1 }

            let content = UNMutableNotificationContent()
            // Due and overdue reminders repeat daily, so their wording has to stay true on later days.
            content.title = isDue ? "\(category.name) isn't paid yet" : "\(category.name) is due today"
            content.body = "Due \(due.formatted(.dateTime.month(.abbreviated).day())) · \(category.remainingThisPeriod.formatted(.currency(code: currencyCode))) left to pay. Tap to pay it."
            content.sound = .default
            content.threadIdentifier = "bills"

            var components = isDue ? DateComponents() : calendar.dateComponents([.year, .month, .day], from: due)
            components.hour = 9
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: isDue)
            let id = (try? JSONEncoder().encode(category.persistentModelID))?.base64EncodedString() ?? ""
            return UNNotificationRequest(identifier: prefix + id, content: content, trigger: trigger)
        }

        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            // Clear reminders already on screen for bills that have since been paid.
            let current = Set(requests.map(\.identifier))
            let stale = await center.deliveredNotifications().map(\.request.identifier)
                .filter { $0.hasPrefix(prefix) && !current.contains($0) }
            center.removeDeliveredNotifications(withIdentifiers: stale)

            guard !requests.isEmpty, (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else {
                try? await center.setBadgeCount(0)
                return
            }
            for request in requests { try? await center.add(request) }
            try? await center.setBadgeCount(dueCount)
        }
    }

    nonisolated static func categoryID(fromNotification identifier: String) -> PersistentIdentifier? {
        guard identifier.hasPrefix(prefix), let data = Data(base64Encoded: String(identifier.dropFirst(prefix.count))) else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }
}

/// Hands the bill from a tapped notification to the UI.
@Observable @MainActor
final class BillRouter {
    static let shared = BillRouter()
    var openedCategoryID: PersistentIdentifier?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Show reminders even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = BillReminders.categoryID(fromNotification: response.notification.request.identifier)
        Task { @MainActor in
            BillRouter.shared.openedCategoryID = id
            completionHandler()
        }
    }
}
