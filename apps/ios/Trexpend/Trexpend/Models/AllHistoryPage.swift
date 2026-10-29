import Foundation

nonisolated struct AllHistoryCursor: Equatable, Sendable {
    let generation: UUID
    let date: String
    let id: Int64
}

nonisolated struct HistoryAccountContext: Equatable, Sendable {
    let id: Int64
    let name: String
    let currency: CurrencyInfo
}

nonisolated struct AllHistoryRow: Identifiable, Equatable, Sendable {
    let transaction: HistoryRow
    let source: HistoryAccountContext
    let destination: HistoryAccountContext?
    var id: Int64 { transaction.id }

}

nonisolated struct AllHistoryPage: Equatable, Sendable {
    let rows: [AllHistoryRow]
    let next: AllHistoryCursor?
}

nonisolated struct AllHistorySnapshot: Equatable, Sendable {
    let summary: HomeSnapshot
    let page: AllHistoryPage
}

nonisolated struct AllHistoryDay: Identifiable {
    let id: String
    var rows: [AllHistoryRow]
}
