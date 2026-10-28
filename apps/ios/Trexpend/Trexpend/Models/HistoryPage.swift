import Foundation

nonisolated struct HistoryCursor: Equatable, Sendable {
    let generation: UUID
    let accountID: Int64
    let date: String
    let id: Int64
}

nonisolated struct HistoryRow: Identifiable, Equatable, Sendable {
    let id: Int64
    let type: LedgerTransactionType
    let date: LocalDateTime
    let category: String
    let symbol: String?
    let notes: String?
    let incoming: Bool
    let amount: Decimal
    let currency: CurrencyInfo
    let counterparty: String?
    let counterpartAmount: Decimal?
    let counterpartCurrency: CurrencyInfo?
    let fee: Decimal
    let feeCurrency: CurrencyInfo?
    let feeAccountName: String?
}

nonisolated struct HistoryPage: Equatable, Sendable {
    let rows: [HistoryRow]
    let next: HistoryCursor?
}

nonisolated struct AccountHistorySnapshot: Equatable, Sendable {
    let generation: UUID
    let account: HomeAccountRow
    let month: CalendarMonth
    let displayCurrency: CurrencyInfo
    let convertedBalance: Decimal?
    let difference: Decimal
    let page: HistoryPage
}

nonisolated struct HistoryDay: Identifiable {
    let id: String
    var rows: [HistoryRow]
}
