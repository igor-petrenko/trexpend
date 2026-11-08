import Foundation

nonisolated enum TransactionWrite {
    struct Values {
        let draft: TransactionDraft
        let amount: String
        let receiverAmount: String?
        let fee: String
        let occurrence: OccurrenceDate
        let roundedFields: [String]
    }

    static func validate(_ draft: TransactionDraft, context: TransactionEditorContext, now: Date, timeZone: TimeZone) throws -> Values {
        let original = context.original
        let originalSource = try original?.integer("account_id")
        let originalReceiver = try original?.optionalInteger("to_account_id")
        func account(_ id: Int64?) throws -> EditorAccount {
            guard let account = context.accounts.first(where: { $0.id == id }),
                  account.isOpen || account.id == originalSource || account.id == originalReceiver else { throw EditorError.account }
            return account
        }
        let source = try account(draft.accountID)
        let originalCategory = try original?.integer("category_id")
        guard context.categories.contains(where: { $0.id == draft.categoryID && ($0.active || $0.id == originalCategory) }) else { throw EditorError.category }
        var rounded: [String] = []
        func money(_ text: String, currency: CurrencyInfo, label: String) throws -> String {
            let value = try MoneyCodec.parseInput(text, places: currency.decimalPlaces)
            let encoded = try MoneyCodec.encode(value, places: currency.decimalPlaces)
            // Decimal parsing is exact in MoneyCodec; trailing zero differences are harmless.
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            if Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) != value { rounded.append(label + ": " + encoded + " " + currency.code) }
            return encoded
        }
        let amount = try money(draft.amount, currency: source.currency, label: "Amount")
        var received: String?
        var fee = try MoneyCodec.encode(0, places: source.currency.decimalPlaces)
        if draft.type == .transfer {
            let receiver = try account(draft.receiverID)
            guard receiver.id != source.id else { throw EditorError.receiver }
            received = try money(draft.receiverAmount, currency: receiver.currency, label: "Received amount")
            fee = try money(draft.fee, currency: draft.feeFromReceiver ? receiver.currency : source.currency, label: "Fee")
        }
        let local = try LocalDateTime(storage: draft.localDate)
        let originalOccurrence: OccurrenceDate? = try original.map { try OccurrenceDate(local: LocalDateTime(storage: $0.text("date")), withOffset: $0.optionalText("date_with_offset")) }
        let occurrence = try TransactionDateRules.forSave(original: originalOccurrence,
            editedLocal: originalOccurrence?.local == local ? nil : local, now: now, timeZone: timeZone)
        return Values(draft: draft, amount: amount, receiverAmount: received, fee: fee, occurrence: occurrence, roundedFields: rounded)
    }

    static func save(_ db: SQLiteConnection, draft: TransactionDraft, context: TransactionEditorContext, now: Date, timeZone: TimeZone) throws -> Int64 {
        try db.transaction {
            if let original = context.original {
                guard let current = try db.rows("SELECT * FROM transactions WHERE id=?", parameters: [.integer(original.integer("id"))]).first,
                      current.values == original.values else { throw EditorError.changed }
            }
            let values = try validate(draft, context: context, now: now, timeZone: timeZone)
            let timestamp = TransactionDateRules.technicalTimestamp(now)
            let transfer = draft.type == .transfer
            let oldNotes = try context.original?.optionalText("notes")
            let notes: SQLValue = draft.notes == (oldNotes ?? "") && context.original != nil ? oldNotes.map(SQLValue.text) ?? .null : (draft.notes.isEmpty ? .null : .text(draft.notes))
            var fields: [SQLValue] = [.integer(Int64(draft.type.rawValue)), .integer(draft.accountID!), .text(values.amount),
                transfer ? draft.receiverID.map(SQLValue.integer) ?? .null : .null,
                values.receiverAmount.map(SQLValue.text) ?? .null, .text(values.occurrence.local.storage),
                values.occurrence.withOffset.map(SQLValue.text) ?? .null, .integer(draft.categoryID!), notes, .text(values.fee),
                transfer ? (draft.feeFromReceiver ? draft.receiverID : draft.accountID).map(SQLValue.integer) ?? .null : .null,
                .text(timestamp)]
            let id: Int64
            if let original = context.original {
                id = try original.integer("id")
                fields.append(.integer(id))
                try db.run("UPDATE transactions SET transaction_type=?,account_id=?,amount=?,to_account_id=?,to_amount=?,date=?,date_with_offset=?,category_id=?,notes=?,fee=?,fee_account_id=?,updated_at=? WHERE id=?", parameters: fields)
            } else {
                fields.append(.text(timestamp))
                try db.run("INSERT INTO transactions(transaction_type,account_id,amount,to_account_id,to_amount,date,date_with_offset,category_id,notes,fee,fee_account_id,updated_at,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", parameters: fields)
                id = try db.rows("SELECT last_insert_rowid() AS id")[0].integer("id")
                try db.run("UPDATE app_settings SET last_created_category_id=? WHERE id=1", parameters: [.integer(draft.categoryID!)])
                if transfer {
                    try db.run("INSERT INTO transfer_defaults(source_account_id,destination_account_id) VALUES (?,?) ON CONFLICT(source_account_id) DO UPDATE SET destination_account_id=excluded.destination_account_id", parameters: [.integer(draft.accountID!), .integer(draft.receiverID!)])
                    try db.run("UPDATE app_settings SET transfer_category_id=? WHERE id=1 AND transfer_category_id IS NULL", parameters: [.integer(draft.categoryID!)])
                }
            }
            return id
        }
    }
}
