import Foundation

nonisolated enum AccountWrite {
    static func checkOriginal(_ db: SQLiteConnection, context: AccountEditorContext) throws {
        if let original = context.original {
            guard let current = try db.rows("SELECT * FROM accounts WHERE id=?", parameters: [.integer(original.integer("id"))]).first,
                  current.values == original.values else { throw AccountError.changed }
        }
    }

    static func save(_ db: SQLiteConnection, draft: AccountDraft, context: AccountEditorContext, now: Date) throws -> Int64 {
        try checkOriginal(db, context: context)
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AccountError.name }
        guard let currency = try HomeRead.currencies(db).first(where: { $0.id == draft.currencyID }),
              try context.original == nil || context.original!.integer("currency_id") == currency.id else { throw AccountError.currency }
        let initial = try MoneyCodec.encode(MoneyCodec.parseInput(draft.initialBalance, places: currency.decimalPlaces, signed: true), places: currency.decimalPlaces)
        let limit: SQLValue = try draft.creditLimit.isEmpty ? .null : .text(MoneyCodec.encode(MoneyCodec.parseInput(draft.creditLimit, places: currency.decimalPlaces), places: currency.decimalPlaces))
        for date in [draft.openDate, draft.expiryDate, draft.closeDate] where !date.isEmpty {
            guard date.count == 10 else { throw FinanceError.invalidDate }
            _ = try LocalDateTime(storage: date + "T00:00:00")
        }
        if let bank = draft.bankID {
            guard try !db.rows("SELECT id FROM banks WHERE id=?", parameters: [.integer(bank)]).isEmpty else { throw DatabaseError.invalidData }
        }
        if let image = draft.appearance.imageID {
            guard (1...4).contains(image) else { throw DatabaseError.invalidData }
        }
        // Existing custom image references can only be retained from this account.
        let oldCustom = try context.original?.optionalInteger("custom_image_id")
        guard draft.appearance.customImageID == nil || draft.appearance.customImageID == oldCustom else { throw AccountError.image }
        var custom = draft.appearance.customImageID
        if let data = draft.newImage {
            try AccountImageCodec.validate(data)
            try db.run("INSERT INTO account_custom_images(png_data) VALUES (?)", parameters: [.blob(data)])
            custom = try db.rows("SELECT last_insert_rowid() AS id")[0].integer("id")
        }
        let timestamp = TransactionDateRules.technicalTimestamp(now)
        func nullable(_ text: String, field: String) throws -> SQLValue {
            if let original = context.original, text == (try original.optionalText(field) ?? "") {
                return try original.optionalText(field).map(SQLValue.text) ?? .null
            }
            return text.isEmpty ? .null : .text(text)
        }
        let closeDate: SQLValue
        let oldOpen = try context.original?.integer("status") == 1
        if draft.isOpen { closeDate = .null }
        else if context.original == nil || oldOpen {
            closeDate = .text(try LocalDateTime(instant: now, timeZone: .current).calendarDay)
        } else { closeDate = try nullable(draft.closeDate, field: "close_date") }
        var values: [SQLValue] = [.text(draft.name), .integer(currency.id), .text(initial),
            try nullable(draft.openDate, field: "open_date"), try nullable(draft.expiryDate, field: "exp_date"), closeDate,
            .integer(draft.isOpen ? 1 : 2), .integer(Int64(draft.type.rawValue)),
            try nullable(draft.accountNumber, field: "account_number"), limit, .integer(draft.favorite ? 1 : 0),
            draft.appearance.imageID.map(SQLValue.integer) ?? .null, draft.appearance.color.map(SQLValue.text) ?? .null,
            try nullable(draft.notes, field: "notes"), .text(timestamp), draft.bankID.map(SQLValue.integer) ?? .null, custom.map(SQLValue.integer) ?? .null]
        let originalBankID = try context.original?.optionalInteger("bank_id")
        let legacyBank = try draft.bankID == originalBankID ? context.original?.optionalText("bank") : nil
        values.append(legacyBank.map(SQLValue.text) ?? .null)
        let id: Int64
        if let original = context.original {
            id = try original.integer("id")
            values.append(.integer(id))
            try db.run("""
                UPDATE accounts SET name=?,currency_id=?,initial_balance=?,open_date=?,exp_date=?,close_date=?,status=?,account_type=?,
                account_number=?,credit_limit=?,favorite=?,image_id=?,color=?,notes=?,updated_at=?,bank_id=?,custom_image_id=?,bank=? WHERE id=?
                """, parameters: values)
        } else {
            values.append(.text(timestamp))
            try db.run("""
                INSERT INTO accounts(name,currency_id,initial_balance,open_date,exp_date,close_date,status,account_type,
                account_number,credit_limit,favorite,image_id,color,notes,updated_at,bank_id,custom_image_id,bank,created_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, parameters: values)
            id = try db.rows("SELECT last_insert_rowid() AS id")[0].integer("id")
        }
        if !draft.isOpen {
            try db.run("UPDATE app_settings SET default_account_id=NULL WHERE default_account_id=?", parameters: [.integer(id)])
        }
        try removeUnusedImage(db, id: oldCustom)
        return id
    }

    static func delete(_ db: SQLiteConnection, context: AccountEditorContext) throws {
        guard let original = context.original else { throw AccountError.changed }
        try checkOriginal(db, context: context)
        let id = try original.integer("id")
        guard try !AccountRead.hasTransactions(db, id: id) else { throw AccountError.referenced }
        try db.run("UPDATE app_settings SET default_account_id=NULL WHERE default_account_id=?", parameters: [.integer(id)])
        try db.run("DELETE FROM accounts WHERE id=?", parameters: [.integer(id)])
        try removeUnusedImage(db, id: original.optionalInteger("custom_image_id"))
    }

    private static func removeUnusedImage(_ db: SQLiteConnection, id: Int64?) throws {
        if let id {
            try db.run("DELETE FROM account_custom_images WHERE id=? AND NOT EXISTS (SELECT 1 FROM accounts WHERE custom_image_id=?)",
                parameters: [.integer(id), .integer(id)])
        }
    }
}
