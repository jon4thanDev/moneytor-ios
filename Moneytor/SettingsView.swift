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

struct SettingsView: View {
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
            .onChange(of: linksExpenses) { _, isOn in
                if isOn && unlinkedCount > 0 { isLinkingExpenses = true }
            }
            .sheet(isPresented: $isLinkingExpenses) { LinkExpensesSheet() }
        }
    }
}
