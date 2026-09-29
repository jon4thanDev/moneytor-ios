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

            Label(isShort
                  ? "Limits are \(shortfall.formatted(.currency(code: currencyCode))) more than your income"
                  : "\((-shortfall).formatted(.currency(code: currencyCode))) of income not budgeted",
                  systemImage: isShort ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(isShort ? .red : .green)
                .frame(maxWidth: .infinity, alignment: .leading)
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
