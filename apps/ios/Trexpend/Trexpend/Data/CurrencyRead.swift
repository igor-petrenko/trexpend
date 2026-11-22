import Foundation

nonisolated enum CurrencyRead {
    static func legacy(_ db: SQLiteConnection) throws -> [ExchangeRate] {
        try db.rows("SELECT from_currency_id,to_currency_id,rate FROM exchange_rates ORDER BY id").map {
            try ExchangeRate(fromCurrencyID: $0.integer("from_currency_id"), toCurrencyID: $0.integer("to_currency_id"), value: MoneyCodec.decodeRate($0.text("rate")))
        }
    }

    static func sync(_ db: SQLiteConnection) throws -> CurrencySync {
        let rows = try db.rows("SELECT * FROM currency_sync_state")
        guard rows.count == 1, let row = rows.first, try row.integer("id") == 1 else { throw DatabaseError.invalidData }
        return try CurrencySync(automatic: row.integer("auto_update") == 1, canonical: row.text("valuation_mode") == "uah",
                                lastAttempt: row.optionalText("last_attempt_at"), lastSuccess: row.optionalText("last_success_at"), requestedDate: row.optionalText("last_success_requested_date"))
    }

    static func rates(_ db: SQLiteConnection) throws -> [Int64: CurrencyRate] {
        var result: [Int64: CurrencyRate] = [:]
        for row in try db.rows("SELECT * FROM currency_rates") {
            let id = try row.integer("currency_id")
            result[id] = try CurrencyRate(currencyID: id, nbu: row.optionalText("nbu_rate").map(MoneyCodec.decodeRate),
                                         effectiveDate: row.optionalText("nbu_effective_date"), fetchedAt: row.optionalText("nbu_fetched_at"),
                                         manual: row.optionalText("manual_rate").map(MoneyCodec.decodeRate), manualUpdatedAt: row.optionalText("manual_updated_at"))
        }
        return result
    }

    static func converter(_ db: SQLiteConnection) throws -> CurrencyConverter {
        let old = try legacy(db)
        guard try DatabaseMigrator.version(db) >= 6 else { return try CurrencyConverter(rates: old) }
        guard let anchor = try db.rows("SELECT id FROM currencies WHERE code='UAH' AND currency_type='fiat'").first?.integer("id") else { throw DatabaseError.invalidData }
        let values = try rates(db)
        return try CurrencyConverter(legacy: old, anchorID: anchor,
                                     coefficients: values.compactMapValues(\.nbu), overrides: values.compactMapValues(\.manual), canonical: sync(db).canonical)
    }

    static func catalog(_ db: SQLiteConnection, generation: UUID) throws -> CurrencyCatalog {
        let currencies = try HomeRead.currencies(db)
        guard let display = try db.rows("SELECT display_currency_id FROM app_settings WHERE id=1").first?.integer("display_currency_id") else { throw DatabaseError.invalidData }
        var used = Set(try db.rows("SELECT DISTINCT currency_id FROM accounts").map { try $0.integer("currency_id") })
        let values = try rates(db)
        used.insert(display)
        used.formUnion(values.values.filter { $0.manual != nil }.map(\.currencyID))
        let fiat = Set(try db.rows("SELECT id FROM currencies WHERE currency_type='fiat'").map { try $0.integer("id") })
        return try CurrencyCatalog(generation: generation, currencies: currencies, fiatIDs: fiat, usedIDs: used,
                                   displayID: display, rates: values, sync: sync(db), converter: converter(db),
                                   comparisonIDs: DatabaseMigrator.version(db) >= 7 ? CurrencyComparisonRead.ids(db) : [])
    }

    static func signature(_ db: SQLiteConnection) throws -> [String: String] {
        let canonical = try sync(db).canonical
        var signature = ["mode": canonical ? "uah" : "legacy"]
        for (id, value) in try rates(db) {
            if let rate = value.manual ?? (canonical ? value.nbu : nil) { signature[String(id)] = CurrencyConverter.text(rate) }
        }
        return signature
    }

    static func validate(_ db: SQLiteConnection) throws {
        let state = try sync(db)
        let values = try rates(db)
        let currencies = try db.rows("SELECT id,code,currency_type FROM currencies")
        let indexed = try Dictionary(uniqueKeysWithValues: currencies.map { (try $0.integer("id"), $0) })
        guard currencies.contains(where: { (try? $0.text("code").uppercased()) == "UAH" && (try? $0.text("currency_type")) == "fiat" }) else { throw DatabaseError.invalidData }
        func timestamp(_ value: String) throws {
            guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,9})?Z$"#, options: .regularExpression) != nil,
                  RateDates.instant(value) != nil else { throw DatabaseError.invalidData }
            _ = try LocalDateTime(storage: String(value.prefix(19)))
        }
        for time in [state.lastAttempt, state.lastSuccess].compactMap({ $0 }) { try timestamp(time) }
        if let day = state.requestedDate { try RateDates.validateDay(day) }
        for value in values.values {
            guard let currency = indexed[value.currencyID], try currency.text("currency_type") == "fiat",
                  try currency.text("code").uppercased() != "UAH" else { throw DatabaseError.invalidData }
            if let day = value.effectiveDate {
                try RateDates.validateDay(day)
                guard state.canonical, day == state.requestedDate, let fetched = value.fetchedAt, fetched == state.lastSuccess else { throw DatabaseError.invalidData }
                try timestamp(fetched)
            }
            if let updated = value.manualUpdatedAt { try timestamp(updated) }
        }
    }
}
