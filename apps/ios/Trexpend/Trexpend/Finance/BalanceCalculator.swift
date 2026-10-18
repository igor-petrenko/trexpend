import Foundation

nonisolated enum BalanceCalculator {
    static func balances(accounts: [LedgerAccount], transactions: [AccountingTransaction], through: LocalDateTime? = nil) throws -> [Int64: Decimal] {
        let indexed = try index(accounts)
        var result = indexed.mapValues(\.initialBalance)
        for account in accounts { try MoneyCodec.validate(account.initialBalance) }
        for transaction in transactions {
            try validate(transaction, accounts: indexed)
            if let through, transaction.date > through { continue }
            switch transaction.type {
            case .income:
                result[transaction.accountID] = try DecimalArithmetic.add(result[transaction.accountID]!, transaction.amount)
            case .expense:
                result[transaction.accountID] = try DecimalArithmetic.subtract(result[transaction.accountID]!, transaction.amount)
            case .transfer:
                guard let destination = transaction.toAccountID, let received = transaction.toAmount,
                      let feeAccount = transaction.feeAccountID else { throw FinanceError.invalidTransaction }
                result[transaction.accountID] = try DecimalArithmetic.subtract(result[transaction.accountID]!, transaction.amount)
                result[destination] = try DecimalArithmetic.add(result[destination]!, received)
                result[feeAccount] = try DecimalArithmetic.subtract(result[feeAccount]!, transaction.fee)
            }
        }
        return result
    }

    static func periodTotals(accounts: [LedgerAccount], transactions: [AccountingTransaction], month: CalendarMonth, accountID: Int64? = nil) throws -> [Int64: PeriodTotals] {
        let indexed = try index(accounts)
        if let accountID, indexed[accountID] == nil { throw FinanceError.missingAccount }
        var totals: [Int64: PeriodTotals] = [:]
        for transaction in transactions {
            try validate(transaction, accounts: indexed)
            guard month.contains(transaction.date) else { continue }
            let chargedID = transaction.type == .transfer ? transaction.feeAccountID! : transaction.accountID
            guard accountID == nil || accountID == chargedID else { continue }
            let currencyID = indexed[chargedID]!.currencyID
            var total = totals[currencyID, default: PeriodTotals()]
            if transaction.type == .income {
                total.income = try DecimalArithmetic.add(total.income, transaction.amount)
            } else {
                let expense = transaction.type == .transfer ? transaction.fee : transaction.amount
                total.expenses = try DecimalArithmetic.add(total.expenses, expense)
            }
            totals[currencyID] = total
        }
        return totals
    }

    static func homeBalance(accounts: [LedgerAccount], transactions: [AccountingTransaction], displayCurrency: LedgerCurrency, rates: CurrencyConverter) throws -> Decimal {
        let native = try balances(accounts: accounts, transactions: transactions)
        let values = accounts.filter { !$0.isClosed }.map {
            MonetaryAmount(value: native[$0.id]!, currencyID: $0.currencyID)
        }
        return try rates.total(values, to: displayCurrency)
    }

    private static func index(_ accounts: [LedgerAccount]) throws -> [Int64: LedgerAccount] {
        var result: [Int64: LedgerAccount] = [:]
        for account in accounts {
            guard account.id > 0, account.currencyID > 0, result[account.id] == nil else { throw FinanceError.invalidTransaction }
            result[account.id] = account
        }
        return result
    }

    private static func validate(_ transaction: AccountingTransaction, accounts: [Int64: LedgerAccount]) throws {
        guard accounts[transaction.accountID] != nil else { throw FinanceError.missingAccount }
        try MoneyCodec.validate(transaction.amount)
        try MoneyCodec.validate(transaction.fee)
        guard transaction.amount >= 0, transaction.fee >= 0 else { throw FinanceError.negativeAmount }
        if transaction.type == .transfer {
            guard let destination = transaction.toAccountID, destination != transaction.accountID,
                  let received = transaction.toAmount, let feeAccount = transaction.feeAccountID,
                  feeAccount == transaction.accountID || feeAccount == destination else { throw FinanceError.invalidTransaction }
            guard accounts[destination] != nil else { throw FinanceError.missingAccount }
            try MoneyCodec.validate(received)
            guard received >= 0 else { throw FinanceError.negativeAmount }
        } else {
            guard transaction.toAccountID == nil, transaction.toAmount == nil,
                  transaction.fee == 0, transaction.feeAccountID == nil else { throw FinanceError.invalidTransaction }
        }
    }
}
