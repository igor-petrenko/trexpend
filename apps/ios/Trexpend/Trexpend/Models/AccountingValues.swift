import Foundation

nonisolated struct LedgerCurrency: Equatable, Sendable {
    let id: Int64
    let decimalPlaces: Int

    init(id: Int64, decimalPlaces: Int) throws {
        guard id > 0, (0...18).contains(decimalPlaces) else { throw FinanceError.invalidPrecision }
        self.id = id
        self.decimalPlaces = decimalPlaces
    }
}

nonisolated struct LedgerAccount: Equatable, Sendable {
    let id: Int64
    let currencyID: Int64
    let initialBalance: Decimal
    var isClosed = false
}

nonisolated enum LedgerTransactionType: Int, Sendable {
    case expense = 1
    case income = 2
    case transfer = 3
}

// Accounting inputs deliberately omit presentation and persistence metadata.
nonisolated struct AccountingTransaction: Equatable, Sendable {
    let type: LedgerTransactionType
    let accountID: Int64
    let amount: Decimal
    let date: LocalDateTime
    var toAccountID: Int64?
    var toAmount: Decimal?
    var fee: Decimal = 0
    var feeAccountID: Int64?
}

nonisolated struct PeriodTotals: Equatable, Sendable {
    var income: Decimal = 0
    var expenses: Decimal = 0
}

nonisolated struct MonetaryAmount: Equatable, Sendable {
    let value: Decimal
    let currencyID: Int64
}

nonisolated struct ExchangeRate: Equatable, Sendable {
    let fromCurrencyID: Int64
    let toCurrencyID: Int64
    let value: Decimal
}
