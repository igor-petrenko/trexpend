import Foundation
import Testing
@testable import Trexpend

private func decimal(_ text: String) -> Decimal {
    Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
}

@Suite("Money codec")
struct MoneyCodecTests {
    @Test(arguments: ["12.35", "12,35", " 12.35 \n"])
    func separators(_ input: String) throws {
        #expect(try MoneyCodec.parseInput(input, places: 2) == decimal("12.35"))
    }

    @Test(arguments: ["", " ", "1 234.56", "1,234.56", "1.234,56", "1..2", "1e2", "NaN", "inf", "+1", ".5", "1.", "12x", "1\n2"])
    func invalidInput(_ input: String) {
        #expect(throws: (any Error).self) { try MoneyCodec.parseInput(input, places: 2) }
    }

    @Test
    func signedAndZeroAmounts() throws {
        #expect(try MoneyCodec.parseInput("-12.345", places: 2, signed: true) == decimal("-12.35"))
        #expect(throws: FinanceError.negativeAmount) { try MoneyCodec.parseInput("-1", places: 2) }
        #expect(try MoneyCodec.encode(MoneyCodec.parseInput("0.004", places: 2), places: 2) == "0.00")
        #expect(try MoneyCodec.encode(MoneyCodec.parseInput("-0.004", places: 2, signed: true), places: 2) == "0.00")
    }

    @Test
    func roundingAndCurrencyScales() throws {
        #expect(try MoneyCodec.encode(decimal("12.345"), places: 2) == "12.35")
        #expect(try MoneyCodec.encode(decimal("12.344"), places: 2) == "12.34")
        #expect(try MoneyCodec.encode(decimal("-12.345"), places: 2) == "-12.35")
        #expect(try MoneyCodec.encode(decimal("12.5"), places: 0) == "13")
        #expect(try MoneyCodec.encode(decimal("0.000000015"), places: 8) == "0.00000002")
        #expect(try MoneyCodec.encode(decimal("0.000000000000000001"), places: 18) == "0.000000000000000001")
        #expect(try MoneyCodec.encode(decimal("1"), places: 4) == "1.0000")
        #expect(throws: FinanceError.invalidPrecision) { try MoneyCodec.encode(1, places: 19) }
    }

    @Test(arguments: ["0.00", "12.35", "999999999999999999999999999999999999.99"])
    func storedRoundTrip(_ text: String) throws {
        #expect(try MoneyCodec.encode(MoneyCodec.decode(text, places: 2), places: 2) == text)
    }

    @Test(arguments: ["12.345", "12.3", "012.30", "12,30", " 12.30", "-0.00"])
    func noncanonicalStorage(_ text: String) {
        #expect(throws: (any Error).self) { try MoneyCodec.decode(text, places: 2, signed: true) }
    }

    @Test
    func exactArithmeticAndFailures() throws {
        #expect(try DecimalArithmetic.add(decimal("0.1"), decimal("0.2")) == decimal("0.3"))
        #expect(throws: FinanceError.arithmeticFailure) { try DecimalArithmetic.divide(1, 0) }
        #expect(throws: (any Error).self) { try DecimalArithmetic.multiply(decimal("1e127"), 100) }
        #expect(throws: (any Error).self) { try DecimalArithmetic.divide(decimal("1e-128"), 10) }
        #expect(throws: (any Error).self) { try MoneyCodec.parseInput(String(repeating: "9", count: 39), places: 2) }
        #expect(throws: (any Error).self) { try MoneyCodec.decodeRate("0." + String(repeating: "0", count: 128) + "1") }
        #expect(throws: (any Error).self) { try MoneyCodec.encode(.nan, places: 2) }
        #expect(try MoneyCodec.decodeRate("0.03263563841720928") == decimal("0.03263563841720928"))
    }
}

@Suite("Local dates")
struct TransactionDateTests {
    private let toronto = TimeZone(identifier: "America/Toronto")!

    private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    @Test
    func calendarValidation() throws {
        #expect(try LocalDateTime(storage: "2024-02-29T23:59:59").storage == "2024-02-29T23:59:59")
        for invalid in ["2025-02-29T00:00:00", "2026-04-31T00:00:00", "2026-01-01T24:00:00", "2026-01-01", "0000-01-01T00:00:00"] {
            #expect(throws: FinanceError.invalidDate) { try LocalDateTime(storage: invalid) }
        }
        #expect(try LocalDateTime(storage: "2026-01-01T18:00:00") > LocalDateTime(storage: "2026-01-01T00:00:00"))
    }

