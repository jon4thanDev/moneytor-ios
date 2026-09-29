import SwiftUI
import UIKit

/// Money field that opens a calculator keypad instead of the system keyboard, so an amount like
/// 120 + 85 can be worked out right here. `value` follows the answer as you type.
struct CalculatorField: UIViewRepresentable {
    @Binding var value: Decimal?
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var focusesOnAppear = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> CalculatorTextField {
        let coordinator = context.coordinator
        let field = CalculatorTextField()
        field.focusesOnAppear = focusesOnAppear
        field.placeholder = "0"
        field.font = font
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 17
        field.delegate = coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let keypad = UIHostingController(rootView: CalculatorKeypad(model: coordinator.model) { [weak coordinator] key in
            coordinator?.press(key)
        })
        keypad.safeAreaRegions = []
        keypad.view.backgroundColor = .clear
        keypad.view.translatesAutoresizingMaskIntoConstraints = false
        // A fixed height: sizing from the SwiftUI content can measure zero before the first layout,
        // which leaves the keypad invisible. Self-sizing then adds the home indicator area below.
        let inputView = KeypadInputView(
            frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: CalculatorKeypad.height),
            inputViewStyle: .keyboard
        )
        inputView.allowsSelfSizing = true
        inputView.addSubview(keypad.view)
        let height = keypad.view.heightAnchor.constraint(equalToConstant: CalculatorKeypad.height)
        height.priority = .init(999)
        NSLayoutConstraint.activate([
            height,
            keypad.view.topAnchor.constraint(equalTo: inputView.topAnchor),
            keypad.view.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            keypad.view.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            keypad.view.bottomAnchor.constraint(equalTo: inputView.safeAreaLayoutGuide.bottomAnchor),
        ])
        field.inputView = inputView

        coordinator.field = field
        coordinator.keypad = keypad
        return field
    }

    /// Fills the row so tapping anywhere beside the currency symbol opens the keypad.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CalculatorTextField, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? uiView.intrinsicContentSize.width
        return CGSize(width: width, height: max(uiView.intrinsicContentSize.height, 44))
    }

    func updateUIView(_ field: CalculatorTextField, context: Context) {
        context.coordinator.parent = self
        let model = context.coordinator.model
        // Only an amount set from outside (like a prefilled bill) replaces what's typed.
        if value != model.result {
            model.expression = value.map { "\($0)" } ?? ""
            field.text = model.displayText
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CalculatorField
        let model = CalculatorModel()
        weak var field: UITextField?
        var keypad: UIHostingController<CalculatorKeypad>?

        init(_ parent: CalculatorField) {
            self.parent = parent
        }

        func press(_ key: CalculatorKey) {
            UIDevice.current.playInputClick()
            if key == .done {
                field?.resignFirstResponder()
                return
            }
            model.press(key)
            sync()
        }

        private func sync() {
            field?.text = model.displayText
            parent.value = model.result
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            model.showAnswer()
            sync()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
        }

        /// Typing on a hardware keyboard or pasting goes through the calculator too.
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty { model.press(.backspace) }
            for character in string {
                switch character {
                case "0"..."9": model.press(.digit(String(character)))
                case ".", Character(Locale.current.decimalSeparator ?? "."): model.press(.decimalPoint)
                case "+": model.press(.operation("+"))
                case "-", "−": model.press(.operation("−"))
                case "*", "x", "×": model.press(.operation("×"))
                case "/", "÷": model.press(.operation("÷"))
                default: break
                }
            }
            sync()
            return false
        }
    }
}

final class CalculatorTextField: UITextField {
    var focusesOnAppear = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard focusesOnAppear, window != nil else { return }
        focusesOnAppear = false
        DispatchQueue.main.async { self.becomeFirstResponder() }
    }
}

/// Plays the standard keyboard click (when enabled in Settings) as keys are tapped.
private final class KeypadInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

enum CalculatorKey: Hashable {
    /// "0" through "9", or "00".
    case digit(String)
    case decimalPoint
    /// One of + − × ÷.
    case operation(Character)
    case backspace
    case clear
    case done
}

@Observable
final class CalculatorModel {
    /// Numbers use "." and operators are + − × ÷, like "1200+50.5×2".
    var expression = ""

    private static let operators: Set<Character> = ["+", "−", "×", "÷"]

    var hasOperation: Bool { expression.contains { Self.operators.contains($0) } }

