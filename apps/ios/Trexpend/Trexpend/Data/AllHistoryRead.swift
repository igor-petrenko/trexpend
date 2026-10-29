import Foundation

// Called only on the serial database worker inside a coherent read transaction.
nonisolated enum AllHistoryRead {
    static func snapshot(_ db: SQLiteConnection, generation: UUID, month: CalendarMonth) throws -> AllHistorySnapshot {
        let summary = try HomeRead.snapshot(db, generation: generation, month: month)
        return try AllHistorySnapshot(summary: summary, page: page(db, generation: generation, cursor: nil))
    }

    static func pageQuery(cursor: Bool) -> String {
        let boundary = cursor ? "WHERE (date,id) < (?,?)" : ""
        return """
        SELECT t.*,c.name AS category_name,i.system_name AS icon_symbol,
               a.name AS source_name,a.currency_id AS source_currency_id,
               b.name AS destination_name,b.currency_id AS destination_currency_id,
               f.name AS fee_account_name,f.currency_id AS fee_currency_id
        FROM (SELECT * FROM transactions \(boundary) ORDER BY date DESC,id DESC LIMIT 51) t
        JOIN accounts a ON a.id=t.account_id
        JOIN categories c ON c.id=t.category_id
        LEFT JOIN accounts b ON b.id=t.to_account_id
        LEFT JOIN accounts f ON f.id=t.fee_account_id
        LEFT JOIN category_icons i ON i.id=c.icon_id
        ORDER BY t.date DESC,t.id DESC
        """
    }

    static func page(_ db: SQLiteConnection, generation: UUID, cursor: AllHistoryCursor?) throws -> AllHistoryPage {
        if let cursor {
            guard cursor.generation == generation else { throw DatabaseError.staleDataset }
            _ = try LocalDateTime(storage: cursor.date)
        }
        let currencies = Dictionary(uniqueKeysWithValues: try HomeRead.currencies(db).map { ($0.id, $0) })
        let parameters: [SQLValue] = cursor.map { [.text($0.date), .integer($0.id)] } ?? []
        let stored = try db.rows(pageQuery(cursor: cursor != nil), parameters: parameters)
        let rows = try stored.prefix(50).map { row -> AllHistoryRow in
            guard let type = try LedgerTransactionType(rawValue: Int(row.integer("transaction_type"))),
                  let currency = currencies[try row.integer("source_currency_id")] else { throw DatabaseError.invalidData }
            let source = try HistoryAccountContext(id: row.integer("account_id"), name: row.text("source_name"), currency: currency)
            var destination: HistoryAccountContext?
            var received: Decimal?
            if let id = try row.optionalInteger("to_account_id") {
                guard let target = currencies[try row.integer("destination_currency_id")] else { throw DatabaseError.invalidData }
                destination = try HistoryAccountContext(id: id, name: row.text("destination_name"), currency: target)
                received = try MoneyCodec.decode(row.text("to_amount"), places: target.decimalPlaces)
            }
            guard type != .transfer || destination != nil else { throw DatabaseError.invalidData }
            let feeCurrency = try row.optionalInteger("fee_currency_id").flatMap { currencies[$0] }
            let transaction = try HistoryRow(id: row.integer("id"), type: type,
                date: LocalDateTime(storage: row.text("date")), category: row.text("category_name"),
                symbol: row.optionalText("icon_symbol"), notes: row.optionalText("notes"), incoming: type == .income,
                amount: MoneyCodec.decode(row.text("amount"), places: currency.decimalPlaces), currency: currency,
                counterparty: destination?.name, counterpartAmount: received, counterpartCurrency: destination?.currency,
                fee: MoneyCodec.decode(row.text("fee"), places: (feeCurrency ?? currency).decimalPlaces),
                feeCurrency: feeCurrency, feeAccountName: row.optionalText("fee_account_name"))
            return AllHistoryRow(transaction: transaction, source: source, destination: destination)
        }
        let next = stored.count > 50 ? rows.last.map {
            AllHistoryCursor(generation: generation, date: $0.transaction.date.storage, id: $0.id)
        } : nil
        return AllHistoryPage(rows: rows, next: next)
    }
}
