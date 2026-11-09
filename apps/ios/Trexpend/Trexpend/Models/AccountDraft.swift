import Foundation

nonisolated struct BankInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    let name: String
    let assetName: String?
}

nonisolated struct AccountAppearance: Equatable, Sendable {
    var imageID: Int64? = nil
    var customImageID: Int64? = nil
    var color: String? = nil
    var symbol: String? {
        switch imageID {
        case 1: "creditcard"
        case 2: "creditcard.fill"
        case 3: "banknote"
        case 4: "building.columns"
        default: nil
        }
    }
}

nonisolated struct ManagedAccount: Identifiable, Equatable, Sendable {
    let id: Int64
    let name: String
    let bankID: Int64?
    let type: HomeAccountType
    let currency: CurrencyInfo
    let balance: Decimal
    let isOpen: Bool
    let favorite: Bool
    let appearance: AccountAppearance
}

nonisolated struct AccountCatalog: Sendable {
    let generation: UUID
    let accounts: [ManagedAccount]
    let banks: [BankInfo]
    let currencies: [CurrencyInfo]
}

nonisolated struct AccountEditorContext: Sendable {
    let generation: UUID
    let original: SQLRow?
    let catalog: AccountCatalog
    let hasTransactions: Bool
}

nonisolated struct AccountDraft: Equatable, Sendable {
    var name = ""
    var type: HomeAccountType = .checking
    var currencyID: Int64? = nil
    var bankID: Int64? = nil
    var initialBalance = "0"
    var creditLimit = ""
    var accountNumber = ""
    var notes = ""
    var favorite = false
    var isOpen = true
    var openDate = ""
    var expiryDate = ""
    var closeDate = ""
    var appearance = AccountAppearance()
    var newImage: Data? = nil

    static func editing(_ row: SQLRow) throws -> Self {
        guard let type = try HomeAccountType(rawValue: Int(row.integer("account_type"))) else { throw DatabaseError.invalidData }
        return try Self(name: row.text("name"), type: type, currencyID: row.integer("currency_id"), bankID: row.optionalInteger("bank_id"),
            initialBalance: row.text("initial_balance"), creditLimit: row.optionalText("credit_limit") ?? "",
            accountNumber: row.optionalText("account_number") ?? "", notes: row.optionalText("notes") ?? "",
            favorite: row.integer("favorite") == 1, isOpen: row.integer("status") == 1,
            openDate: row.optionalText("open_date") ?? "", expiryDate: row.optionalText("exp_date") ?? "", closeDate: row.optionalText("close_date") ?? "",
            appearance: AccountAppearance(imageID: row.optionalInteger("image_id"), customImageID: row.optionalInteger("custom_image_id"), color: row.optionalText("color")))
    }
}

nonisolated enum AccountError: Error, LocalizedError {
    case name, changed, currency, referenced, image
    var errorDescription: String? {
        switch self {
        case .name: "Enter an account name."
        case .changed: "This account changed or was removed. Reopen it before saving."
        case .currency: "Select a currency. An existing account's currency cannot be changed."
        case .referenced: "This account has transactions. Close it instead of deleting it."
        case .image: "Choose a supported image no larger than 20 MB."
        }
    }
}