    @Test
    func monthBoundaries() throws {
        let month = try CalendarMonth(year: 2025, month: 12)
        #expect(month.start.storage == "2025-12-01T00:00:00")
        #expect(month.end.storage == "2026-01-01T00:00:00")
        #expect(month.contains(try LocalDateTime(storage: "2025-12-01T00:00:00")))
        #expect(month.contains(try LocalDateTime(storage: "2025-12-31T23:59:59")))
        #expect(!month.contains(try LocalDateTime(storage: "2026-01-01T00:00:00")))
    }

    @Test
    func localAndOffsetHaveSeparateRoles() throws {
        let local = try LocalDateTime(storage: "2026-07-01T18:00:00")
        #expect(try TransactionDateRules.occurrence(local, timeZone: toronto).withOffset == "2026-07-01T18:00:00-04:00")
        #expect(try TransactionDateRules.occurrence(local, timeZone: .gmt).local == local)
        let winter = try LocalDateTime(storage: "2026-01-01T18:00:00")
        #expect(try TransactionDateRules.occurrence(winter, timeZone: toronto).withOffset == "2026-01-01T18:00:00-05:00")
    }

    @Test
    func dateDefaultsAndPreservation() throws {
        let now = instant("2026-07-01T22:00:00Z")
        let created = try TransactionDateRules.newOccurrence(now: now, timeZone: toronto)
        #expect(created.local.storage == "2026-07-01T18:00:00")
        let day = try LocalDateTime(storage: "2026-06-30T12:00:00")
        let backdated = try TransactionDateRules.changingDay(of: created.local, to: day)
        #expect(backdated.storage == "2026-06-30T00:00:00")
        #expect(try TransactionDateRules.changingDay(of: created.local, to: created.local) == created.local)
        #expect(try TransactionDateRules.forSave(original: created, editedLocal: nil, now: now, timeZone: .gmt) == created)
        let legacy = OccurrenceDate(local: day, withOffset: nil)
        #expect(try TransactionDateRules.forSave(original: legacy, editedLocal: nil, now: now, timeZone: toronto) == legacy)
        #expect(try TransactionDateRules.forSave(original: created, editedLocal: backdated, now: now, timeZone: toronto).withOffset == "2026-06-30T00:00:00-04:00")
        #expect(throws: FinanceError.futureDate) {
            try TransactionDateRules.validateNotFuture(LocalDateTime(storage: "2026-07-02T00:00:00"), now: now, timeZone: toronto)
        }
        #expect(TransactionDateRules.technicalTimestamp(now) == "2026-07-01T22:00:00.000Z")
    }

    @Test
    func daylightSavingAmbiguity() throws {
        let repeated = try LocalDateTime(storage: "2026-11-01T01:30:00")
        #expect(try TransactionDateRules.occurrence(repeated, timeZone: toronto).withOffset == "2026-11-01T01:30:00-04:00")
        #expect(try TransactionDateRules.newOccurrence(now: instant("2026-11-01T06:30:00Z"), timeZone: toronto).withOffset == "2026-11-01T01:30:00-05:00")
        #expect(throws: FinanceError.invalidDate) {
            try TransactionDateRules.occurrence(LocalDateTime(storage: "2026-03-08T02:30:00"), timeZone: toronto)
        }
    }
}

@Suite("Balances and periods")
struct BalanceCalculatorTests {
    private var accounts: [LedgerAccount] {
        [LedgerAccount(id: 1, currencyID: 1, initialBalance: 100),
         LedgerAccount(id: 2, currencyID: 2, initialBalance: -20, isClosed: true)]
    }
    private var date: LocalDateTime { try! LocalDateTime(storage: "2026-07-01T12:00:00") }

    private func transfer(feeAccount: Int64, fee: Decimal = 2) -> AccountingTransaction {
        AccountingTransaction(type: .transfer, accountID: 1, amount: 30, date: date,
                              toAccountID: 2, toAmount: 40, fee: fee, feeAccountID: feeAccount)
    }

