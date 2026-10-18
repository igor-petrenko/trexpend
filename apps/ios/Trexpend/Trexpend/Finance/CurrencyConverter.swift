import Foundation

nonisolated struct CurrencyConverter: Sendable {
    private struct Pair: Hashable, Sendable {
        let from: Int64
        let to: Int64
    }

    private let rates: [Pair: Decimal]
    private let currencyIDs: [Int64]

    init(rates: [ExchangeRate]) throws {
        var indexed: [Pair: Decimal] = [:]
        var identifiers: Set<Int64> = []
        for rate in rates {
            try MoneyCodec.validate(rate.value)
            let key = Pair(from: rate.fromCurrencyID, to: rate.toCurrencyID)
            guard rate.fromCurrencyID > 0, rate.toCurrencyID > 0,
                  rate.fromCurrencyID != rate.toCurrencyID, rate.value > 0, indexed[key] == nil else {
                throw FinanceError.invalidRate
            }
            indexed[key] = rate.value
            identifiers.formUnion([rate.fromCurrencyID, rate.toCurrencyID])
        }
        self.rates = indexed
        currencyIDs = identifiers.sorted()
    }

    func convert(_ amount: MonetaryAmount, to currencyID: Int64) throws -> Decimal {
        try MoneyCodec.validate(amount.value)
        guard amount.currencyID > 0, currencyID > 0 else { throw FinanceError.invalidRate }
        if amount.currencyID == currencyID { return amount.value }
        if let result = try directOrInverse(amount.value, from: amount.currencyID, to: currencyID) { return result }
        // V1 rates form a common-base graph. A cross conversion needs two edges.
        for base in currencyIDs where base != amount.currencyID && base != currencyID {
            guard hasRate(from: amount.currencyID, to: base), hasRate(from: base, to: currencyID) else { continue }
            let intermediate = try directOrInverse(amount.value, from: amount.currencyID, to: base)!
            return try directOrInverse(intermediate, from: base, to: currencyID)!
        }
        throw FinanceError.missingRate
    }

    func suggestedAmount(_ amount: MonetaryAmount, to currency: LedgerCurrency) throws -> Decimal {
        try MoneyCodec.rounded(convert(amount, to: currency.id), places: currency.decimalPlaces)
    }

    func total(_ amounts: [MonetaryAmount], to currency: LedgerCurrency) throws -> Decimal {
        var result: Decimal = 0
        for amount in amounts {
            result = try ValuationArithmetic.add(result, convert(amount, to: currency.id))
        }
        return try MoneyCodec.rounded(result, places: currency.decimalPlaces)
    }

    private func hasRate(from: Int64, to: Int64) -> Bool {
        rates[Pair(from: from, to: to)] != nil || rates[Pair(from: to, to: from)] != nil
    }

    private func directOrInverse(_ value: Decimal, from: Int64, to: Int64) throws -> Decimal? {
        if let rate = rates[Pair(from: from, to: to)] { return try ValuationArithmetic.multiply(value, rate) }
        if let inverse = rates[Pair(from: to, to: from)] { return try ValuationArithmetic.divide(value, inverse) }
        return nil
    }
}