    /// The answer rounded to cents, with × and ÷ before + and −. A trailing operator is ignored;
    /// nil when there's nothing to work out or it divides by zero.
    var result: Decimal? {
        var numbers: [Decimal] = []
        var operations: [Character] = []
        var number = ""
        for character in expression {
            if Self.operators.contains(character) {
                guard let value = Decimal(string: number) else { return nil }
                numbers.append(value)
                operations.append(character)
                number = ""
            } else {
                number.append(character)
            }
        }
        if let value = Decimal(string: number) {
            numbers.append(value)
        } else if !operations.isEmpty {
            operations.removeLast()
        }
        guard let first = numbers.first else { return nil }

        var terms = [first]
        var signs: [Character] = []
        for (operation, value) in zip(operations, numbers.dropFirst()) {
            switch operation {
            case "×": terms[terms.count - 1] *= value
            case "÷":
                guard value != 0 else { return nil }
                terms[terms.count - 1] /= value
            default:
                terms.append(value)
                signs.append(operation)
            }
        }
        var total = terms[0]
        for (sign, term) in zip(signs, terms.dropFirst()) {
            total += sign == "+" ? term : -term
        }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &total, 2, .plain)
        return rounded
    }

    /// The expression with grouped digits and spaced operators, like "1,200 + 50".
    var displayText: String {
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let groupingSeparator = Locale.current.groupingSeparator ?? ","
        var text = ""
        var number = ""
        // The trailing "=" flushes the last number.
        for character in expression + "=" {
            guard Self.operators.contains(character) || character == "=" else {
                number.append(character)
                continue
            }
            let parts = number.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let integer = parts.first ?? ""
            if integer.hasPrefix("-") { text += "-" }
            let digits = integer.drop { $0 == "-" }
            for (index, digit) in digits.enumerated() {
                if index > 0 && (digits.count - index) % 3 == 0 { text += groupingSeparator }
                text.append(digit)
            }
            if parts.count > 1 { text += decimalSeparator + parts[1] }
            if character != "=" { text += " \(character) " }
            number = ""
        }
        return text
    }

    func press(_ key: CalculatorKey) {
        let currentNumber = expression.split(omittingEmptySubsequences: false) { Self.operators.contains($0) }.last ?? ""
        switch key {
        case .digit(let digits):
            if let point = currentNumber.firstIndex(of: ".") {
                let room = 2 - currentNumber[currentNumber.index(after: point)...].count
                expression += digits.prefix(max(room, 0))
            } else if currentNumber == "0" {
                if digits != "0" && digits != "00" {
                    expression.removeLast()
                    expression += digits
                }
            } else if currentNumber.isEmpty && digits == "00" {
                expression += "0"
            } else if currentNumber.count + digits.count <= 12 {
                expression += digits
            }
        case .decimalPoint:
            if currentNumber.isEmpty {
                expression += "0."
            } else if !currentNumber.contains(".") {
                expression += "."
            }
        case .operation(let operation):
            guard let last = expression.last, last != "-" else { return }
            // A second operator in a row replaces the first.
            if Self.operators.contains(last) || last == "." { expression.removeLast() }
            expression.append(operation)
        case .backspace:
            if !expression.isEmpty { expression.removeLast() }
        case .clear:
            expression = ""
        case .done:
            break
        }
    }

    /// Replaces a calculation like "120+85" with its answer, "205".
    func showAnswer() {
        guard hasOperation else { return }
        expression = result.map { "\($0)" } ?? ""
    }
}

struct CalculatorKeypad: View {
    let model: CalculatorModel
    let onKey: (CalculatorKey) -> Void

    private static let spacing: CGFloat = 6
    private static let keyHeight: CGFloat = 46
    private static let resultHeight: CGFloat = 24
    /// Padding, the result line, and five rows of keys.
    static let height = spacing * 2 + resultHeight + spacing + keyHeight * 5 + spacing * 4

    var body: some View {
        VStack(spacing: Self.spacing) {
            // Always takes its space so the keypad doesn't change height while typing.
            Text(model.hasOperation ? model.result.map { "= \($0.formatted(.currency(code: currencyCode)))" } ?? "Can't divide by zero" : " ")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(model.hasOperation && model.result == nil ? .red : .secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 8)
                .frame(height: Self.resultHeight)

            HStack(spacing: Self.spacing) {
                VStack(spacing: Self.spacing) {
                    row(.clear, .backspace, .operation("÷"))
                    row(.digit("7"), .digit("8"), .digit("9"))
                    row(.digit("4"), .digit("5"), .digit("6"))
                    row(.digit("1"), .digit("2"), .digit("3"))
                    row(.digit("00"), .digit("0"), .decimalPoint)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: Self.spacing) {
                    key(.operation("×"))
                    key(.operation("−"))
                    key(.operation("+"))
                    key(.done, height: Self.keyHeight * 2 + Self.spacing)
                }
                .frame(width: 80)
            }
        }
        .padding(Self.spacing)
    }

    private func row(_ keys: CalculatorKey...) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(keys, id: \.self) { key($0) }
        }
    }

    private func key(_ key: CalculatorKey, height: CGFloat? = nil) -> some View {
        // Matches the system keyboard: white (or light grey in dark mode) number keys, darker function keys.
        let fill: Color = switch key {
        case .digit, .decimalPoint:
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white })
        case .done:
            .accentColor
        default:
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1) })
        }
        let foreground: Color = switch key {
        case .done: .white
        case .operation: .accentColor
        default: .primary
        }
        let accessibilityName = switch key {
        case .digit(let digits): digits
        case .decimalPoint: "Decimal point"
        case .operation("+"): "Plus"
        case .operation("−"): "Minus"
        case .operation("×"): "Times"
        case .operation: "Divided by"
        case .backspace: "Delete"
        case .clear: "Clear all"
        case .done: "Done"
        }

        return Button { onKey(key) } label: {
            switch key {
            case .digit(let digits):
                Text(digits).font(.system(size: 24))
            case .decimalPoint:
                Text(Locale.current.decimalSeparator ?? ".").font(.system(size: 24, weight: .semibold))
            case .operation(let operation):
                let symbol = switch operation {
                case "+": "plus"
                case "−": "minus"
                case "×": "multiply"
                default: "divide"
                }
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
            case .backspace:
                Image(systemName: "delete.left").font(.system(size: 20))
            case .clear:
                Text("AC").font(.system(size: 18, weight: .medium))
            case .done:
                Text("Done").font(.system(size: 18, weight: .semibold))
            }
        }
        .buttonStyle(KeyStyle(fill: fill, foreground: foreground))
        .frame(height: height ?? Self.keyHeight)
        .accessibilityLabel(accessibilityName)
    }
}

private struct KeyStyle: ButtonStyle {
    let fill: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(foreground)
            .background(fill.opacity(configuration.isPressed ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            .contentShape(Rectangle())
    }
}
