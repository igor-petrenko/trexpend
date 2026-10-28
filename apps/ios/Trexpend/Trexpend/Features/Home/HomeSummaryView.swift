import SwiftUI

struct HomeSummaryView: View {
    let content: HomeSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatisticsSummaryView(balanceTitle: "Total balance", balance: content.totalBalance,
                                  currency: content.currency, month: content.month,
                                  income: content.income, expenses: content.expenses,
                                  difference: content.difference)
            if content.hasUnavailableConversion {
                Text("Some totals are unavailable because an exchange rate is missing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
