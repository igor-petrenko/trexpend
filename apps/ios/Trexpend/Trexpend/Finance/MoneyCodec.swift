import Foundation

nonisolated enum FinanceError: Error, Equatable, LocalizedError {
    case invalidAmount
    case invalidPrecision
    case negativeAmount
    case unsupportedNumber
    case arithmeticFailure
    case invalidDate
    case futureDate
    case invalidTransaction
    case missingAccount
    case invalidRate
    case missingRate

    var errorDescription: String? {
        switch self {
        case .invalidAmount: "Enter a valid decimal amount."
        case .invalidPrecision: "The currency precision is unsupported."
        case .negativeAmount: "The operation amount cannot be negative."
        case .unsupportedNumber: "The number cannot be represented exactly."
        case .arithmeticFailure: "The calculation exceeds supported decimal precision."
        case .invalidDate: "The date or local time is invalid."
        case .futureDate: "The transaction date cannot be in the future."
        case .invalidTransaction: "The transaction fields are inconsistent."
        case .missingAccount: "A referenced account is unavailable."
        case .invalidRate: "The exchange rate is invalid."
        case .missingRate: "An exchange rate is unavailable."
        }
    }
}

nonisolated enum MoneyCodec {
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func parseInput(_ text: String, places: Int, signed: Bool = false) throws -> Decimal {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let value = try exactDecimal(normalized)
        guard signed || value >= 0 else { throw FinanceError.negativeAmount }
        return try rounded(value, places: places)
    }

    static func decode(_ text: String, places: Int, signed: Bool = false) throws -> Decimal {
        let value = try exactDecimal(text)
        guard signed || value >= 0 else { throw FinanceError.negativeAmount }
        guard try encode(value, places: places) == text else { throw FinanceError.invalidAmount }
        return value
    }

    static func decodeRate(_ text: String) throws -> Decimal {
        let value = try exactDecimal(text)
        guard value > 0 else { throw FinanceError.invalidRate }
        return value
    }

    static func rounded(_ value: Decimal, places: Int) throws -> Decimal {
        guard (0...18).contains(places) else { throw FinanceError.invalidPrecision }
        guard !value.isNaN else { throw FinanceError.unsupportedNumber }
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, places, .plain)
        guard !result.isNaN else { throw FinanceError.unsupportedNumber }
        return result == 0 ? Decimal(0) : result
    }

    static func encode(_ value: Decimal, places: Int) throws -> String {
        let result = try rounded(value, places: places)
        var copy = result
        let text = NSDecimalString(&copy, locale)
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let integer = String(parts[0])
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= places else { throw FinanceError.unsupportedNumber }
        return places == 0 ? integer : integer + "." + fraction + String(repeating: "0", count: places - fraction.count)
    }

    static func validate(_ value: Decimal) throws {
        guard !value.isNaN else { throw FinanceError.unsupportedNumber }
        var copy = value
        _ = try representation(NSDecimalString(&copy, locale))
    }

    private static func exactDecimal(_ text: String) throws -> Decimal {
        let expected = try representation(text)
        guard let value = Decimal(string: text, locale: locale), !value.isNaN else {
            throw FinanceError.unsupportedNumber
        }
        var copy = value
        guard try representation(NSDecimalString(&copy, locale)) == expected else {
            throw FinanceError.unsupportedNumber
        }
        return value
    }

    // Compare normalized decimal digits, avoiding a floating-point round trip.
    private static func representation(_ text: String) throws -> String {
        guard text.count <= 512,
              text.range(of: #"^-?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else {
            throw FinanceError.invalidAmount
        }
        let negative = text.hasPrefix("-")
        let unsigned = negative ? String(text.dropFirst()) : text
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        var digits = Array(parts.joined())
        var exponent = parts.count == 2 ? -parts[1].count : 0
        while digits.first == "0" { digits.removeFirst() }
        guard !digits.isEmpty else { return "0" }
        while digits.last == "0" {
            digits.removeLast()
            exponent += 1
        }
        guard digits.count <= 38, (-128...127).contains(exponent) else {
            throw FinanceError.unsupportedNumber
        }
        return (negative ? "-" : "") + String(digits) + "e" + String(exponent)
    }
}

nonisolated enum DecimalArithmetic {
    static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        try calculate(lhs, rhs, NSDecimalAdd)
    }

    static func subtract(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        try calculate(lhs, rhs, NSDecimalSubtract)
    }

    static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        try calculate(lhs, rhs, NSDecimalMultiply)
    }

    static func divide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        // Recurring quotients use Foundation's available decimal precision. All
        // other arithmetic must succeed without implicit precision loss.
        try calculate(lhs, rhs, NSDecimalDivide, allowsDivisionRounding: true)
    }

    private static func calculate(
        _ lhs: Decimal, _ rhs: Decimal,
        _ operation: (UnsafeMutablePointer<Decimal>, UnsafePointer<Decimal>, UnsafePointer<Decimal>, Decimal.RoundingMode) -> Decimal.CalculationError,
        allowsDivisionRounding: Bool = false
    ) throws -> Decimal {
        try MoneyCodec.validate(lhs)
        try MoneyCodec.validate(rhs)
        var left = lhs
        var right = rhs
        var result = Decimal()
        let status = operation(&result, &left, &right, .plain)
        guard status == .noError || (allowsDivisionRounding && status == .lossOfPrecision) else {
            throw FinanceError.arithmeticFailure
        }
        try MoneyCodec.validate(result)
        return result
    }
}

// Valuation may contain recurring quotients. Keep Foundation's available decimal
// precision throughout the calculation and round to currency scale only at its end.
// Persisted money and native balance arithmetic retain the strict policy above.
nonisolated enum ValuationArithmetic {
    static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        try calculate(lhs, rhs, NSDecimalAdd)
    }
    static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        try calculate(lhs, rhs, NSDecimalMultiply)
    }
    static func divide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        try calculate(lhs, rhs, NSDecimalDivide)
    }
    private static func calculate(
        _ lhs: Decimal, _ rhs: Decimal,
        _ operation: (UnsafeMutablePointer<Decimal>, UnsafePointer<Decimal>, UnsafePointer<Decimal>, Decimal.RoundingMode) -> Decimal.CalculationError
    ) throws -> Decimal {
        guard !lhs.isNaN, !rhs.isNaN else { throw FinanceError.unsupportedNumber }
        var left = lhs
        var right = rhs
        var result = Decimal()
        let status = operation(&result, &left, &right, .plain)
        guard (status == .noError || status == .lossOfPrecision), !result.isNaN else {
            throw FinanceError.arithmeticFailure
        }
        return result
    }
}
