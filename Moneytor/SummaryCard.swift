import SwiftUI

struct SummaryCard: View {
    let totalIncome: Decimal
    let totalLimit: Decimal
    /// What's still unspent of this month's limits. Negative when spending went over.
    let remaining: Decimal

    var body: some View {
        let shortfall = totalLimit - totalIncome
        let isShort = shortfall > 0
        let isOver = remaining < 0
        let spent = totalLimit - remaining

        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isOver ? "Over Budget This Month" : "Expenses Left This Month")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(abs(remaining), format: .currency(code: currencyCode))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(isOver ? .red : .primary)
                ProgressView(value: totalLimit > 0 ? min(max(NSDecimalNumber(decimal: spent / totalLimit).doubleValue, 0), 1) : 0)
                    .tint(isOver ? .red : .green)
                Text("\(spent.formatted(.currency(code: currencyCode))) in expenses of \(totalLimit.formatted(.currency(code: currencyCode)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 12) {
                SummaryStat(title: "Total Income", amount: totalIncome, icon: "arrow.down.circle.fill", tint: .green)
                SummaryStat(title: "Expense Limits", amount: totalLimit, icon: "arrow.up.circle.fill", tint: .orange)
            }

            // How income compares with the limits: money still without a plan, a perfect match, or limits
            // asking for more than comes in. Hidden until there's something to compare.
            if totalIncome > 0 || totalLimit > 0 {
                let difference = abs(shortfall).formatted(.currency(code: currencyCode))
                let (icon, tint, title, detail): (String, Color, String, String) = if totalIncome == 0 {
                    ("banknote.fill", .orange, "Add your income",
                     "Add it in the Income tab to see whether your limits fit what you earn.")
                } else if isShort {
                    ("exclamationmark.triangle.fill", .orange, "\(difference) more than you earn",
                     "Your limits add up to more than your income. Lower a limit or add income to balance it.")
                } else if shortfall == 0 {
                    ("checkmark.seal.fill", .green, "Every bit of income has a plan",
                     "Your limits match your income exactly.")
                } else {
                    ("tray.full.fill", .accentColor, "\(difference) left to plan",
                     "Income you haven't given a limit yet. Put it toward an expense or keep it as savings.")
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct SummaryStat: View {
    let title: String
    let amount: Decimal
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(amount, format: .currency(code: currencyCode))
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
