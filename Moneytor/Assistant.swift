import Foundation
import SwiftData

/// What a single message asks for, produced by `CommandParser` or by `LocalModel`.
/// Fields are nil when the message doesn't mention them.
struct Interpretation: Decodable {
    enum Intent: String, Decodable {
        case spend, income, remaining, confirm, cancel
        /// Nothing to do with the user's budget, like politics or homework.
        case offTopic = "offtopic"
        /// "If I spend 500 on food, how much is left?" Answered without logging anything.
        case whatIf = "whatif"
        /// Plain arithmetic, like "what's 1500 minus 320?"
        case calculate
        /// Changing a category's limit or an income's amount or name, like "change rent to 6000 next month".
        case edit
        case other = "none"
    }

    var intent: Intent?
    var amount: Decimal?
    var category: String?
    var note: String?
    var daysAgo: Int?
    var source: String?
    /// What an off-topic message is about, like "politics".
    var topic: String?
    /// How `amount` was worked out when the message had a calculation in it, like "150 + 200".
    var working: String?
    /// An income named in full, like "Salary".
    var income: String?
    /// Categories and incomes sharing a word with the message when none was named in full,
    /// like "Daily Food" and "Daily Work" for "daily". The assistant asks which one was meant.
    var categoryMatches: [String]?
    var incomeMatches: [String]?

    enum Total: String, Decodable { case spent, left, limit, income }
    /// Asks for a total across the whole budget, like "total expenses this month", rather than one category.
    var total: Total?
    /// Names to leave out of the total, from "except for Daily Food".
    var excluded: [String]?
    /// Months from this one, from "next month" (1), "the month after next" (2), or "from November".
    var monthsAhead: Int?
    /// A new name, from "rename Food to Groceries".
    var newName: String?
    /// How much to raise (positive) or lower (negative) an amount, from "increase rent by 500".
    var amountChange: Decimal?
}

/// Rule-based understanding of short English budgeting messages, e.g. "spent 200 on lunch yesterday".
enum CommandParser {
    private static let spendWords = ["spent", "spend", "spending", "paid", "pay", "bought", "buy", "cost", "costs",
                                     "deduct", "expense", "purchase", "purchased", "used", "log", "put"]
    private static let incomeWords = ["income", "earned", "earn", "earning", "received", "receive", "got paid", "paid me", "wage", "wages"]
    private static let remainingWords = ["left", "remaining", "remain", "how much", "balance", "summary", "status"]
    private static let confirmWords = ["yes", "yep", "yeah", "yup", "confirm", "ok", "okay", "sure", "correct", "go ahead", "do it", "save"]
    private static let cancelWords = ["cancel", "no", "nope", "never mind", "nevermind", "forget it", "stop"]
    private static let currencyWords: Set<String> = ["peso", "pesos", "php", "dollar", "dollars", "buck", "bucks"]
    /// Dropped from the start and end of what's left over when building a note or income name.
    private static let edgeWords: Set<String> = ["i", "i've", "ive", "my", "is", "was", "on", "for", "at", "in", "to", "the", "a", "an",
                                                 "from", "of", "and", "it", "about", "around", "just", "per", "month", "monthly",
                                                 "every", "each", "got", "me", "add", "new", "please", "worth", "total",
                                                 "make", "change", "actually", "instead", "that", "be", "under",
                                                 "create", "record", "set", "up", "called", "named", "as", "with",
                                                 "amount", "value", "an", "source"]
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let editWords = ["change", "edit", "update", "rename", "set", "adjust", "modify",
                                    "increase", "decrease", "raise", "lower", "reduce", "cut", "bump"]
    private static let monthNames = ["january", "february", "march", "april", "may", "june",
                                     "july", "august", "september", "october", "november", "december"]
    /// Subjects the assistant can't help with. Only checked when a message has nothing budget-related in it,
    /// so "spent 500 on school" still logs. Most specific first.
    private static let offTopics: [(name: String, keywords: [String])] = [
        ("corruption", ["corruption", "corrupt", "bribe", "bribery", "kickback", "kickbacks", "plunder", "graft",
                        "pork barrel", "money laundering"]),
        ("politics", ["politics", "political", "politician", "politicians", "president", "senator", "senate", "congress",
                      "mayor", "governor", "election", "elections", "vote", "voting", "government", "campaign", "democracy"]),
        ("legal questions", ["law", "laws", "legal", "lawyer", "attorney", "court", "lawsuit", "sue", "constitution",
                             "crime", "illegal", "arrest", "police", "jail"]),
        ("school or education topics", ["education", "homework", "assignment", "essay", "exam", "thesis", "quiz", "math",
                                        "science", "history", "school", "university", "college", "teacher", "lesson"]),
        ("religion", ["religion", "religious", "god", "church", "bible", "pray", "prayer", "faith"]),
        ("health advice", ["symptom", "symptoms", "diagnosis", "diagnose", "disease", "illness", "cure", "treatment"]),
        ("investing advice", ["stock", "stocks", "crypto", "bitcoin", "invest", "investing", "investment", "trading", "forex"]),
        ("news or sports", ["news", "weather", "basketball", "nba", "football", "soccer", "sports"]),
        ("coding", ["code", "coding", "programming", "python", "javascript"]),
        ("jokes or stories", ["joke", "jokes", "poem", "story", "song", "riddle"]),
    ]
    /// Everyday words that point to a category whose name contains the key.
    private static let categoryHints: [String: [String]] = [
        "food": ["lunch", "dinner", "breakfast", "snack", "snacks", "coffee", "meal", "restaurant", "ate", "drinks"],
        "grocer": ["groceries", "grocery", "supermarket", "market"],
        "transport": ["grab", "taxi", "uber", "bus", "train", "jeep", "jeepney", "gas", "fuel", "fare", "parking", "toll", "commute"],
        "bill": ["electric", "electricity", "water", "internet", "wifi", "phone", "rent", "utilities"],
        "shop": ["clothes", "shoes", "shirt", "mall"],
        "health": ["medicine", "doctor", "pharmacy", "hospital", "vitamins", "dentist"],
        "entertain": ["movie", "movies", "netflix", "games", "concert"],
        "wi-fi": ["wifi", "internet"],
        "electric": ["meralco", "power"],
        "subscription": ["netflix", "spotify", "youtube", "disney", "icloud", "chatgpt"],
        "data": ["load", "mobile data"],
        "travel": ["flight", "hotel", "trip"],
        "work": ["office"],
        "pet": ["vet", "pet"],
        "date": ["date night"],
    ]

