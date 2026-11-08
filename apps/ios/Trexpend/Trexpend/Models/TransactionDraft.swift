import Foundation

nonisolated struct EditorAccount: Identifiable, Sendable {
    let id: Int64
    let name: String
    let currency: CurrencyInfo
    let isOpen: Bool
    let favorite: Bool
}

nonisolated struct EditorCategory: Identifiable, Sendable {
    let id: Int64
    let name: String
    let parentID: Int64?
    let active: Bool
    let favorite: Bool
}

nonisolated struct TransactionEditorContext: Sendable {
    let generation: UUID
    let accounts: [EditorAccount]
    let categories: [EditorCategory]
    let settings: DatasetSettings
    let converter: CurrencyConverter
    let original: SQLRow?
}

nonisolated struct TransactionDraft: Equatable, Sendable {
    var type: LedgerTransactionType = .expense
    var accountID: Int64?
    var categoryID: Int64?
    var amount = ""
    var receiverID: Int64?
    var receiverAmount = ""
    var receiverIsManual = false
    var receiverAmountIsManual = false
    var fee = "0"
    var feeFromReceiver = false
    var localDate: String
    var notes = ""

    init(localDate: String) { self.localDate = localDate }

    static func editing(_ row: SQLRow) throws -> Self {
        var draft = Self(localDate: try row.text("date"))
        guard let type = LedgerTransactionType(rawValue: Int(try row.integer("transaction_type"))) else { throw DatabaseError.invalidData }
        draft.type = type
        draft.accountID = try row.integer("account_id")
        draft.categoryID = try row.integer("category_id")
        draft.amount = try row.text("amount")
        draft.receiverID = try row.optionalInteger("to_account_id")
        draft.receiverAmount = try row.optionalText("to_amount") ?? ""
        draft.receiverIsManual = type == .transfer
        draft.receiverAmountIsManual = type == .transfer
        draft.fee = try row.text("fee")
        let feeAccount = try row.optionalInteger("fee_account_id")
        draft.feeFromReceiver = draft.receiverID != nil && feeAccount == draft.receiverID
        draft.notes = try row.optionalText("notes") ?? ""
        return draft
    }

    mutating func changeType(_ newType: LedgerTransactionType, transferCategory: Int64?) {
        guard type != newType else { return }
        type = newType
        if newType == .transfer { categoryID = transferCategory }
        else {
            receiverID = nil; receiverAmount = ""; receiverIsManual = false
            receiverAmountIsManual = false; fee = "0"; feeFromReceiver = false
        }
    }
}

nonisolated struct TransactionCommit: Sendable {
    let id: Int64
    let snapshot: DatabaseSnapshot
}

nonisolated enum EditorError: Error, LocalizedError {
    case account, category, receiver, changed
    var errorDescription: String? {
        switch self {
        case .account: "Choose an available account."
        case .category: "Choose an available category."
        case .receiver: "Choose a different receiving account."
        case .changed: "This transaction changed or no longer exists. Reopen it before saving."
        }
    }
}