    @Test
    func transferAndFeeOnEitherSide() throws {
        let sourceFee = try BalanceCalculator.balances(accounts: accounts, transactions: [transfer(feeAccount: 1)])
        #expect(sourceFee == [1: 68, 2: 20])
        let receiverFee = try BalanceCalculator.balances(accounts: accounts, transactions: [transfer(feeAccount: 2)])
        #expect(receiverFee == [1: 70, 2: 18])
    }

    @Test
    func ordinaryOperationsAndZero() throws {
        let transactions = [AccountingTransaction(type: .income, accountID: 1, amount: 25, date: date),
                            AccountingTransaction(type: .expense, accountID: 1, amount: 10, date: date),
                            AccountingTransaction(type: .expense, accountID: 2, amount: 0, date: date)]
        #expect(try BalanceCalculator.balances(accounts: accounts, transactions: transactions) == [1: 115, 2: -20])
        #expect(try BalanceCalculator.balances(accounts: accounts, transactions: transactions, through: LocalDateTime(storage: "2026-06-30T23:59:59")) == [1: 100, 2: -20])
    }

    @Test
    func periodsIncludeClosedAccountsAndOnlyTransferFees() throws {
        let transactions = [AccountingTransaction(type: .income, accountID: 2, amount: 100, date: date),
                            AccountingTransaction(type: .expense, accountID: 2, amount: 7, date: date),
                            transfer(feeAccount: 2),
                            AccountingTransaction(type: .income, accountID: 1, amount: 999, date: try LocalDateTime(storage: "2026-08-01T00:00:00"))]
        let month = try CalendarMonth(year: 2026, month: 7)
        let totals = try BalanceCalculator.periodTotals(accounts: accounts, transactions: transactions, month: month)
        #expect(totals[2] == PeriodTotals(income: 100, expenses: 9))
        #expect(totals[1] == nil)
        let sourceOnly = try BalanceCalculator.periodTotals(accounts: accounts, transactions: transactions, month: month, accountID: 1)
        #expect(sourceOnly.isEmpty)
    }

    @Test
    func unequalSameCurrencyTransfer() throws {
        let sameCurrency = [accounts[0], LedgerAccount(id: 2, currencyID: 1, initialBalance: 0)]
        #expect(try BalanceCalculator.balances(accounts: sameCurrency, transactions: [transfer(feeAccount: 1, fee: 0)]) == [1: 70, 2: 40])
    }

    @Test
    func invalidReferencesAndFields() throws {
        #expect(throws: FinanceError.invalidTransaction) { try BalanceCalculator.balances(accounts: accounts + [accounts[0]], transactions: []) }
        var invalid = transfer(feeAccount: 3)
        #expect(throws: FinanceError.invalidTransaction) { try BalanceCalculator.balances(accounts: accounts, transactions: [invalid]) }
        invalid = transfer(feeAccount: 1)
        invalid.toAccountID = 9
        #expect(throws: FinanceError.missingAccount) { try BalanceCalculator.balances(accounts: accounts, transactions: [invalid]) }
        invalid.toAccountID = 1
        #expect(throws: FinanceError.invalidTransaction) { try BalanceCalculator.balances(accounts: accounts, transactions: [invalid]) }
        let negative = AccountingTransaction(type: .expense, accountID: 1, amount: -1, date: date)
        #expect(throws: FinanceError.negativeAmount) { try BalanceCalculator.balances(accounts: accounts, transactions: [negative]) }
    }

    @Test
    func homeExcludesClosedBalance() throws {
        let converter = try CurrencyConverter(rates: [])
        let target = try LedgerCurrency(id: 1, decimalPlaces: 2)
        #expect(try BalanceCalculator.homeBalance(accounts: accounts, transactions: [transfer(feeAccount: 1)], displayCurrency: target, rates: converter) == 68)
    }
}

