import SwiftUI
import SwiftData

enum Appearance: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Opens Settings from the gear button on any page.
@Observable @MainActor
final class SettingsRouter {
    static let shared = SettingsRouter()
    var isShowing = false
}

/// The gear at the top of each page. Settings has no tab of its own, so the add button fits in the tab bar.
struct SettingsButton: View {
    var body: some View {
        Button("Settings", systemImage: "gearshape") { SettingsRouter.shared.isShowing = true }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("linksExpensesToIncome") private var linksExpenses = false
    @Query private var logs: [SpendLog]
    @State private var isLinkingExpenses = false

    var body: some View {
        let unlinkedCount = logs.filter {
            Calendar.current.isDate($0.effectiveDate, equalTo: .now, toGranularity: .month) && !$0.isLinked
        }.count

        NavigationStack {
            Form {
                Section {
                    Toggle("Link Expenses to Income", isOn: $linksExpenses)
                    if linksExpenses && unlinkedCount > 0 {
                        Button {
                            isLinkingExpenses = true
                        } label: {
                            Label("\(unlinkedCount) expense\(unlinkedCount == 1 ? "" : "s") need\(unlinkedCount == 1 ? "s" : "") an income",
                                  systemImage: "exclamationmark.triangle.fill")
                        }
                        .tint(.orange)
                    }
                } header: {
                    Text("Expenses")
                } footer: {
                    Text("When on, every expense must say which income paid for it, so you can see what's left of each income this month.")
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows your iPhone's Light or Dark Mode setting.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: linksExpenses) { _, isOn in
                if isOn && unlinkedCount > 0 { isLinkingExpenses = true }
            }
            .sheet(isPresented: $isLinkingExpenses) { LinkExpensesSheet() }
        }
    }
}
