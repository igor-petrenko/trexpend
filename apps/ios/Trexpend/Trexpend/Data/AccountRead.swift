import Foundation

nonisolated enum AccountRead {
    static func catalog(_ db: SQLiteConnection, generation: UUID) throws -> AccountCatalog {
        let currencies = try HomeRead.currencies(db)
        let banks = try db.rows("SELECT * FROM banks ORDER BY name COLLATE NOCASE,id").map {
            try BankInfo(id: $0.integer("id"), name: $0.text("name"), assetName: $0.optionalText("asset_name"))
        }
        var balances: [Int64: Decimal] = [:]
        let rows = try db.rows("SELECT * FROM accounts ORDER BY favorite DESC,name COLLATE NOCASE,id")
        let indexed = Dictionary(uniqueKeysWithValues: currencies.map { ($0.id, $0) })
        var precision: [Int64: Int] = [:]
        for row in rows {
            let id = try row.integer("id")
            guard let currency = indexed[try row.integer("currency_id")] else { throw DatabaseError.invalidData }
            precision[id] = currency.decimalPlaces
            balances[id] = try MoneyCodec.decode(row.text("initial_balance"), places: currency.decimalPlaces, signed: true)
        }
        // SQLite selects each native-currency effect; all monetary arithmetic stays Decimal.
        try db.forEach("""
            SELECT account_id AS id,amount AS amount,CASE WHEN transaction_type=2 THEN 1 ELSE -1 END AS direction FROM transactions
            UNION ALL SELECT to_account_id,to_amount,1 FROM transactions WHERE transaction_type=3
            UNION ALL SELECT fee_account_id,fee,-1 FROM transactions WHERE transaction_type=3
            """) { row in
            let id = try row.integer("id")
            guard let places = precision[id], let before = balances[id] else { throw DatabaseError.invalidData }
            let value = try MoneyCodec.decode(row.text("amount"), places: places)
            balances[id] = try row.integer("direction") == 1 ? DecimalArithmetic.add(before, value) : DecimalArithmetic.subtract(before, value)
        }
        let accounts = try rows.map { row -> ManagedAccount in
            let id = try row.integer("id")
            guard let type = try HomeAccountType(rawValue: Int(row.integer("account_type"))),
                  let currency = indexed[try row.integer("currency_id")], let balance = balances[id] else { throw DatabaseError.invalidData }
            return try ManagedAccount(id: id, name: row.text("name"), bankID: row.optionalInteger("bank_id"), type: type,
                currency: currency, balance: balance, isOpen: row.integer("status") == 1, favorite: row.integer("favorite") == 1,
                appearance: AccountAppearance(imageID: row.optionalInteger("image_id"), customImageID: row.optionalInteger("custom_image_id"), color: row.optionalText("color")))
        }
        return AccountCatalog(generation: generation, accounts: accounts, banks: banks, currencies: currencies)
    }

    static func context(_ db: SQLiteConnection, accountID: Int64?, generation: UUID) throws -> AccountEditorContext {
        let original: SQLRow?
        if let accountID {
            guard let row = try db.rows("SELECT * FROM accounts WHERE id=?", parameters: [.integer(accountID)]).first else { throw AccountError.changed }
            original = row
        } else { original = nil }
        return try AccountEditorContext(generation: generation, original: original, catalog: catalog(db, generation: generation),
            hasTransactions: accountID.map { try hasTransactions(db, id: $0) } ?? false)
    }

    static func hasTransactions(_ db: SQLiteConnection, id: Int64) throws -> Bool {
        try !db.rows("SELECT id FROM transactions WHERE account_id=? OR to_account_id=? OR fee_account_id=? LIMIT 1",
            parameters: [.integer(id), .integer(id), .integer(id)]).isEmpty
    }
}
