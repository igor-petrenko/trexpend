import SwiftUI

struct StatisticsSummaryView: View {
    let balanceTitle: String
    let balance: Decimal?
    let currency: CurrencyInfo
    let month: CalendarMonth
    let income: Decimal?
    let expenses: Decimal?
    let difference: Decimal?
    var balanceDetail: String? = nil
    var balanceEquivalent: String? = nil
    @Environment(\.dynamicTypeSize) private var textSize

    private var showsDifference: Bool { income.map { $0 != 0 } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(balanceTitle).fixedSize()
                    Spacer(minLength: 12)
                    balanceAmount.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(balanceTitle)
                    balanceAmount.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.subheadline)
            if let balanceDetail {
                Text(balanceDetail).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text(MoneyPresentation.month(month)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(currency.code).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { metrics }
            } else {
                HStack(alignment: .top, spacing: 10) { metrics }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private var balanceAmount: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(amount(balance)).font(.headline).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if let balanceEquivalent {
                Text("\u{2248} " + balanceEquivalent)
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .accessibilityLabel("Approximately " + balanceEquivalent)
            }
        }
    }

    @ViewBuilder private var metrics: some View {
        metric("Income", symbol: "arrow.up.right", value: income, color: .green)
        metric("Expenses", symbol: "arrow.down.right", value: expenses, color: .red)
        if showsDifference {
            metric("Difference", symbol: nil, value: difference,
                   color: difference.map { $0 < 0 ? .red : ($0 > 0 ? .green : .primary) } ?? .secondary)
        }
    }

    private func amount(_ value: Decimal?) -> String {
        value.map { MoneyPresentation.number($0, places: currency.decimalPlaces) } ?? "Unavailable"
    }

    private func metric(_ title: String, symbol: String?, value: Decimal?, color: Color) -> some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }.font(.caption).lineLimit(1).minimumScaleFactor(0.7)
            Text(amount(value)).font(.subheadline.weight(.semibold)).monospacedDigit()
                .lineLimit(textSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(color)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