    /// Keyboard mashing like "aihjsdasdj" or "sdfghj": no numbers, and every word has a run of consonants,
    /// no vowels, or one letter held down. The user's own names never count, however they're spelled.
    static func isGibberish(_ text: String, names: [String]) -> Bool {
        let lower = text.lowercased()
        guard !lower.contains(where: \.isNumber) else { return false }
        let nameWords = Set(names.flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter }) })
        let words = lower.split(whereSeparator: { !$0.isLetter }).filter { !nameWords.contains($0) }
        return !words.isEmpty && words.allSatisfy { word in
            guard word.count >= 4 else { return false }
            let vowels = "aeiouy"
            var longestRun = 0
            var run = 0
            // Pairs like "th" and "ng" are one sound, so "strength" doesn't count as a run of four.
            for letter in word.replacingOccurrences(of: "th|ch|sh|ph|ng|ck|gh|wh", with: "x", options: .regularExpression) {
                run = vowels.contains(letter) ? 0 : run + 1
                longestRun = max(longestRun, run)
            }
            return longestRun >= 4 || !word.contains(where: vowels.contains) || word.range(of: #"(.)\1{3}"#, options: .regularExpression) != nil
        }
    }

    /// Letters to add, remove, change, or swap with a neighbour to turn one word into the other.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }

    static func parse(_ text: String, categoryNames: [String], incomeNames: [String] = []) -> Interpretation {
        let lower = text.lowercased()
        func mentions(_ phrases: [String]) -> Bool {
            phrases.contains { lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: $0))\\b", options: .regularExpression) != nil }
        }

        var result = Interpretation()
        var rest = text
        let isHypothetical = mentions(["if i", "if we", "what if", "suppose", "supposing", "assuming", "would i have",
                                       "will i have", "would be left", "will be left", "would i still", "afford"])

        // "for 5 days" in a what-if multiplies the amount. Taken out first so the 5 isn't read as the amount.
        var count: (number: Int, unit: String)?
        if isHypothetical, let match = rest.firstMatch(of: #/\bfor\s+(?:the\s+next\s+)?(\d+)\s+(days?|weeks?|months?|times)\b/#.ignoresCase()),
           let number = Int(match.output.1) {
            count = (number, match.output.2.lowercased())
            rest.replaceSubrange(match.range, with: " ")
        }

        // The month a change starts. Taken out before amounts so the 3 in "in 3 months" isn't read as one.
        let calendar = Calendar.current
        let relativeMonths: [(pattern: String, months: Int)] = [
            (#"\b(?:the\s+)?month\s+after\s+next\b|\bnext\s+next\s+month\b"#, 2),
            (#"\bnext\s+month\b"#, 1),
            (#"\bthis\s+month\b|\bright\s+now\b"#, 0),
            (#"\b(?:last|previous)\s+month\b"#, -1),
        ]
        for (pattern, months) in relativeMonths {
            if let range = rest.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                result.monthsAhead = months
                rest.replaceSubrange(range, with: " ")
                break
            }
        }
        if result.monthsAhead == nil, let match = rest.firstMatch(of: #/\bin\s+(\d+)\s+months?\b|\b(\d+)\s+months?\s+from\s+now\b/#.ignoresCase()),
           let months = Int(match.output.1 ?? match.output.2 ?? "") {
            result.monthsAhead = months
            rest.replaceSubrange(match.range, with: " ")
        }
        // "from November", "starting jan 2027": only after a word like "from", since "may" is also an everyday word.
        if result.monthsAhead == nil,
           let match = rest.firstMatch(of: #/\b(?:from|starting|start|beginning|effective|in|on|for|by)\s+(?:(?:in|on)\s+)?(?:the\s+month\s+of\s+)?(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)\b(?:\s+(\d{4}))?/#.ignoresCase()),
           let index = monthNames.firstIndex(where: { $0.hasPrefix(match.output.1.lowercased().prefix(3)) }) {
            let thisMonth = calendar.component(.month, from: .now)
            if let year = match.output.2.flatMap({ Int($0) }) {
                result.monthsAhead = (year - calendar.component(.year, from: .now)) * 12 + index + 1 - thisMonth
            } else {
                result.monthsAhead = (index + 1 - thisMonth + 12) % 12
            }
            rest.replaceSubrange(match.range, with: " ")
        }

        // "rename Food to Groceries": taken out before names are matched, in case the new name is one of them.
        let isEditRequest = mentions(editWords) && !isHypothetical
        if isEditRequest, mentions(["rename", "name"]),
           let match = rest.firstMatch(of: #/\b(?:to|as|into)\s+["“']?([^"”']+?)["”']?\s*[.!?]*\s*$/#.ignoresCase()) {
            let name = String(match.output.1).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                result.newName = name == name.lowercased() ? name.capitalized : name
                rest.replaceSubrange(match.range, with: " ")
            }
        }

        // "150 + 200", "3 x 500", "1.5k minus 300": worked out into one amount, keeping the working to show.
        let number = #"(?:₱|\$)?\s?\d[\d,]*(?:\.\d+)?(?:\s?(?:k|thousand)\b)?"#
        let operation = #"\s*(?:\+|-|−|×|\*|/|÷|x(?=\s*[\d₱$])|\bplus\b|\bminus\b|\bless\b|\btimes\b|\bdivided by\b|\bmultiplied by\b)\s*"#
        if let range = rest.range(of: "\(number)(?:\(operation)\(number))+", options: [.regularExpression, .caseInsensitive]),
           let tokens = try? NSRegularExpression(
               pattern: #"(\d[\d,]*(?:\.\d+)?)\s?(k|thousand)?|(\+|-|−|×|\*|/|÷|x|plus|minus|less|times|divided by|multiplied by)"#,
               options: .caseInsensitive
           ) {
            let expression = String(rest[range])
            var calculation = ""
            var working = ""
            for match in tokens.matches(in: expression, range: NSRange(expression.startIndex..., in: expression)) {
                if let digits = Range(match.range(at: 1), in: expression),
                   var value = Decimal(string: expression[digits].replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")) {
                    if match.range(at: 2).location != NSNotFound { value *= 1000 }
                    calculation += "\(value)"
                    working += value.formatted()
                } else if let symbol = Range(match.range(at: 3), in: expression) {
                    let operation: Character = switch expression[symbol].lowercased() {
                    case "+", "plus": "+"
                    case "-", "−", "minus", "less": "−"
                    case "/", "÷", "divided by": "÷"
                    default: "×"
                    }
                    calculation.append(operation)
                    working += " \(operation) "
                }
            }
            let calculator = CalculatorModel()
            calculator.expression = calculation
            result.amount = calculator.result
            result.working = working
            rest.replaceSubrange(range, with: " ")
        }

        // "200", "₱1,500", "1.5k" — but not the "2" in "2 days ago".
        if result.working == nil,
           let match = rest.firstMatch(of: #/(?:₱|\$)?\s?(\d[\d,]*(?:\.\d+)?)\s?(k|thousand)?\b(?!\s*days?\b)/#.ignoresCase()),
           var amount = Decimal(string: match.output.1.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")) {
            if match.output.2 != nil { amount *= 1000 }
            result.amount = amount
            rest.replaceSubrange(match.range, with: " ")
        }

        // "increase rent by 500", "lower food by 1k": a change to the current amount rather than a new one.
        if isEditRequest, let amount = result.amount, mentions(["by"]) {
            if mentions(["increase", "raise", "bump", "up", "more", "add"]) {
                result.amountChange = amount
                result.amount = nil
            } else if mentions(["decrease", "lower", "reduce", "cut", "down", "less"]) {
                result.amountChange = -amount
                result.amount = nil
            }
        }

        // "200 a day" in a what-if: for the stated time, or for the rest of this month.
        if isHypothetical, let amount = result.amount {
            let daysIn = ["day": 1, "week": 7, "month": 30]
            // "daily" in "on daily" can be part of a name like "Daily Food" rather than a rate.
            let nameWords = Set((categoryNames + incomeNames).flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter }) }.map(String.init))
            let rateUnit: String? = rest.firstMatch(of: #/\b(?:a|per|every|each)\s+(day|week|month)\b|\b(daily|weekly)\b/#.ignoresCase())
                .flatMap { match in (match.output.1 ?? match.output.2).map { nameWords.contains($0.lowercased()) } == true ? nil : match }
                .map { match in
                    let unit = (match.output.1 ?? match.output.2 ?? "").lowercased()
                    return unit == "daily" ? "day" : unit == "weekly" ? "week" : unit
                }
            let base = result.working.map { "(\($0))" } ?? amount.formatted()
            var factor: Decimal?
            var working = ""
            if let count {
                let unit = count.unit.hasSuffix("s") ? String(count.unit.dropLast()) : count.unit
                if unit != "time", let rateUnit, let unitDays = daysIn[unit], let rateDays = daysIn[rateUnit] {
                    factor = Decimal(count.number * unitDays) / Decimal(rateDays)
                    working = "\(base) a \(rateUnit) for \(count.number) \(count.unit)"
                } else {
                    factor = Decimal(count.number)
                    working = "\(base) × \(count.number) \(count.unit)"
                }
            } else if let rateUnit, rateUnit != "month",
                      let monthEnd = Calendar.current.dateInterval(of: .month, for: .now)?.end {
                let daysLeft = max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: monthEnd).day ?? 1, 1)
                let periods = rateUnit == "day" ? daysLeft : max(daysLeft / 7, 1)
                factor = Decimal(periods)
                working = "\(base) a \(rateUnit) for the \(periods) \(rateUnit)\(periods == 1 ? "" : "s") left this month"
            }
            if let factor {
                result.amount = amount * factor
                result.working = working
            }
        }

        for (phrase, days) in [("day before yesterday", 2), ("yesterday", 1), ("last night", 1), ("today", 0), ("tonight", 0), ("this morning", 0)] {
            if let range = rest.range(of: "\\b\(phrase)\\b", options: [.regularExpression, .caseInsensitive]) {
                result.daysAgo = days
                rest.replaceSubrange(range, with: " ")
                break
            }
        }
        if result.daysAgo == nil, let match = rest.firstMatch(of: #/(\d+)\s+days?\s+ago/#.ignoresCase()) {
            result.daysAgo = Int(match.output.1)
            rest.replaceSubrange(match.range, with: " ")
        }
        if result.daysAgo == nil,
           let match = rest.firstMatch(of: #/(last\s+|on\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)/#.ignoresCase()),
           let weekday = weekdays.firstIndex(of: match.output.2.lowercased()) {
            let today = Calendar.current.component(.weekday, from: .now) - 1
            let days = (today - weekday + 7) % 7
            result.daysAgo = days == 0 && match.output.1?.lowercased().hasPrefix("last") == true ? 7 : days
            rest.replaceSubrange(match.range, with: " ")
        }

        func mentionsName(_ name: String) -> Bool {
            let lowerName = name.lowercased()
            return mentions([lowerName]) || (lowerName.count > 3 && lowerName.hasSuffix("s") && mentions([String(lowerName.dropLast())]))
        }
        // "Subscriptions (Netflix)" -> ["Subscriptions", "Netflix"]. Most specific match wins: the part in
        // parentheses, then the full name, then the part before it. Longest names first, so "cat food"
        // picks "Cat Food" over "Food".
        let nameParts = categoryNames.sorted { $0.count > $1.count }.map { name in
            (name, name.split(whereSeparator: { "()".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        }
        let named = nameParts.lazy.compactMap { name, parts in parts.dropFirst().first(where: mentionsName).map { (name, $0) } }.first
            ?? nameParts.first { name, _ in mentionsName(name) }.map { name, _ in (name, name) }
            ?? nameParts.first { _, parts in parts.first.map(mentionsName) ?? false }.map { name, parts in (name, parts[0]) }
        if let (_, term) = named {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: term))\\b|\\b\(NSRegularExpression.escapedPattern(for: String(term.dropLast())))\\b"
            rest = rest.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        // Shortest name first, so "lunch" picks "Food" rather than "Pet Food".
        result.category = named?.0 ?? categoryNames.sorted { $0.count < $1.count }.first { name in
            categoryHints.contains { key, hints in name.lowercased().contains(key) && mentions(hints) }
        }
        result.income = incomeNames.sorted { $0.count > $1.count }.first(where: mentionsName)

        // "except for daily food", "not counting rent": names left out of a total. Longest first, so
        // "daily food" leaves out Daily Food and not Food too.
        var excluded: [String] = []
        if let match = lower.firstMatch(of: #/\b(?:except|excluding|exclude|without|besides|apart from|other than|not counting|not including|but not)\b(.*)/#) {
            var tail = String(match.output.1)
            for name in (categoryNames + incomeNames).sorted(by: { $0.count > $1.count }) where tail.contains(name.lowercased()) {
                excluded.append(name)
                tail = tail.replacingOccurrences(of: name.lowercased(), with: " ")
            }
            // Only part of a name, like "except daily": leave out every name with that word.
            if excluded.isEmpty {
                excluded = (categoryNames + incomeNames).filter { name in
                    name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                        .contains { $0.count >= 3 && tail.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }
                }
            }
        }
        if !excluded.isEmpty {
            result.excluded = excluded
            if let category = result.category, excluded.contains(category) { result.category = nil }
            if let income = result.income, excluded.contains(income) { result.income = nil }
        }

        if result.category == nil && result.income == nil && excluded.isEmpty {
            let genericWords: Set<String> = ["the", "and", "for", "with", "from", "other"]
            let partlyMentioned = { (name: String) in
                name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .contains { $0.count >= 3 && !genericWords.contains(String($0)) && mentionsName(String($0)) }
            }
            result.categoryMatches = categoryNames.filter(partlyMentioned)
            result.incomeMatches = incomeNames.filter(partlyMentioned)
            // A misspelled name, like "fod" or "grocries", gets a "Did you mean Food?" too. Same first letter,
            // so everyday words like "went" aren't read as "Rent".
            if result.categoryMatches?.isEmpty == true && result.incomeMatches?.isEmpty == true {
                let words = lower.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 3 }
                let misspelled = { (name: String) in
                    name.lowercased().split(whereSeparator: { !$0.isLetter }).contains { part in
                        part.count >= 3 && words.contains { word in
                            word.first == part.first && editDistance(String(word), String(part)) <= (part.count <= 5 ? 1 : 2)
                        }
                    }
                }
                result.categoryMatches = categoryNames.filter(misspelled)
                result.incomeMatches = incomeNames.filter(misspelled)
            }
        }

        let hasDetails = result.amount != nil || result.category != nil
        // Spending words only count in statements: "should I buy bitcoin?" asks for advice rather than logging anything.
        let isQuestion = lower.contains("?") || ["should", "what", "who", "why", "can", "could", "would", "is", "are", "do", "does"]
            .contains(lower.split(separator: " ").first.map(String.init) ?? "")
        let isAboutBudget = hasDetails || mentions(incomeWords + ["salary", "left", "remaining", "budget"])
            || (!isQuestion && mentions(spendWords))
        let asksTotal = !excluded.isEmpty || mentions(["total", "overall", "altogether", "in all", "sum"])
        // "Total spent on food" is still about one category.
        let namesOne = result.category != nil || result.income != nil || !(result.categoryMatches ?? []).isEmpty
        let total: Interpretation.Total? = if !asksTotal || result.amount != nil || namesOne {
            nil
        } else if mentions(["left", "remaining", "remain"]) {
            .left
        } else if mentions(["expense", "expenses", "spent", "spend", "spending", "paid", "used", "cost", "costs"]) {
            .spent
        } else if mentions(["income", "incomes", "salary", "earn", "earned", "earnings"]) {
            .income
        } else if mentions(["budget", "limit", "limits"]) {
            .limit
        } else {
            excluded.isEmpty ? nil : .left
        }

        // "Change rent to 6000", "rename food to groceries", "set my salary to 30k from November".
        let namesTarget = result.category != nil || result.income != nil
            || !(result.categoryMatches ?? []).isEmpty || !(result.incomeMatches ?? []).isEmpty
        if isEditRequest && (namesTarget || result.newName != nil
                             || mentions(["limit", "budget", "income", "salary", "category", "expense", "amount", "name"])) {
            result.intent = .edit
        } else if isHypothetical && result.amount != nil {
            result.intent = .whatIf
        } else if result.working != nil && result.category == nil && !mentions(spendWords + incomeWords + ["salary"]) {
            result.intent = .calculate
        } else if let total {
            result.intent = .remaining
            result.total = total
        } else if !isAboutBudget, let topic = offTopics.first(where: { mentions($0.keywords) }) {
            result.intent = .offTopic
            result.topic = topic.name
        } else if mentions(remainingWords) || (isQuestion && mentions(["budget", "limit"]))
                    // "What's the total spent on food?" asks about spending rather than logging it.
                    || (isQuestion && result.amount == nil && result.category != nil && mentions(spendWords)) {
            result.intent = .remaining
        } else if mentions(incomeWords + ["salary"]) {
            result.intent = .income
        } else if mentions(spendWords) || (result.amount != nil && result.category != nil) {
            result.intent = .spend
        } else if !hasDetails && mentions(cancelWords) {
            result.intent = .cancel
        } else if !hasDetails && mentions(confirmWords) {
            result.intent = .confirm
        } else {
            result.intent = .other
        }

        let removable = Set(spendWords + incomeWords.flatMap { $0.split(separator: " ").map(String.init) }).union(currencyWords)
        var words = rest
            .split(whereSeparator: { $0.isWhitespace || ",.!?".contains($0) })
            .map(String.init)
            .filter { !removable.contains($0.lowercased()) }
        while let first = words.first, edgeWords.contains(first.lowercased()) { words.removeFirst() }
        while let last = words.last, edgeWords.contains(last.lowercased()) { words.removeLast() }

        if !words.isEmpty {
            let leftover = words.joined(separator: " ")
            if result.intent == .income {
                result.source = leftover.capitalized
            } else if result.intent == .spend || result.intent == .other {
                result.note = leftover.prefix(1).uppercased() + leftover.dropFirst()
            }
        }
        return result
    }
}

/// Holds the conversation, asks follow-up questions for missing details, and writes confirmed entries to SwiftData.
@Observable @MainActor
final class Assistant {
    struct Message: Identifiable {
        let id = UUID()
        let fromUser: Bool
        let text: String
        var suggestions: [String] = []
    }

    private enum Kind { case spend, income }

    private struct Draft {
        var kind: Kind?
        var amount: Decimal?
        var category: BudgetCategory?
        var categoryGuess: String?
        var note: String?
        var source: String?
        /// The income that paid for an expense, when expenses are linked to income.
        var paidWith: IncomeSource?
        var daysAgo = 0
        /// Categories the message only partly named, to ask which one it was.
        var categoryChoices: [String] = []

        var date: Date { Calendar.current.date(byAdding: .day, value: -max(daysAgo, 0), to: .now) ?? .now }
    }

    /// Starts with a greeting from `greet(in:)`.
    private(set) var messages: [Message] = []
    private(set) var isThinking = false
    private var draft: Draft?
    private var awaitingConfirmation = false
    private var awaitingIncome = false
    private var incomes: [IncomeSource] = []
    /// Includes limits that ended this month, so totals match the Budget tab.
    private var allCategories: [BudgetCategory] = []

    private struct Choice {
        let name: String
        let isIncome: Bool
    }
    /// Waiting for the user to pick which name they meant; then `interpretation` carries on with it.
    private var clarification: (interpretation: Interpretation, choices: [Choice])?

    /// A change to a category's limit or an income's amount or name, built up over a few messages.
    private struct Edit {
        var category: BudgetCategory?
        var income: IncomeSource?
        var amount: Decimal?
        /// Added to the current amount instead of replacing it, from "increase rent by 500".
        var change: Decimal?
        var name: String?
        /// Months from this one that a new amount starts; nil means this month.
        var monthsAhead: Int?
        var targetName: String? { category?.name ?? income?.name }
    }
    private var edit: Edit?
    private enum EditQuestion { case target, value }
    private var editQuestion: EditQuestion?

    /// A different opening each time: a hello for the time of day, something about the budget right now,
    /// and an example to try using the user's own category names.
    func greet(in context: ModelContext) {
        guard messages.isEmpty else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let money = { (value: Decimal) in value.formatted(.currency(code: currencyCode)) }
        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>(predicate: #Predicate { !$0.isArchived })))?
            .filter { $0.status == .active } ?? []
        let logs = (try? context.fetch(FetchDescriptor<SpendLog>())) ?? []

        let hour = calendar.component(.hour, from: .now)
        let timeOfDay = switch hour {
        case 5..<12: "Good morning!"
        case 12..<18: "Good afternoon!"
        case 18..<22: "Good evening!"
        default: "Still up?"
        }
        let opening = [timeOfDay, timeOfDay, "Hi there!", "Hey!", "Welcome back!"].randomElement() ?? timeOfDay

        // Due bills always come first; otherwise one of a few things worth knowing today.
        let dueBills = categories
            .compactMap { category in category.unpaidDue.map { (category: category, due: $0) } }
            .filter { calendar.startOfDay(for: $0.due.date) <= today }
            .sorted { $0.due.date < $1.due.date }
        var insight = ""
        if let first = dueBills.first {
            let isLate = calendar.startOfDay(for: first.due.date) < today
            insight = dueBills.count == 1
                ? "\(first.category.name) \(isLate ? "is overdue" : "is due today") (\(money(first.due.amount)))."
                : "\(dueBills.count) bills need paying, starting with \(first.category.name)."
        } else if !categories.isEmpty {
            let left = categories.reduce(0) { $0 + $1.remainingThisMonth }
            let spentToday = logs.filter { calendar.isDate($0.effectiveDate, inSameDayAs: .now) }.reduce(0) { $0 + $1.amount }
            let daysLeft = (calendar.dateInterval(of: .month, for: .now)?.end)
                .flatMap { calendar.dateComponents([.day], from: today, to: $0).day } ?? 0
            var insights = [
                left < 0 ? "You're \(money(-left)) over budget this month." : "You have \(money(left)) left in your budget this month.",
                spentToday > 0 ? "You've logged \(money(spentToday)) in expenses today." : "Nothing logged yet today.",
            ]
            if daysLeft > 0 && left > 0 {
                insights.append("That's about \(money(left / Decimal(daysLeft))) a day for the \(daysLeft) day\(daysLeft == 1 ? "" : "s") left this month.")
            }
            if let tightest = categories.filter({ $0.limit > 0 && $0.remainingThisPeriod > 0 })
                .min(by: { $0.remainingThisPeriod / $0.availableThisPeriod < $1.remainingThisPeriod / $1.availableThisPeriod }),
               tightest.remainingThisPeriod / tightest.availableThisPeriod < 0.3 {
                insights.append("\(tightest.name) is running low, with \(money(tightest.remainingThisPeriod)) left \(tightest.periodName).")
            }
            insight = insights.randomElement() ?? ""
        }

        let name = categories.randomElement()?.name ?? "Food"
        let example = [
            "Try “\(name) 150” to log an expense.",
            "Log something like “\(name) 200 yesterday”.",
            "Ask me “How much is left for \(name)?”",
            "Thinking of buying something? Ask “If I spend 500 on \(name), how much is left?”",
            "Planning ahead? Try “Change \(name) to 3000 next month”.",
            "Got paid? Try “Add salary 25k”.",
        ].randomElement() ?? ""

        var suggestions = ["How much is left?", "Log an expense"]
        if let first = dueBills.first {
            suggestions.insert("Log \(first.due.amount.formatted()) to \(first.category.name)", at: 0)
        }
        messages.append(Message(fromUser: false, text: [opening, insight, example].filter { !$0.isEmpty }.joined(separator: " "),
                                suggestions: suggestions))
    }

    func send(_ text: String, in context: ModelContext) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }

        let lastQuestion = messages.last { !$0.fromUser }?.text
        messages.append(Message(fromUser: true, text: text))
        let descriptor = FetchDescriptor<BudgetCategory>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.createdAt)])
        allCategories = (try? context.fetch(descriptor)) ?? []
        let categories = allCategories.filter { $0.status == .active }
        let names = categories.map(\.name)
        incomes = (try? context.fetch(FetchDescriptor<IncomeSource>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []

        let rules = CommandParser.parse(text, categoryNames: names, incomeNames: incomes.map(\.name))
        var interpretation = rules
        let isGibberish = CommandParser.isGibberish(text, names: allCategories.map(\.name) + incomes.map(\.name))
        if LocalModel.shared.isReady && !isGibberish {
            isThinking = true
            let ai = await LocalModel.shared.interpret(text, categories: names, lastQuestion: lastQuestion)
            isThinking = false
            // The model wins where it found something; the rules fill in amounts and keywords it missed.
            if let ai {
                let aiCategory = ai.category.flatMap { name in names.first { $0.localizedCaseInsensitiveCompare(name) == .orderedSame } }
                // Don't let the model turn down something the rules found budget details in,
                // like an income named "Money Laundering".
                let rulesFoundBudget = rules.amount != nil || rules.category != nil || ![.other, .offTopic].contains(rules.intent)
                let aiIntent = ai.intent == .offTopic && rulesFoundBudget ? .other : ai.intent ?? .other
                // The rules do arithmetic exactly and never log a what-if, so they decide those.
                let rulesDecide = [.whatIf, .calculate, .edit].contains(rules.intent) || rules.total != nil
                // When a word only partly matches names, ask rather than let the model guess one.
                let isAmbiguous = !(rules.categoryMatches ?? []).isEmpty || !(rules.incomeMatches ?? []).isEmpty
                interpretation = Interpretation(
                    intent: rulesDecide || aiIntent == .other ? rules.intent : aiIntent,
                    amount: rules.working != nil ? rules.amount : ai.amount ?? rules.amount,
                    // A total never uses the category the model found; it may be the one left out.
                    category: isAmbiguous || rules.total != nil ? rules.category : aiCategory ?? rules.category ?? ai.category,
                    note: ai.note ?? rules.note,
                    daysAgo: ai.daysAgo ?? rules.daysAgo,
                    source: ai.source ?? rules.source,
                    topic: ai.topic ?? rules.topic,
                    working: rules.working,
                    income: rules.income,
                    categoryMatches: rules.categoryMatches,
                    incomeMatches: rules.incomeMatches,
                    total: rules.total,
                    excluded: rules.excluded,
                    monthsAhead: rules.monthsAhead,
                    newName: rules.newName,
                    amountChange: rules.amountChange
                )
            }
        } else {
            // The rules answer instantly; a short typing pause reads more like a conversation.
            isThinking = true
            try? await Task.sleep(for: .milliseconds(800))
            isThinking = false
        }
        if isGibberish {
            // Nothing in progress changes; whatever was just asked is asked again.
            let quoted = text.count > 24 ? "that" : "“\(text)”"
            let opener = [
                "Hmm, I didn't catch \(quoted). Was that a typo?",
                "Oops, \(quoted) looks like a typo.",
                "Sorry, I couldn't make sense of \(quoted).",
                "Looks like your fingers slipped there.",
            ].randomElement() ?? ""
            if let pending = clarification {
                reply(opener)
                askWhich(pending.choices, for: pending.interpretation)
            } else if edit != nil {
                reply(opener)
                advanceEdit()
            } else if draft != nil {
                reply(opener)
                advance(categories: categories)
            } else {
                reply("\(opener) You can log an expense like “Food 200”, add income, or ask how much is left.",
                      suggestions: ["How much is left?", "Log an expense", "Add income"])
            }
            return
        }
        handle(interpretation, text: text, categories: categories, context: context)
    }

    private func handle(_ interpretation: Interpretation, text: String, categories: [BudgetCategory], context: ModelContext) {
        if let pending = clarification {
            clarification = nil
            // A tapped or typed name, or "yes" to the only one offered. Longest first so "Daily Food" beats "Food".
            let picked = pending.choices.count == 1 && interpretation.intent == .confirm
                ? pending.choices.first
                : pending.choices.sorted { $0.name.count > $1.name.count }.first { text.localizedCaseInsensitiveContains($0.name) }
            if let picked {
                var resolved = pending.interpretation
                resolved.categoryMatches = nil
                resolved.incomeMatches = nil
                if picked.isIncome { resolved.income = picked.name } else { resolved.category = picked.name }
                handle(resolved, text: text, categories: categories, context: context)
                return
            }
            // "No" to "Did you mean Daily Food?": offer all of them instead.
            if pending.choices.count == 1 && interpretation.intent == .cancel {
                let incomeChoices = pending.interpretation.intent == .remaining ? incomes.map { Choice(name: $0.name, isIncome: true) } : []
                askWhich(categories.map { Choice(name: $0.name, isIncome: false) } + incomeChoices, for: pending.interpretation)
                return
            }
        }

        var interpretation = interpretation
        // A short reply like "school" may just be answering the question that's waiting.
        if interpretation.intent == .offTopic && draft != nil && text.split(separator: " ").count <= 3 {
            interpretation.intent = .other
        }
        // "150 + 200" while an amount is being asked for is the answer, not a question.
        if interpretation.intent == .calculate && draft != nil && draft?.amount == nil {
            interpretation.intent = .other
        }

        // "Change it to food" while an expense is being logged corrects that expense.
        if interpretation.intent == .edit && draft != nil && interpretation.newName == nil && interpretation.monthsAhead == nil {
            interpretation.intent = .other
        }
        if edit != nil {
            switch interpretation.intent ?? .other {
            case .cancel:
                edit = nil
                editQuestion = nil
                awaitingConfirmation = false
                reply("Okay, nothing changed.")
                return
            case .confirm where awaitingConfirmation:
                applyEdit()
                return
            case .confirm, .other, .edit:
                updateEdit(with: interpretation, text: text)
                return
            // An answer like "Salary" to "Which one do you want to change?" isn't adding income.
            case _ where editQuestion != nil:
                updateEdit(with: interpretation, text: text)
                return
            default:
                // Moving on to something else, like logging an expense, drops the change.
                edit = nil
                editQuestion = nil
                awaitingConfirmation = false
            }
        } else if interpretation.intent == .edit {
            updateEdit(with: interpretation, text: text)
            return
        }

        // Checked first because an answer like "Salary" would otherwise read as adding income.
        if awaitingIncome, interpretation.intent != .cancel,
           let income = incomes.first(where: { text.localizedCaseInsensitiveContains($0.name) }) {
            draft?.paidWith = income
            advance(categories: categories)
            return
        }

        switch interpretation.intent ?? .other {
        case .cancel:
            reply(draft == nil ? "Okay." : "Okay, cancelled.")
            draft = nil
            awaitingConfirmation = false
            awaitingIncome = false
            return
        case .confirm where awaitingConfirmation:
            save(in: context)
            return
        case .remaining:
            if let total = interpretation.total {
                answerTotal(total, excluding: interpretation.excluded ?? [])
                return
            }
            if interpretation.category == nil && interpretation.income == nil {
                let choices = (interpretation.categoryMatches ?? []).map { Choice(name: $0, isIncome: false) }
                    + (interpretation.incomeMatches ?? []).map { Choice(name: $0, isIncome: true) }
                if !choices.isEmpty {
                    askWhich(choices, for: interpretation)
                    return
                }
            }
            if interpretation.category == nil, let income = incomes.first(where: { $0.name == interpretation.income }) {
                let money = { (value: Decimal) in value.formatted(.currency(code: currencyCode)) }
                var answer = "\(income.name) brings in \(money(income.amount)) a month."
                if UserDefaults.standard.bool(forKey: "linksExpensesToIncome") {
                    let left = income.remainingThisMonth
                    answer += left < 0
                        ? " This month's expenses paid from it are \(money(-left)) more than that."
                        : " \(money(left)) is left after this month's expenses paid from it."
                }
                reply(answer)
                return
            }
            reply(summary(for: interpretation.category, categories: categories))
            return
        case .whatIf:
            guard let amount = interpretation.amount else {
                reply("How much are you thinking of spending? For example: “If I spend 500 on food, how much is left?”")
                return
            }
            if interpretation.category == nil, let matches = interpretation.categoryMatches, !matches.isEmpty {
                askWhich(matches.map { Choice(name: $0, isIncome: false) }, for: interpretation)
                return
            }
            answerWhatIf(amount: amount, categoryName: interpretation.category, working: interpretation.working, categories: categories)
            return
        case .calculate:
            if let amount = interpretation.amount, let working = interpretation.working {
                reply("\(working) = \(amount.formatted(.currency(code: currencyCode)))")
            } else {
                reply("I can't work that out because it divides by zero.")
            }
            return
        case .offTopic:
            let topic = interpretation.topic?.lowercased()
            let advice = switch topic {
            case "legal questions": " For legal matters, a lawyer is the best person to ask."
            case "health advice": " For health concerns, please talk to a doctor."
            case "investing advice": " For investing, a licensed financial adviser can help."
            default: ""
            }
            reply("Sorry, I can't help with \(topic ?? "that"). I'm your budget assistant, so I can log expenses, add income, and tell you what's left.\(advice)",
                  suggestions: draft == nil ? ["How much is left?", "Log an expense", "Add income"] : [])
            // Pick up where the entry in progress left off.
            if draft != nil { advance(categories: categories) }
            return
        case .spend, .income:
            let kind: Kind = interpretation.intent == .spend ? .spend : .income
            if draft == nil || (draft?.kind != nil && draft?.kind != kind) || (awaitingConfirmation && interpretation.amount != nil) {
                draft = Draft(kind: kind)
            } else {
                draft?.kind = kind
            }
        case .confirm, .other, .edit:
            if draft != nil && interpretation.intent == .confirm {
                advance(categories: categories)
                return
            }
            if draft == nil {
                guard interpretation.amount != nil else {
                    reply("I can log expenses, add income, change a limit or income, or tell you what's left. Try “Food expense 200”, “Add salary 25k”, “Change rent to 6000 next month”, or “How much is left?”")
                    return
                }
                draft = Draft()
            }
        }

        guard var current = draft else { return }
        var categoryGuess = interpretation.category
        var source = interpretation.source
        let answeredNothing = interpretation.intent == .other && interpretation.amount == nil
            && interpretation.category == nil && interpretation.source == nil && interpretation.daysAgo == nil
        // A bare reply like "snacks" or "Freelance" answers whatever was just asked.
        if answeredNothing && current.amount != nil && current.kind == .spend && current.category == nil {
            categoryGuess = text
        } else if answeredNothing && current.amount != nil && current.kind == .income && current.source == nil {
            source = interpretation.note ?? text
        } else if let note = interpretation.note, interpretation.intent != .other {
            current.note = note
        }

        current.amount = interpretation.amount ?? current.amount
        current.daysAgo = interpretation.daysAgo ?? current.daysAgo
        if let source {
            current.source = source.prefix(1).uppercased() + source.dropFirst()
        }
        if let categoryGuess {
            current.categoryGuess = categoryGuess
            current.category = matchCategory(categoryGuess, in: categories)
        }
        // A word that's only part of a name, like "daily", is asked about rather than guessed.
        if interpretation.category == nil, current.kind != .income, let matches = interpretation.categoryMatches, !matches.isEmpty {
            current.category = nil
            current.categoryChoices = matches
        }
        if current.kind == nil && current.category != nil { current.kind = .spend }
        if current.kind == nil && current.source != nil { current.kind = .income }

        draft = current
        advance(categories: categories)
    }

    /// Asks for the next missing detail, or for confirmation once everything is known.
    private func advance(categories: [BudgetCategory]) {
        guard let current = draft else { return }
        awaitingConfirmation = false
        awaitingIncome = false

        switch current.kind {
        case nil:
            reply("Was that an expense or income?", suggestions: ["Expense", "Income"])
        case .spend:
            guard let amount = current.amount else {
                return reply("How much was the expense?")
            }
            guard !categories.isEmpty else {
                draft = nil
                return reply("You don't have any budget categories yet. Add one in the Budget tab first.")
            }
            guard let category = current.category else {
                if !current.categoryChoices.isEmpty {
                    // Asked once; an answer that isn't one of them falls back to the question below.
                    draft?.categoryChoices = []
                    return askWhich(current.categoryChoices.map { Choice(name: $0, isIncome: false) }, for: Interpretation(intent: .spend))
                }
                let question = current.categoryGuess.map { "I couldn't find a category called “\($0)”. Which one was it?" }
                    ?? "What category was that for?"
                return reply(question, suggestions: categories.map(\.name))
            }
            if UserDefaults.standard.bool(forKey: "linksExpensesToIncome") && current.paidWith == nil {
                guard !incomes.isEmpty else {
                    draft = nil
                    return reply("Your expenses are linked to income, so add an income in the Income tab first.")
                }
                awaitingIncome = true
                return reply("Which income did you pay with?", suggestions: incomes.map(\.name))
            }
            let note = current.note.map { " (\($0))" } ?? ""
            let day = switch current.daysAgo {
            case ...0: "today"
            case 1: "yesterday"
            default: current.date.formatted(.dateTime.month(.abbreviated).day())
            }
            let paidWith = current.paidWith.map { " from \($0.name)" } ?? ""
            awaitingConfirmation = true
            reply("Log \(amount.formatted(.currency(code: currencyCode))) to \(category.name)\(note) for \(day)\(paidWith)?", suggestions: ["Confirm", "Cancel"])
        case .income:
            guard let amount = current.amount else {
                return reply("How much is it per month?")
            }
            guard let source = current.source else {
                return reply("What should I call this income?", suggestions: ["Salary", "Freelance", "Business"])
            }
            awaitingConfirmation = true
            reply("Add “\(source)” as income of \(amount.formatted(.currency(code: currencyCode))) per month?", suggestions: ["Confirm", "Cancel"])
        }
    }

    private func save(in context: ModelContext) {
        guard let current = draft, let amount = current.amount else { return }
        draft = nil
        awaitingConfirmation = false
        let formattedAmount = amount.formatted(.currency(code: currencyCode))

        if current.kind == .spend, let category = current.category {
            var remaining = category.remainingThisPeriod
            if category.isInCurrentPeriod(current.date) { remaining -= amount }
            // Only a day the user mentioned, like "yesterday", counts as a set date.
            let log = SpendLog(amount: amount, note: current.note ?? "", date: current.daysAgo > 0 ? current.date : nil, category: category)
            context.insert(log)
            if let income = current.paidWith {
                log.setFundings([income.persistentModelID: amount], from: [income], in: context)
            }
            let status = remaining < 0
                ? "You're \((-remaining).formatted(.currency(code: currencyCode))) over your \(category.name) limit \(category.periodName)."
                : "You have \(remaining.formatted(.currency(code: currencyCode))) left in \(category.name) \(category.periodName)."
            reply("Done! Logged \(formattedAmount) to \(category.name). \(status)")
        } else if current.kind == .income, let source = current.source {
            context.insert(IncomeSource(name: source, amount: amount))
            reply("Done! Added \(source) at \(formattedAmount) per month.")
        }
    }

    /// Folds a message into the change being set up: a fresh request, or an answer to the last question.
    private func updateEdit(with interpretation: Interpretation, text: String) {
        let isNewRequest = interpretation.intent == .edit && editQuestion == nil
        var current = isNewRequest ? Edit() : edit ?? Edit()
        let findCategory = { (name: String) in self.matchCategory(name, in: self.allCategories) }
        let findIncome = { (name: String) in self.incomes.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } }

        if editQuestion == .value && interpretation.amount == nil && interpretation.amountChange == nil
            && interpretation.newName == nil && interpretation.monthsAhead == nil && interpretation.intent != .confirm {
            // A bare reply like "Groceries" to "What should Food change to?" is the new name.
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            current.name = name == name.lowercased() ? name.capitalized : name
        } else {
            if isNewRequest || editQuestion == .target {
                if let category = interpretation.category.flatMap(findCategory)
                    ?? allCategories.sorted(by: { $0.name.count > $1.name.count }).first(where: { text.localizedCaseInsensitiveContains($0.name) }) {
                    current.category = category
                    current.income = nil
                } else if let income = interpretation.income.flatMap(findIncome)
                            ?? incomes.sorted(by: { $0.name.count > $1.name.count }).first(where: { text.localizedCaseInsensitiveContains($0.name) }) {
                    current.income = income
                    current.category = nil
                }
            }
            if let amount = interpretation.amount {
                current.amount = amount
                current.change = nil
            }
            if let change = interpretation.amountChange {
                current.change = change
                current.amount = nil
            }
            current.name = interpretation.newName ?? current.name
            current.monthsAhead = interpretation.monthsAhead ?? current.monthsAhead
        }

        // A word that's only part of several names, like "daily", is asked about before going on.
        if current.targetName == nil && isNewRequest {
            let choices = (interpretation.categoryMatches ?? []).map { Choice(name: $0, isIncome: false) }
                + (interpretation.incomeMatches ?? []).map { Choice(name: $0, isIncome: true) }
            if !choices.isEmpty {
                edit = nil
                askWhich(choices, for: interpretation)
                return
            }
        }
        edit = current
        advanceEdit()
    }

    /// Asks for whatever the change still needs, then for confirmation.
    private func advanceEdit() {
        guard var current = edit else { return }
        let money = { (value: Decimal) in value.formatted(.currency(code: currencyCode)) }
        awaitingConfirmation = false
        editQuestion = nil

        guard let targetName = current.targetName else {
            editQuestion = .target
            let names = allCategories.map(\.name) + incomes.map(\.name)
            return reply(names.isEmpty ? "You don't have any categories or income to change yet." : "Which one do you want to change?",
                         suggestions: names)
        }
        if let months = current.monthsAhead, months < 0 {
            edit?.monthsAhead = nil
            return reply("Past months keep what you spent then, so a change can only start this month or later. When should it start?",
                         suggestions: ["This month", "Next month"])
        }
        guard current.amount != nil || current.change != nil || current.name != nil else {
            editQuestion = .value
            let noun = current.category != nil ? "limit" : "monthly amount"
            return reply("What should \(targetName) change to? Tell me a new \(noun), like 6000, or a new name.")
        }
        if let name = current.name, name.localizedCaseInsensitiveCompare(targetName) != .orderedSame,
           (allCategories.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            || incomes.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            edit?.name = nil
            editQuestion = .value
            return reply("You already have something called “\(name)”. What other name should \(targetName) have?")
        }

        let calendar = Calendar.current
        let months = current.monthsAhead ?? 0
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let month = calendar.date(byAdding: .month, value: months, to: thisMonth) ?? thisMonth
        let monthName = month.formatted(calendar.isDate(month, equalTo: .now, toGranularity: .year)
            ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
        let when = switch months {
        case 0: "starting this month"
        case 1: "starting next month (\(monthName))"
        default: "starting \(monthName)"
        }

        var parts: [String] = []
        if let name = current.name, name != targetName {
            parts.append("rename \(targetName) to \(name)")
        }
        var suggestions = ["Confirm"]
        if current.amount != nil || current.change != nil {
            let old = current.category?.limitAmount(inMonthOf: month) ?? current.income?.amount(inMonthOf: month) ?? 0
            let new = current.amount ?? old + (current.change ?? 0)
            guard new >= 0 else {
                edit?.change = nil
                editQuestion = .value
                return reply("That would take \(targetName) below zero, since it's \(money(old)) \(months == 0 ? "now" : "in \(monthName)"). What should it change to?")
            }
            current.amount = new
            current.change = nil
            edit = current
            let what = current.category != nil ? "\(parts.isEmpty ? "\(targetName)’s" : "its") limit" : "\(parts.isEmpty ? targetName : "it")"
            parts.append("change \(what) from \(money(old)) to \(money(new))\(current.income != nil ? " a month" : "") \(when)")
            suggestions.append(months == 0 ? "From next month" : "This month instead")
        }
        suggestions.append("Cancel")

        var notes: [String] = []
        if current.name != nil && current.monthsAhead.map({ $0 > 0 }) == true && current.amount == nil {
            notes.append("Names change right away rather than from a later month.")
        }
        let scheduledMonth = current.category?.scheduledLimitMonth ?? current.income?.scheduledAmountMonth
        let scheduledAmount = current.category?.scheduledLimit ?? current.income?.scheduledAmount
        if months > 0, current.amount != nil, let scheduledMonth, let scheduledAmount, scheduledMonth != month {
            notes.append("This replaces the change to \(money(scheduledAmount)) planned for \(scheduledMonth.formatted(.dateTime.month(.wide))).")
        }

        let sentence = parts.joined(separator: " and ")
        awaitingConfirmation = true
        reply(([sentence.prefix(1).uppercased() + sentence.dropFirst() + "?"] + notes).joined(separator: " "), suggestions: suggestions)
    }

    private func applyEdit() {
        guard let current = edit, let targetName = current.targetName else { return }
        edit = nil
        awaitingConfirmation = false
        editQuestion = nil
        let money = { (value: Decimal) in value.formatted(.currency(code: currencyCode)) }
        let calendar = Calendar.current
        let months = current.monthsAhead ?? 0
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let month = calendar.date(byAdding: .month, value: months, to: thisMonth) ?? thisMonth

        var done: [String] = []
        if let name = current.name, name != targetName {
            current.category?.name = name
            current.income?.name = name
            done.append("renamed \(targetName) to \(name)")
        }
        if let amount = current.amount {
            let shownName = current.name ?? targetName
            if months == 0 {
                current.category?.limit = amount
                current.income?.amount = amount
                done.append("\(shownName) is now \(money(amount))\(current.income != nil ? " a month" : "")")
            } else {
                current.category?.scheduledLimit = amount
                current.category?.scheduledLimitMonth = month
                current.income?.scheduledAmount = amount
                current.income?.scheduledAmountMonth = month
                let monthName = month.formatted(calendar.isDate(month, equalTo: .now, toGranularity: .year)
                    ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
                done.append("\(shownName) will be \(money(amount))\(current.income != nil ? " a month" : "") from \(monthName). Until then it stays as it is")
            }
        }
        let sentence = done.joined(separator: ", and ")
        reply("Done! " + sentence.prefix(1).uppercased() + sentence.dropFirst() + ".")
    }

    private func summary(for categoryName: String?, categories: [BudgetCategory]) -> String {
        guard !categories.isEmpty else {
            return "You don't have any budget categories yet. Add one in the Budget tab first."
        }
        if let categoryName, let category = matchCategory(categoryName, in: categories) {
            let remaining = category.remainingThisPeriod
            let limit = category.periodLimit.formatted(.currency(code: currencyCode))
            return remaining < 0
                ? "\(category.name) is \((-remaining).formatted(.currency(code: currencyCode))) over its \(limit) limit \(category.periodName)."
                : "You have \(remaining.formatted(.currency(code: currencyCode))) left in \(category.name) \(category.periodName) (\(category.spentThisPeriod.formatted(.currency(code: currencyCode))) of \(limit) used)."
        }

        let lines = categories.map { category in
            let remaining = category.remainingThisPeriod
            return "• \(category.name): \(abs(remaining).formatted(.currency(code: currencyCode))) \(remaining < 0 ? "over" : "left") \(category.periodName)"
        }
        return (["Here's what's left in each limit:"] + lines).joined(separator: "\n")
    }

    /// Works out what would be left after spending `amount`, in one category if named and across the whole budget.
    /// Nothing is logged; a suggestion logs it for real in one tap.
    private func answerWhatIf(amount: Decimal, categoryName: String?, working: String?, categories: [BudgetCategory]) {
        let money = { (value: Decimal) in value.formatted(.currency(code: currencyCode)) }
        let workingLine = working.map { "\($0) = \(money(amount)). " } ?? ""
        guard !categories.isEmpty else {
            reply(workingLine + "You don't have any budget limits yet, so there's nothing to take it from. Add a category in the Budget tab first.")
            return
        }
        let budgetLeft = categories.reduce(0) { $0 + $1.remainingThisMonth } - amount

        if let categoryName, let category = matchCategory(categoryName, in: categories) {
            let left = category.remainingThisPeriod - amount
            let categoryLine = left < 0
                ? "If you spend \(money(amount)) on \(category.name), you'd go \(money(-left)) over your \(category.name) limit \(category.periodName)."
                : "If you spend \(money(amount)) on \(category.name), you'd have \(money(left)) left in \(category.name) \(category.periodName)."
            let budgetLine = budgetLeft < 0
                ? "That's \(money(-budgetLeft)) more than your whole budget has left this month."
                : "Your whole budget would have \(money(budgetLeft)) left this month."
            reply("\(workingLine)\(categoryLine) \(budgetLine)", suggestions: ["Log \(amount.formatted()) to \(category.name)"])
        } else {
            reply(workingLine + (budgetLeft < 0
                ? "If you spend \(money(amount)), you'd go \(money(-budgetLeft)) over your budget this month."
                : "If you spend \(money(amount)), you'd have \(money(budgetLeft)) left in your budget this month."))
        }
    }

    /// Adds up this month's expenses, what's left, the limits, or income across the whole budget,
    /// leaving out any names in `excluded`.
    private func answerTotal(_ total: Interpretation.Total, excluding excluded: [String]) {
        let money = { (value: Decimal) in value.formatted(.currency(code: currencyCode)) }
        let spentThisMonth = { (category: BudgetCategory) in
            category.logs
                .filter { Calendar.current.isDate($0.effectiveDate, equalTo: .now, toGranularity: .month) }
                .reduce(0) { $0 + $1.amount }
        }
        let included = allCategories.filter { !excluded.contains($0.name) }
        let leftOut = total == .income
            ? incomes.filter { excluded.contains($0.name) }.map(\.name)
            : allCategories.filter { excluded.contains($0.name) }.map { total == .spent ? "\($0.name) (\(money(spentThisMonth($0))))" : $0.name }
        let notCounting = leftOut.isEmpty ? "" : ", not counting \(leftOut.formatted(.list(type: .and)))"

        switch total {
        case .spent:
            let lines = included
                .map { ($0.name, spentThisMonth($0)) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .map { "• \($0.0): \(money($0.1))" }
            let spent = included.reduce(0) { $0 + spentThisMonth($1) }
            reply((["Your total expenses this month are \(money(spent))\(notCounting)."] + lines).joined(separator: "\n"))
        case .left:
            let left = included.reduce(0) { $0 + $1.remainingThisMonth }
            reply(left < 0
                ? "You're \(money(-left)) over budget this month\(notCounting)."
                : "You have \(money(left)) left in your budget this month\(notCounting).")
        case .limit:
            reply("Your limits add up to \(money(included.reduce(0) { $0 + $1.limitThisMonth })) this month\(notCounting).")
        case .income:
            let sum = incomes.filter { !excluded.contains($0.name) }.reduce(0) { $0 + $1.amount }
            reply("Your income adds up to \(money(sum)) a month\(notCounting).")
        }
    }

    /// Asks which name was meant when a word matched several, or checks the only one it partly matched,
    /// like "Did you mean Daily Food?". Once one is picked, `interpretation` carries on with it.
    private func askWhich(_ choices: [Choice], for interpretation: Interpretation) {
        clarification = (interpretation, choices)
        let mixesKinds = choices.contains(where: \.isIncome) && choices.contains { !$0.isIncome }
        let describe = { (choice: Choice) in
            choice.name + (mixesKinds || choices.count == 1 ? (choice.isIncome ? " (income)" : " (expense)") : "")
        }
        if choices.count == 1 {
            reply("Did you mean \(describe(choices[0]))?", suggestions: ["Yes", "No"])
        } else {
            reply("Which one do you mean: \(choices.map(describe).formatted(.list(type: .or)))?", suggestions: choices.map(\.name))
        }
    }

    private func matchCategory(_ name: String, in categories: [BudgetCategory]) -> BudgetCategory? {
        categories.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            ?? categories.first { name.count >= 3 && (name.localizedCaseInsensitiveContains($0.name) || $0.name.localizedCaseInsensitiveContains(name)) }
    }

    private func reply(_ text: String, suggestions: [String] = []) {
        messages.append(Message(fromUser: false, text: text, suggestions: suggestions))
    }
}
