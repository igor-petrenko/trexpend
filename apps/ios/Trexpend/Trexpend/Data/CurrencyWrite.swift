import Foundation

nonisolated enum CurrencyWrite {
    static func manual(_ db: SQLiteConnection, id: Int64, value: String?, original: CurrencyRate?, now: Date) throws {
        guard let currency = try db.rows("SELECT code,currency_type FROM currencies WHERE id=?", parameters: [.integer(id)]).first,
              try currency.text("code").uppercased() != "UAH", try currency.text("currency_type") == "fiat" else { throw FinanceError.invalidRate }
        let current = try CurrencyRead.rates(db)[id]
        guard current?.manual == original?.manual, current?.manualUpdatedAt == original?.manualUpdatedAt else { throw CurrencyRateError.changed }
        if let value {
            let decimal = try MoneyCodec.decodeRate(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
            try db.run("INSERT INTO currency_rates(currency_id,manual_rate,manual_updated_at) VALUES(?,?,?) ON CONFLICT(currency_id) DO UPDATE SET manual_rate=excluded.manual_rate,manual_updated_at=excluded.manual_updated_at",
                       parameters: [.integer(id), .text(CurrencyConverter.text(decimal)), .text(RateDates.timestamp(now))])
        } else {
            guard current?.nbu != nil else { throw CurrencyRateError.unavailable }
            try db.run("UPDATE currency_rates SET manual_rate=NULL,manual_updated_at=NULL WHERE currency_id=?", parameters: [.integer(id)])
        }
    }

    static func batch(_ db: SQLiteConnection, batch: NBUBatch, extraIDs: Set<Int64>, generation: UUID, now: Date) throws {
        guard batch.day == RateDates.kyivDay(now) else { throw CurrencyRateError.cancelled }
        try RateDates.validateDay(batch.day)
        let catalog = try CurrencyRead.catalog(db, generation: generation)
        let managed = catalog.managedIDs.union(extraIDs)
        for currency in catalog.currencies where managed.contains(currency.id) && catalog.fiatIDs.contains(currency.id) && currency.code.uppercased() != "UAH" {
            let code = currency.code.uppercased()
            if NBUClient.supportedCodes.contains(code) || catalog.rates[currency.id]?.nbu != nil {
                guard batch.rates[code] != nil else { throw CurrencyRateError.response }
            }
        }
        // Drop only the inactive provider layer. Manual values remain untouched.
        try db.run("DELETE FROM currency_rates WHERE manual_rate IS NULL")
        try db.run("UPDATE currency_rates SET nbu_rate=NULL,nbu_effective_date=NULL,nbu_fetched_at=NULL")
        let timestamp = RateDates.timestamp(now)
        for currency in catalog.currencies where catalog.fiatIDs.contains(currency.id) && currency.code.uppercased() != "UAH" {
            guard let rate = batch.rates[currency.code.uppercased()] else { continue }
            _ = try MoneyCodec.decodeRate(CurrencyConverter.text(rate))
            try db.run("INSERT INTO currency_rates(currency_id,nbu_rate,nbu_effective_date,nbu_fetched_at) VALUES(?,?,?,?) ON CONFLICT(currency_id) DO UPDATE SET nbu_rate=excluded.nbu_rate,nbu_effective_date=excluded.nbu_effective_date,nbu_fetched_at=excluded.nbu_fetched_at",
                       parameters: [.integer(currency.id), .text(CurrencyConverter.text(rate)), .text(batch.day), .text(timestamp)])
        }
        try db.run("UPDATE currency_sync_state SET valuation_mode='uah',last_success_at=?,last_success_requested_date=? WHERE id=1", parameters: [.text(timestamp), .text(batch.day)])
        try CurrencyRead.validate(db)
    }
}
