import Foundation

// All reads run on DatabaseStore's worker inside coherent SQLite transactions.
nonisolated enum HistoryRead {
    private struct Account {
        let name: String
        let bank: String?
        let favorite: Bool
        let type: HomeAccountType
        let currency: CurrencyInfo
        let ledger: LedgerAccount
    }
    private static func accounts(_ db: SQLiteConnection, currencies: [Int64: CurrencyInfo]) throws -> [Int64: Account] {
        var result: [Int64: Account] = [:]
        for row in try db.rows("SELECT a.*,s.code AS status_code FROM accounts a JOIN account_statuses s ON s.id=a.status") {
            let id = try row.integer("id")
            guard let currency = currencies[try row.integer("currency_id")],
                  let type = try HomeAccountType(rawValue: Int(row.integer("account_type"))) else { throw DatabaseError.invalidData }
            result[id] = try Account(name: row.text("name"), bank: row.optionalText("bank"), favorite: row.integer("favorite") == 1, type: type, currency: currency,
                ledger: LedgerAccount(id: id, currencyID: currency.id, initialBalance: MoneyCodec.decode(row.text("initial_balance"), places: currency.decimalPlaces, signed: true), isClosed: row.text("status_code") == "closed"))
        }
        return result
    }
    private static func transaction(_ row: SQLRow, accounts: [Int64: Account]) throws -> AccountingTransaction {
        guard let source = accounts[try row.integer("account_id")],
              let type = try LedgerTransactionType(rawValue: Int(row.integer("transaction_type"))) else { throw DatabaseError.invalidData }
        let destinationID = try row.optionalInteger("to_account_id")
        var received: Decimal?
        if let destinationID {
            guard let destination = accounts[destinationID] else { throw DatabaseError.invalidData }
            received = try MoneyCodec.decode(row.text("to_amount"), places: destination.currency.decimalPlaces)
        }
        let feeID = try row.optionalInteger("fee_account_id")
        let feePlaces = feeID.flatMap { accounts[$0]?.currency.decimalPlaces } ?? source.currency.decimalPlaces
        return try AccountingTransaction(type: type, accountID: source.ledger.id, amount: MoneyCodec.decode(row.text("amount"), places: source.currency.decimalPlaces), date: LocalDateTime(storage: row.text("date")), toAccountID: destinationID, toAmount: received, fee: MoneyCodec.decode(row.text("fee"), places: feePlaces), feeAccountID: feeID)
    }

    static func snapshot(_ db: SQLiteConnection, accountID: Int64, generation: UUID, month: CalendarMonth) throws -> AccountHistorySnapshot {
        let currencies = Dictionary(uniqueKeysWithValues: try HomeRead.currencies(db).map { ($0.id, $0) })
        let indexed = try accounts(db, currencies: currencies)
        guard let account = indexed[accountID], let setting = try db.rows("SELECT display_currency_id FROM app_settings WHERE id=1").first,
              let display = currencies[try setting.integer("display_currency_id")] else { throw DatabaseError.invalidData }
        var transactions: [AccountingTransaction] = []
        try db.forEach("SELECT transaction_type,account_id,amount,date,to_account_id,to_amount,fee,fee_account_id FROM transactions WHERE account_id=? OR to_account_id=?", parameters: [.integer(accountID),.integer(accountID)]) { row in
            transactions.append(try transaction(row, accounts: indexed))
        }
        let ledger = indexed.values.map(\.ledger)
        guard let balance = try BalanceCalculator.balances(accounts: ledger, transactions: transactions)[accountID] else { throw DatabaseError.invalidData }
        let totals = try BalanceCalculator.periodTotals(accounts: ledger, transactions: transactions, month: month, accountID: accountID)[account.currency.id, default: PeriodTotals()]
        let rates = try db.rows("SELECT from_currency_id,to_currency_id,rate FROM exchange_rates ORDER BY id").map {
            try ExchangeRate(fromCurrencyID: $0.integer("from_currency_id"), toCurrencyID: $0.integer("to_currency_id"), value: MoneyCodec.decodeRate($0.text("rate")))
        }
        var converted: Decimal?
        if display.id != account.currency.id {
            do {
                converted = balance == 0 ? 0 : try CurrencyConverter(rates: rates).total([MonetaryAmount(value: balance, currencyID: account.currency.id)], to: display.ledger)
            } catch FinanceError.missingRate { converted = nil }
        }
        let summary = HomeAccountRow(id: accountID, name: account.name, bank: account.bank, type: account.type, favorite: account.favorite, currency: account.currency, balance: balance, income: totals.income, expenses: totals.expenses, hasActivity: transactions.contains { month.contains($0.date) })
        return try AccountHistorySnapshot(generation: generation, account: summary, month: month, displayCurrency: display, convertedBalance: converted, difference: DecimalArithmetic.subtract(totals.income, totals.expenses), page: page(db, accountID: accountID, generation: generation, cursor: nil, indexed: indexed))
    }

    // The first and subsequent pages use the same bounded projection and cursor.
    static func page(_ db: SQLiteConnection, accountID: Int64, generation: UUID, cursor: HistoryCursor?) throws -> HistoryPage {
        let currencies = Dictionary(uniqueKeysWithValues: try HomeRead.currencies(db).map { ($0.id, $0) })
        return try page(db, accountID: accountID, generation: generation, cursor: cursor, indexed: accounts(db, currencies: currencies))
    }

    static func pageQuery(cursor: Bool) -> String {
        let boundary = cursor ? " AND (date,id) < (?,?)" : ""
        return """
        SELECT t.*,c.name AS category_name,i.system_name AS icon_symbol FROM (
          SELECT * FROM transactions WHERE account_id=?\(boundary)
          UNION ALL
          SELECT * FROM transactions WHERE to_account_id=?\(boundary)
          ORDER BY date DESC,id DESC LIMIT 51
        ) t JOIN categories c ON c.id=t.category_id
        LEFT JOIN category_icons i ON i.id=c.icon_id
        ORDER BY t.date DESC,t.id DESC
        """
    }

    private static func page(_ db: SQLiteConnection, accountID: Int64, generation: UUID, cursor: HistoryCursor?, indexed: [Int64: Account]) throws -> HistoryPage {
        if let cursor {
            guard cursor.generation == generation, cursor.accountID == accountID else { throw DatabaseError.staleDataset }
            _ = try LocalDateTime(storage: cursor.date)
        }
        guard let account = indexed[accountID] else { throw DatabaseError.invalidData }
        var parameters: [SQLValue] = []
        for _ in 0..<2 {
            parameters.append(.integer(accountID))
            if let cursor { parameters += [.text(cursor.date), .integer(cursor.id)] }
        }
        let stored = try db.rows(pageQuery(cursor: cursor != nil), parameters: parameters)
        let rows = try stored.prefix(50).map { row -> HistoryRow in
            let transaction = try transaction(row, accounts: indexed)
            let incoming = transaction.type == .income || (transaction.type == .transfer && transaction.toAccountID == accountID)
            let otherID = transaction.type == .transfer ? (incoming ? transaction.accountID : transaction.toAccountID) : nil
            let other = otherID.flatMap { indexed[$0] }
            let charged = transaction.feeAccountID.flatMap { indexed[$0] }
            return try HistoryRow(id: row.integer("id"), type: transaction.type, date: transaction.date, category: row.text("category_name"), symbol: row.optionalText("icon_symbol"), notes: row.optionalText("notes"), incoming: incoming,
                amount: incoming && transaction.type == .transfer ? transaction.toAmount! : transaction.amount, currency: account.currency, counterparty: other?.name,
                counterpartAmount: transaction.type == .transfer ? (incoming ? transaction.amount : transaction.toAmount) : nil,
                counterpartCurrency: other?.currency, fee: transaction.fee, feeCurrency: charged?.currency, feeAccountName: charged?.name)
        }
        let next = stored.count > 50 ? rows.last.map { HistoryCursor(generation: generation, accountID: accountID, date: $0.date.storage, id: $0.id) } : nil
        return HistoryPage(rows: rows, next: next)
    }
}
