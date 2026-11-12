import Foundation

nonisolated enum TransactionEditorRead {
    static func context(_ db: SQLiteConnection, snapshot: DatabaseSnapshot, transactionID: Int64?) throws -> TransactionEditorContext {
        let accounts = try accounts(db)
        let categories = try CategoryRead.catalog(db, generation: snapshot.generation, includeUsage: false).categories.map {
            EditorCategory(id: $0.id, name: $0.name, parentID: $0.parentID, active: $0.active, favorite: $0.favorite, symbol: $0.symbol)
        }
        let rates = try db.rows("SELECT from_currency_id,to_currency_id,rate FROM exchange_rates").map { row in
            try ExchangeRate(fromCurrencyID: row.integer("from_currency_id"), toCurrencyID: row.integer("to_currency_id"), value: MoneyCodec.decodeRate(row.text("rate")))
        }
        var original: SQLRow?
        if let transactionID {
            guard let row = try db.rows("SELECT * FROM transactions WHERE id=?", parameters: [.integer(transactionID)]).first else { throw EditorError.changed }
            original = row
        }
        return try TransactionEditorContext(generation: snapshot.generation, accounts: accounts, categories: categories,
                                             settings: snapshot.settings, converter: CurrencyConverter(rates: rates), original: original)
    }

    static func accounts(_ db: SQLiteConnection) throws -> [EditorAccount] {
        let currencies = try Dictionary(uniqueKeysWithValues: HomeRead.currencies(db).map { ($0.id, $0) })
        return try db.rows("SELECT id,name,currency_id,status,favorite,account_type,image_id,custom_image_id,color FROM accounts ORDER BY favorite DESC,name,id").map { row in
            guard let currency = currencies[try row.integer("currency_id")],
                  let type = try HomeAccountType(rawValue: Int(row.integer("account_type"))) else { throw DatabaseError.invalidData }
            return try EditorAccount(id: row.integer("id"), name: row.text("name"), currency: currency,
                                     isOpen: row.integer("status") == 1, favorite: row.integer("favorite") == 1, type: type,
                                     appearance: AccountAppearance(imageID: row.optionalInteger("image_id"), customImageID: row.optionalInteger("custom_image_id"), color: row.optionalText("color")))
        }
    }

    static func recipient(_ db: SQLiteConnection, source: Int64) throws -> Int64? {
        let parameters: [SQLValue] = [.integer(source)]
        if let row = try db.rows("SELECT d.destination_account_id AS id FROM transfer_defaults d JOIN accounts a ON a.id=d.destination_account_id WHERE d.source_account_id=? AND a.status=1 AND a.id<>d.source_account_id", parameters: parameters).first { return try row.integer("id") }
        if let row = try db.rows("SELECT t.to_account_id AS id FROM transactions t JOIN accounts a ON a.id=t.to_account_id WHERE t.account_id=? AND t.transaction_type=3 AND a.status=1 AND a.id<>t.account_id GROUP BY t.to_account_id ORDER BY count(*) DESC,max(t.date) DESC,(SELECT latest.id FROM transactions latest WHERE latest.transaction_type=3 AND latest.account_id=t.account_id AND latest.to_account_id=t.to_account_id ORDER BY latest.date DESC,latest.id DESC LIMIT 1) DESC,t.to_account_id LIMIT 1", parameters: parameters).first { return try row.integer("id") }
        let others = try db.rows("SELECT id FROM accounts WHERE status=1 AND id<>? ORDER BY id LIMIT 2", parameters: parameters)
        return others.count == 1 ? try others[0].integer("id") : nil
    }
}
