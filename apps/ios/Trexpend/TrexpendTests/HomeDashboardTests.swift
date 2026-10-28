import Foundation
import Testing
@testable import Trexpend

private struct HomeFixture {
    let root: URL
    let resources: DatabaseResources
    let usd: Int64
    let cad: Int64
    let eur: Int64
    var month: CalendarMonth { try! CalendarMonth(year: 2026, month: 7) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("HomeTest-" + UUID().uuidString)
        resources = try .bundled()
        let lifecycle = try DatabaseLifecycle(directory: root, resources: resources)
        _ = try lifecycle.open()
        try lifecycle.close()
        let db = try SQLiteConnection(url: root.appendingPathComponent("ledger.sqlite"))
        func currency(_ code: String) throws -> Int64 { try db.rows("SELECT id FROM currencies WHERE code=?", parameters: [.text(code)])[0].integer("id") }
        usd = try currency("USD"); cad = try currency("CAD"); eur = try currency("EUR")
        try db.run("UPDATE app_settings SET display_currency_id=?", parameters: [.integer(cad)])
        func account(_ id: Int64, _ name: String, _ currency: Int64, _ initial: String, _ type: Int64, closed: Bool = false, favorite: Bool = false) throws {
            try db.run("INSERT INTO accounts(id,name,bank,currency_id,initial_balance,status,account_type,favorite,created_at,updated_at) VALUES (?,?,'Synthetic Bank',?,?,?,?,?,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')", parameters: [.integer(id),.text(name),.integer(currency),.text(initial),.integer(closed ? 2 : 1),.integer(type),.integer(favorite ? 1 : 0)])
        }
        try account(1,"Everyday",usd,"100.00",1,favorite:true)
        try account(2,"Cash",cad,"50.00",3)
        try account(3,"Closed",usd,"200.00",2,closed:true)
        try account(4,"Deposit",cad,"500.00",4)
        try account(5,"Credit",cad,"-100.00",2)
        try account(6,"Dormant",usd,"25.00",3)
        try account(7,"Transfer only",cad,"10.00",1)
        var id: Int64 = 0
        func transaction(_ kind: Int64, _ account: Int64, _ amount: String, _ date: String, to: Int64? = nil, received: String? = nil, fee: String = "0.00", charged: Int64? = nil) throws {
            id += 1
            try db.run("INSERT INTO transactions(id,transaction_type,account_id,amount,date,category_id,to_account_id,to_amount,fee,fee_account_id,created_at,updated_at) VALUES (?,?,?,?,?,1,?,?,?,?,'2026-07-01T12:00:00Z','2026-07-01T12:00:00Z')", parameters: [.integer(id),.integer(kind),.integer(account),.text(amount),.text(date),to.map(SQLValue.integer) ?? .null,received.map(SQLValue.text) ?? .null,.text(fee),charged.map(SQLValue.integer) ?? .null])
        }
        try transaction(1,1,"10.00","2026-06-30T23:59:59")
        try transaction(2,1,"100.00","2026-07-01T00:00:00")
        try transaction(1,1,"20.00","2026-07-02T12:00:00")
        try transaction(3,1,"30.00","2026-07-03T12:00:00",to:2,received:"40.00",fee:"2.00",charged:2)
        try transaction(3,2,"5.00","2026-07-04T12:00:00",to:4,received:"5.00",fee:"1.00",charged:2)
        try transaction(3,4,"1.00","2026-07-05T12:00:00",to:7,received:"1.00",charged:4)
        try transaction(2,3,"200.00","2026-07-06T12:00:00")
        try transaction(1,3,"50.00","2026-07-31T23:59:59")
        try db.run("INSERT INTO exchange_rates(id,from_currency_id,to_currency_id,rate,updated_at) VALUES (1,?,?,'2','2026-07-01T00:00:00Z')", parameters: [.integer(usd),.integer(cad)])
        try db.close()
    }
    func remove() throws { try FileManager.default.removeItem(at: root) }
    func lifecycle() throws -> DatabaseLifecycle { try DatabaseLifecycle(directory: root, resources: resources) }
    func connection() throws -> SQLiteConnection { try SQLiteConnection(url: root.appendingPathComponent("ledger.sqlite")) }
}

