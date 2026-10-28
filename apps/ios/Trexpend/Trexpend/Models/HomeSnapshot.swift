import Foundation

nonisolated struct CurrencyInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    let code: String
    let name: String
    let decimalPlaces: Int

    var ledger: LedgerCurrency { get throws { try LedgerCurrency(id: id, decimalPlaces: decimalPlaces) } }
}

nonisolated enum HomeAccountType: Int, CaseIterable, Identifiable, Sendable {
    case checking = 1, creditCard, cash, deposit
    static let displayOrder: [HomeAccountType] = [.creditCard, .checking, .cash, .deposit]
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .checking: "Checking"
        case .creditCard: "Credit Cards"
        case .cash: "Cash"
        case .deposit: "Deposits"
        }
    }
    var symbol: String {
        switch self {
        case .checking: "creditcard"
        case .creditCard: "creditcard.fill"
        case .cash: "banknote"
        case .deposit: "building.columns"
        }
    }
}

nonisolated struct HomeAccountRow: Identifiable, Equatable, Sendable {
    let id: Int64
    let name: String
    let bank: String?
    let type: HomeAccountType
    let favorite: Bool
    let currency: CurrencyInfo
    let balance: Decimal
    let income: Decimal
    let expenses: Decimal
    let hasActivity: Bool
}

nonisolated struct HomeAccountGroup: Identifiable, Equatable, Sendable {
    let type: HomeAccountType
    let accounts: [HomeAccountRow]
    var id: HomeAccountType { type }
}

nonisolated struct HomeSnapshot: Equatable, Sendable {
    let generation: UUID
    let month: CalendarMonth
    let currency: CurrencyInfo
    let totalBalance: Decimal?
    let income: Decimal?
    let expenses: Decimal?
    let difference: Decimal?
    let groups: [HomeAccountGroup]
    let accountCount: Int

    var hasUnavailableConversion: Bool {
        totalBalance == nil || income == nil || expenses == nil || difference == nil
    }
}
