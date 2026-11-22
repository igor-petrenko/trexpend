import Foundation

nonisolated struct CurrencyRate: Equatable, Sendable {
    let currencyID: Int64
    let nbu: Decimal?
    let effectiveDate: String?
    let fetchedAt: String?
    let manual: Decimal?
    let manualUpdatedAt: String?
    var effective: Decimal? { manual ?? nbu }
}

nonisolated struct CurrencySync: Equatable, Sendable {
    let automatic: Bool
    let canonical: Bool
    let lastAttempt: String?
    let lastSuccess: String?
    let requestedDate: String?
}

nonisolated struct CurrencyCatalog: Sendable {
    let generation: UUID
    let currencies: [CurrencyInfo]
    let fiatIDs: Set<Int64>
    let usedIDs: Set<Int64>
    let displayID: Int64
    let rates: [Int64: CurrencyRate]
    let sync: CurrencySync
    let converter: CurrencyConverter
    var comparisonIDs: [Int64] = []

    func comparisons(excluding id: Int64) -> [CurrencyInfo] {
        let indexed = Dictionary(uniqueKeysWithValues: currencies.map { ($0.id, $0) })
        return comparisonIDs.filter { $0 != id }.compactMap { indexed[$0] }
    }

    var managedIDs: Set<Int64> { usedIDs.union(rates.keys) }
    func needsRate(_ id: Int64) -> Bool {
        guard let currency = currencies.first(where: { $0.id == id }), currency.code.uppercased() != "UAH",
              fiatIDs.contains(id), NBUClient.supportedCodes.contains(currency.code.uppercased()) else { return false }
        return rates[id]?.effective == nil
    }
}

nonisolated enum CurrencyRateError: Error, Equatable, LocalizedError {
    case response, unavailable, changed, cancelled
    var errorDescription: String? {
        switch self {
        case .response: "The NBU response could not be validated. Saved rates were kept."
        case .unavailable: "A usable NBU rate is unavailable. Refresh rates and try again."
        case .changed: "The rate changed while you were editing. Reopen it and try again."
        case .cancelled: "The rate request is no longer applicable."
        }
    }
}

nonisolated enum RateDates {
    static func day(_ date: Date, timeZone: TimeZone) -> String {
        let c = LocalDateTime.calendar(in: timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func kyivDay(_ date: Date) -> String { day(date, timeZone: TimeZone(identifier: "Europe/Kyiv")!) }
    static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    static func instant(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if value.contains(".") { formatter.formatOptions.insert(.withFractionalSeconds) }
        return formatter.date(from: value)
    }
    static func validateDay(_ day: String) throws {
        guard day.count == 10 else { throw CurrencyRateError.response }
        _ = try LocalDateTime(storage: day + "T00:00:00")
    }
    static func due(_ sync: CurrencySync, missing: Bool, now: Date, timeZone: TimeZone = .current) -> Bool {
        guard sync.automatic else { return false }
        let successDate = sync.lastSuccess.flatMap(instant)
        if let text = sync.lastAttempt, let attempt = instant(text), attempt <= now,
           (successDate == nil || attempt > successDate!), now.timeIntervalSince(attempt) < 300 { return false }
        guard let text = sync.lastSuccess, let success = instant(text), success <= now else { return true }
        return missing || day(success, timeZone: timeZone) != day(now, timeZone: timeZone) || sync.requestedDate != kyivDay(now)
    }
}

nonisolated struct CurrencyCommit: Sendable {
    let catalog: CurrencyCatalog
    let changed: Bool
}