@Suite("Currency conversion")
struct CurrencyConverterTests {
    @Test
    func directInverseCrossAndIdentity() throws {
        let rates = try CurrencyConverter(rates: [ExchangeRate(fromCurrencyID: 2, toCurrencyID: 1, value: decimal("1.25")),
                                                 ExchangeRate(fromCurrencyID: 3, toCurrencyID: 1, value: decimal("0.05"))])
        #expect(try rates.convert(MonetaryAmount(value: 10, currencyID: 2), to: 1) == decimal("12.5"))
        #expect(try rates.convert(MonetaryAmount(value: 10, currencyID: 1), to: 2) == 8)
        #expect(try rates.convert(MonetaryAmount(value: 1000, currencyID: 3), to: 2) == 40)
        #expect(try rates.convert(MonetaryAmount(value: 10, currencyID: 99), to: 99) == 10)
        #expect(throws: FinanceError.missingRate) { try rates.convert(MonetaryAmount(value: 10, currencyID: 99), to: 1) }
    }

    @Test
    func aggregateRoundsOnlyAtEnd() throws {
        let rates = try CurrencyConverter(rates: [ExchangeRate(fromCurrencyID: 2, toCurrencyID: 1, value: decimal("0.005"))])
        let target = try LedgerCurrency(id: 1, decimalPlaces: 2)
        let item = MonetaryAmount(value: 1, currencyID: 2)
        #expect(try rates.suggestedAmount(item, to: target) == decimal("0.01"))
        #expect(try rates.total([item, item], to: target) == decimal("0.01"))
        #expect(try rates.total([], to: target) == 0)
    }

    @Test
    func invalidAndDuplicateRates() {
        for value in [Decimal(0), Decimal(-1), Decimal.nan] {
            #expect(throws: (any Error).self) { try CurrencyConverter(rates: [ExchangeRate(fromCurrencyID: 1, toCurrencyID: 2, value: value)]) }
        }
        let rate = ExchangeRate(fromCurrencyID: 1, toCurrencyID: 2, value: 1)
        #expect(throws: FinanceError.invalidRate) { try CurrencyConverter(rates: [rate, rate]) }
    }

    @Test
    func repeatingDivisionUsesDecimalPrecision() throws {
        let rates = try CurrencyConverter(rates: [ExchangeRate(fromCurrencyID: 1, toCurrencyID: 2, value: 3)])
        #expect(try rates.suggestedAmount(MonetaryAmount(value: 1, currencyID: 2), to: LedgerCurrency(id: 1, decimalPlaces: 2)) == decimal("0.33"))
    }
}

@Suite("Valuation regression cases")
struct ValuationRegressionTests {
    @Test
    func smallConvertedAmountPlusNativeAmount() throws {
        let rates = try CurrencyConverter(rates: [ExchangeRate(fromCurrencyID: 2, toCurrencyID: 1, value: decimal("1.37"))])
        let target = try LedgerCurrency(id: 2, decimalPlaces: 2)
        for native in ["1", "10", "1000"] {
            let total = try rates.total([MonetaryAmount(value: decimal("0.01"), currencyID: 1), MonetaryAmount(value: decimal(native), currencyID: 2)], to: target)
            #expect(total == decimal(native) + decimal("0.01"))
        }
    }

    @Test
    func recurringCrossConversionAndAggregate() throws {
        let rates = try CurrencyConverter(rates: [ExchangeRate(fromCurrencyID: 1, toCurrencyID: 2, value: 3), ExchangeRate(fromCurrencyID: 2, toCurrencyID: 3, value: decimal("1.37"))])
        let target = try LedgerCurrency(id: 3, decimalPlaces: 2)
        let item = MonetaryAmount(value: 1, currencyID: 2)
        #expect(try rates.total([item, MonetaryAmount(value: 1, currencyID: 3)], to: target) == decimal("2.37"))
        #expect(try rates.total([MonetaryAmount(value: 1, currencyID: 3), MonetaryAmount(value: 1, currencyID: 1)], to: LedgerCurrency(id: 1, decimalPlaces: 2)) == decimal("1.24"))
        let inverse = try CurrencyConverter(rates: [ExchangeRate(fromCurrencyID: 3, toCurrencyID: 1, value: decimal("0.03263563841720928"))])
        #expect(try inverse.total([MonetaryAmount(value: 100, currencyID: 1), MonetaryAmount(value: 1, currencyID: 3)], to: target) == decimal("3065.13"))
        #expect(throws: FinanceError.arithmeticFailure) { try ValuationArithmetic.divide(1, 0) }
        #expect(throws: FinanceError.arithmeticFailure) { try ValuationArithmetic.multiply(decimal("1e127"), 100) }
    }
}