@Suite("Home dashboard storage and finance")
struct HomeDashboardTests {
    @Test
    func nativeBalancesClosedActivityAndFees() throws {
        let fixture = try HomeFixture(); defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle()
        let snapshot = try lifecycle.open()
        let home = try lifecycle.home(expectedGeneration: snapshot.generation, month: fixture.month)
        #expect(home.totalBalance == 827)
        #expect(home.income == 600 && home.expenses == 143 && home.difference == 457)
        #expect(home.groups.map(\.type) == [.creditCard,.checking,.cash,.deposit])
        let accounts = Dictionary(uniqueKeysWithValues: home.groups.flatMap(\.accounts).map { ($0.id,$0) })
        #expect(accounts[3] == nil)
        #expect(accounts[1]?.balance == 140 && accounts[1]?.income == 100 && accounts[1]?.expenses == 20)
        #expect(accounts[2]?.balance == 82 && accounts[2]?.income == 0 && accounts[2]?.expenses == 3)
        #expect(accounts[4]?.balance == 504)
        #expect(accounts[5]?.balance == -100 && accounts[5]?.hasActivity == false)
        #expect(accounts[6]?.hasActivity == false)
        #expect(accounts[7]?.hasActivity == true && accounts[7]?.income == 0 && accounts[7]?.expenses == 0)
        #expect(accounts[1]?.bank == "Synthetic Bank" && accounts[1]?.favorite == true)
        try lifecycle.close()
    }

    @Test
    func missingRateKeepsNativeRowsAndIndependentFigures() throws {
        let fixture = try HomeFixture(); defer { try? fixture.remove() }
        let db = try fixture.connection()
        try db.run("UPDATE accounts SET currency_id=? WHERE id=6", parameters: [.integer(fixture.eur)])
        try db.close()
        let lifecycle = try fixture.lifecycle(); let snapshot = try lifecycle.open()
        let home = try lifecycle.home(expectedGeneration: snapshot.generation, month: fixture.month)
        #expect(home.totalBalance == nil)
        #expect(home.income == 600 && home.expenses == 143 && home.difference == 457)
        #expect(home.groups.flatMap(\.accounts).first { $0.id == 6 }?.balance == 25)
        let emptyMonth = try lifecycle.home(expectedGeneration: snapshot.generation, month: CalendarMonth(year: 2026, month: 8))
        #expect(emptyMonth.income == 0 && emptyMonth.expenses == 0 && emptyMonth.difference == 0)
        #expect(emptyMonth.groups.flatMap(\.accounts).allSatisfy { !$0.hasActivity })
        try lifecycle.close()
    }

    @Test
    func unavailablePeriodCurrencyDoesNotBecomePartialTotal() throws {
        let fixture = try HomeFixture(); defer { try? fixture.remove() }
        let db = try fixture.connection(); try db.run("DELETE FROM exchange_rates"); try db.close()
        let lifecycle = try fixture.lifecycle(); let snapshot = try lifecycle.open()
        let home = try lifecycle.home(expectedGeneration: snapshot.generation, month: fixture.month)
        #expect(home.income == nil && home.expenses == nil && home.difference == nil)
        #expect(home.groups.flatMap(\.accounts).count == 6)
        try lifecycle.close()
    }

