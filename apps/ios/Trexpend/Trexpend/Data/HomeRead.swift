import Foundation

// Called only inside DatabaseLifecycle's coherent read transaction on its worker.
nonisolated enum HomeRead {
    static func currencies(_ db: SQLiteConnection) throws -> [CurrencyInfo] {
        try db.rows("SELECT id,code,name,decimal_places FROM currencies ORDER BY code COLLATE NOCASE,id").map { row in
            let info = try CurrencyInfo(id: row.integer("id"), code: row.text("code"), name: row.text("name"), decimalPlaces: Int(row.integer("decimal_places")))
            _ = try info.ledger
            return info
        }
    }

    static func snapshot(_ db: SQLiteConnection, generation: UUID, month: CalendarMonth) throws -> HomeSnapshot {
        let catalog = try currencies(db)
        let indexedCurrencies = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        guard let setting = try db.rows("SELECT display_currency_id FROM app_settings WHERE id=1").first,
              let display = indexedCurrencies[try setting.integer("display_currency_id")] else { throw DatabaseError.invalidData }
        let accountRows = try db.rows("SELECT a.id,a.name,a.bank,a.currency_id,a.initial_balance,a.favorite,a.account_type,s.code AS status_code FROM accounts a JOIN account_statuses s ON s.id=a.status ORDER BY a.id")
        var accounts: [LedgerAccount] = []
        for row in accountRows {
            let id = try row.integer("id")
            guard let currency = indexedCurrencies[try row.integer("currency_id")] else { throw DatabaseError.invalidData }
            accounts.append(try LedgerAccount(id: id, currencyID: currency.id, initialBalance: MoneyCodec.decode(row.text("initial_balance"), places: currency.decimalPlaces, signed: true), isClosed: row.text("status_code") == "closed"))
        }
        let indexedAccounts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var transactions: [AccountingTransaction] = []
        var periodByAccount: [Int64: PeriodTotals] = [:]
        var periodByCurrency: [Int64: PeriodTotals] = [:]
        var activeAccounts: Set<Int64> = []
        try db.forEach("SELECT transaction_type,account_id,amount,date,to_account_id,to_amount,fee,fee_account_id FROM transactions ORDER BY id") { row in
            guard let type = try LedgerTransactionType(rawValue: Int(row.integer("transaction_type"))),
                  let account = indexedAccounts[try row.integer("account_id")],
                  let currency = indexedCurrencies[account.currencyID] else { throw DatabaseError.invalidData }
            let destinationID = try row.optionalInteger("to_account_id")
            var received: Decimal?
            if let destinationID {
                guard let destination = indexedAccounts[destinationID], let target = indexedCurrencies[destination.currencyID] else { throw DatabaseError.invalidData }
                received = try MoneyCodec.decode(row.text("to_amount"), places: target.decimalPlaces)
            }
            let feeID = try row.optionalInteger("fee_account_id")
            guard let feeCurrency = feeID.flatMap({ indexedAccounts[$0]?.currencyID }).flatMap({ indexedCurrencies[$0] }) ?? indexedCurrencies[account.currencyID] else { throw DatabaseError.invalidData }
            let transaction = try AccountingTransaction(type: type, accountID: account.id, amount: MoneyCodec.decode(row.text("amount"), places: currency.decimalPlaces), date: LocalDateTime(storage: row.text("date")), toAccountID: destinationID, toAmount: received, fee: MoneyCodec.decode(row.text("fee"), places: feeCurrency.decimalPlaces), feeAccountID: feeID)
            transactions.append(transaction)
            if month.contains(transaction.date) {
                activeAccounts.insert(account.id)
                if let destinationID { activeAccounts.insert(destinationID) }
                let chargedID = type == .transfer ? feeID : account.id
                guard let chargedID, let charged = indexedAccounts[chargedID] else { throw FinanceError.invalidTransaction }
                let income = type == .income ? transaction.amount : Decimal(0)
                let expense = type == .transfer ? transaction.fee : (type == .expense ? transaction.amount : Decimal(0))
                let accountTotal = periodByAccount[chargedID, default: PeriodTotals()]
                periodByAccount[chargedID] = try PeriodTotals(income: DecimalArithmetic.add(accountTotal.income, income), expenses: DecimalArithmetic.add(accountTotal.expenses, expense))
                let currencyTotal = periodByCurrency[charged.currencyID, default: PeriodTotals()]
                periodByCurrency[charged.currencyID] = try PeriodTotals(income: DecimalArithmetic.add(currencyTotal.income, income), expenses: DecimalArithmetic.add(currencyTotal.expenses, expense))
            }
        }
        let balances = try BalanceCalculator.balances(accounts: accounts, transactions: transactions)
        var visible: [HomeAccountRow] = []
        for row in accountRows {
            let id = try row.integer("id")
            guard let account = indexedAccounts[id], let currency = indexedCurrencies[account.currencyID], let balance = balances[id] else { throw DatabaseError.invalidData }
            guard !account.isClosed else { continue }
            guard let type = try HomeAccountType(rawValue: Int(row.integer("account_type"))) else { throw DatabaseError.invalidData }
            let period = periodByAccount[id, default: PeriodTotals()]
            visible.append(try HomeAccountRow(id: id, name: row.text("name"), bank: row.optionalText("bank"), type: type, favorite: row.integer("favorite") == 1, currency: currency, balance: balance, income: period.income, expenses: period.expenses, hasActivity: activeAccounts.contains(id)))
        }
        visible.sort {
            if $0.favorite != $1.favorite { return $0.favorite }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        let groups = HomeAccountType.displayOrder.compactMap { type -> HomeAccountGroup? in
            let rows = visible.filter { $0.type == type }
            return rows.isEmpty ? nil : HomeAccountGroup(type: type, accounts: rows)
        }
        let rateRows = try db.rows("SELECT from_currency_id,to_currency_id,rate FROM exchange_rates ORDER BY id")
        let rates = try rateRows.map { try ExchangeRate(fromCurrencyID: $0.integer("from_currency_id"), toCurrencyID: $0.integer("to_currency_id"), value: MoneyCodec.decodeRate($0.text("rate"))) }
        let converter = try CurrencyConverter(rates: rates)
        func converted(_ values: [MonetaryAmount]) throws -> Decimal? {
            do { return try converter.total(values.filter { $0.value != 0 }, to: display.ledger) }
            catch FinanceError.missingRate { return nil }
        }
        let total = try converted(visible.map { MonetaryAmount(value: $0.balance, currencyID: $0.currency.id) })
        let income = try converted(periodByCurrency.sorted { $0.key < $1.key }.map { MonetaryAmount(value: $0.value.income, currencyID: $0.key) })
        let expenses = try converted(periodByCurrency.sorted { $0.key < $1.key }.map { MonetaryAmount(value: $0.value.expenses, currencyID: $0.key) })
        // Difference follows the displayed period figures, so the visible equation
        // remains exact even if each converted aggregate rounded independently.
        let difference: Decimal?
        if let income, let expenses { difference = try DecimalArithmetic.subtract(income, expenses) }
        else { difference = nil }
        return HomeSnapshot(generation: generation, month: month, currency: display, totalBalance: total, income: income, expenses: expenses, difference: difference, groups: groups, accountCount: accounts.count)
    }
}
