import SwiftUI

/// Money text field that groups digits as you type (e.g. 1,234,567.89).
struct MoneyField: View {
    @Binding var value: Decimal?
    @State private var text = ""

    private static let decimalSeparator = Locale.current.decimalSeparator ?? "."
    private static let groupingSeparator = Locale.current.groupingSeparator ?? ","

    var body: some View {
        TextField("0", text: $text)
            .keyboardType(.decimalPad)
            .onChange(of: text) { _, newText in
                let formatted = Self.format(newText)
                if formatted != newText { text = formatted }
                value = Self.parse(formatted)
            }
            .onChange(of: value, initial: true) { _, newValue in
                guard newValue != Self.parse(text) else { return }
                text = newValue.map { Self.format(NSDecimalNumber(decimal: $0).description(withLocale: Locale.current)) } ?? ""
            }
    }

    private static func parse(_ text: String) -> Decimal? {
        Decimal(string: text.replacingOccurrences(of: groupingSeparator, with: ""), locale: .current)
    }

    private static func format(_ input: String) -> String {
        let allowed = input.filter { $0.isNumber || String($0) == decimalSeparator }
        let parts = allowed.split(separator: Character(decimalSeparator), maxSplits: 1, omittingEmptySubsequences: false)
        let hasDecimal = parts.count > 1

        var intDigits = String(parts.first ?? "").drop { $0 == "0" }
        if intDigits.isEmpty && (hasDecimal || allowed.first == "0") { intDigits = "0" }

        var grouped = ""
        for (index, digit) in intDigits.enumerated() {
            if index > 0 && (intDigits.count - index) % 3 == 0 { grouped += groupingSeparator }
            grouped.append(digit)
        }

        guard hasDecimal else { return grouped }
        let fraction = parts[1].filter(\.isNumber).prefix(2)
        return grouped + decimalSeparator + fraction
    }
}