    @Test
    func currencyPreferencePersistsWithoutRewritingAmounts() throws {
        let fixture = try HomeFixture(); defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle(); let initial = try lifecycle.open()
        let changed = try lifecycle.setDisplayCurrency(fixture.usd, expectedGeneration: initial.generation)
        #expect(changed.generation == initial.generation && changed.settings.displayCurrencyCode == "USD")
        let home = try lifecycle.home(expectedGeneration: initial.generation, month: fixture.month)
        #expect(home.totalBalance == Decimal(string: "413.50"))
        #expect(home.income == 300 && home.expenses == Decimal(string: "71.50") && home.difference == Decimal(string: "228.50"))
        #expect(throws: DatabaseError.invalidData) { try lifecycle.setDisplayCurrency(-1, expectedGeneration: initial.generation) }
        try lifecycle.close()
        let reopened = try fixture.lifecycle(); #expect(try reopened.open().settings.displayCurrencyCode == "USD"); try reopened.close()
        let db = try fixture.connection()
        #expect(try db.rows("SELECT amount FROM transactions WHERE id=1")[0].text("amount") == "10.00")
        #expect(try db.rows("SELECT count(*) AS n FROM accounts WHERE current_balance IS NOT NULL")[0].integer("n") == 0)
        try db.close()
    }

    @Test
    func emptyClosedAndStaleDatasets() throws {
        let fixture = try HomeFixture(); defer { try? fixture.remove() }
        let db = try fixture.connection(); try db.run("UPDATE accounts SET status=2"); try db.close()
        let lifecycle = try fixture.lifecycle(); let initial = try lifecycle.open()
        let closed = try lifecycle.home(expectedGeneration: initial.generation, month: fixture.month)
        #expect(closed.groups.isEmpty && closed.accountCount == 7 && closed.totalBalance == 0)
        #expect(closed.income == 600 && closed.expenses == 143)
        let reset = try lifecycle.reset(expectedGeneration: initial.generation)
        #expect(throws: DatabaseError.staleDataset) { try lifecycle.home(expectedGeneration: initial.generation, month: fixture.month) }
        #expect(throws: DatabaseError.staleDataset) { try lifecycle.setDisplayCurrency(fixture.usd, expectedGeneration: initial.generation) }
        let empty = try lifecycle.home(expectedGeneration: reset.generation, month: fixture.month)
        #expect(empty.groups.isEmpty && empty.accountCount == 0 && empty.difference == 0)
        try lifecycle.close()
    }

    @Test
    func decimalFormattingDoesNotRoundThroughDouble() {
        #expect(MoneyPresentation.number(Decimal(string: "9007199254740993.01")!, places: 2, locale: Locale(identifier: "en_US")) == "9,007,199,254,740,993.01")
        #expect(MoneyPresentation.number(0, places: 2, locale: Locale(identifier: "en_US")) == "0.00")
        #expect(MoneyPresentation.number(Decimal(string: "0.12345678")!, places: 8, locale: Locale(identifier: "en_US")) == "0.12345678")
    }
}

@Suite("Home loading and preference refresh")
@MainActor
struct HomeStateTests {
    @Test
    func loadCurrencyChangeAndReplacement() async throws {
        let fixture = try HomeFixture(); defer { try? fixture.remove() }
        let dependencies = AppDependencies(directory: fixture.root)
        await dependencies.start()
        let state = HomeState()
        await state.load(database: dependencies.database, session: dependencies.session, month: fixture.month)
        #expect(state.content?.income == 600 && state.error == nil && !state.isLoading)
        let settings = SettingsState(dependencies: dependencies)
        await settings.loadCurrencies()
        #expect(settings.currencies.contains { $0.code == "CAD" })
        #expect(await settings.setDisplayCurrency(fixture.usd))
        await state.load(database: dependencies.database, session: dependencies.session, month: fixture.month)
        #expect(state.content?.income == 300 && state.content?.currency.code == "USD")
        let replacement = try await dependencies.database.reset(expectedGeneration: dependencies.session.snapshot!.generation)
        dependencies.session.publish(replacement, settings: dependencies.settings)
        await state.load(database: dependencies.database, session: dependencies.session, month: fixture.month)
        #expect(state.content?.groups.isEmpty == true && state.content?.generation == replacement.generation)
        try await dependencies.database.close()
    }
}
