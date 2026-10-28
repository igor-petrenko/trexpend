import SwiftUI

struct AccountSummaryView: View {
    let content: AccountHistorySnapshot

    var body: some View {
        StatisticsSummaryView(balanceTitle: "Balance", balance: content.account.balance,
                              currency: content.account.currency, month: content.month,
                              income: content.account.income, expenses: content.account.expenses,
                              difference: content.difference, balanceDetail: detail,
                              balanceEquivalent: equivalent)
    }

    private var equivalent: String? {
        guard content.displayCurrency.id != content.account.currency.id,
              let converted = content.convertedBalance else { return nil }
        return MoneyPresentation.number(converted, places: content.displayCurrency.decimalPlaces) + " " + content.displayCurrency.code
    }

    private var detail: String? {
        var parts: [String] = []
        if let bank = content.account.bank, !bank.isEmpty { parts.append(bank) }
        if content.displayCurrency.id != content.account.currency.id, content.convertedBalance == nil {
            parts.append("Converted balance unavailable: exchange rate missing.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }
}
