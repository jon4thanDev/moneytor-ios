import AppIntents
import UIKit

/// Whether the Assistant sheet is showing, so the tab buttons and the Open Assistant shortcut share one sheet.
@Observable @MainActor
final class AssistantRouter {
    static let shared = AssistantRouter()
    var isShowing = false
}

/// Opens the app straight to the Assistant. Shows up in Shortcuts, so it can be put on Back Tap or the Action Button.
struct OpenAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Assistant"
    static let description = IntentDescription("Opens Moneytor straight to the Assistant, ready to log an expense.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let router = AssistantRouter.shared
        guard !router.isShowing else { return .result() }
        // SwiftUI can't show the Assistant over another open sheet (like Add Expense), so close that first.
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        if let root, root.presentedViewController != nil {
            root.dismiss(animated: false) { router.isShowing = true }
        } else {
            router.isShowing = true
        }
        return .result()
    }
}

struct MoneytorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAssistantIntent(),
            phrases: [
                "Open \(.applicationName) Assistant",
                "Log an expense in \(.applicationName)",
                "Ask \(.applicationName)"
            ],
            shortTitle: "Assistant",
            systemImageName: "sparkles"
        )
    }
}
