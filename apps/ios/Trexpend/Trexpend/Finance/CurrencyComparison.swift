import Foundation

nonisolated enum CurrencyComparisonValue: Equatable, Sendable {
    case value(Decimal), unavailable, invalid
}

nonisolated enum CurrencyComparison {
    static func value(amount: Decimal, from: Int64, to: Int64, converter: CurrencyConverter) -> CurrencyComparisonValue {
        do {
            guard amount >= 0 else { return .invalid }
            return .value(try converter.convert(MonetaryAmount(value: amount, currencyID: from), to: to))
        } catch FinanceError.missingRate { return .unavailable }
        catch { return .invalid }
    }
}
