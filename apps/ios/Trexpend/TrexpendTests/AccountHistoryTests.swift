import Foundation
import Testing
import UIKit
@testable import Trexpend

private struct HistoryFixture {
    let root: URL
    let resources: DatabaseResources
    var month: CalendarMonth { try! CalendarMonth(year: 2026, month: 10) }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        resources = try .bundled()
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    var url: URL { root.appendingPathComponent("ledger.sqlite") }
    func legacy() throws {
        let db = try SQLiteConnection(url: url, create: true)
        try db.execute(resources.schema); try db.execute(resources.defaults)
        try db.run("INSERT INTO accounts(id,name,currency_id,initial_balance,status,account_type,created_at,updated_at) VALUES (1,'Synthetic card',1,'100.00',1,2,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z'),(2,'Synthetic cash',34,'50.00',1,3,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')")
        try db.run("INSERT INTO exchange_rates(from_currency_id,to_currency_id,rate,updated_at) VALUES (1,34,'1.37','2026-01-01T00:00:00Z')")
        try db.run("UPDATE app_settings SET display_currency_id=34")
        try db.close()
    }
    func insert(_ db: SQLiteConnection, id: Int64, type: Int64 = 1, source: Int64 = 1, amount: String = "1.00", date: String = "2026-10-24T12:00:00", destination: Int64? = nil, received: String? = nil, fee: String = "0.00", charged: Int64? = nil) throws {
        try db.run("INSERT INTO transactions(id,transaction_type,account_id,amount,date,category_id,to_account_id,to_amount,fee,fee_account_id,notes,created_at,updated_at) VALUES (?,?,?,?,?,10,?,?,?,?,?,'2026-10-24T16:00:00Z','2026-10-24T16:00:00Z')", parameters: [.integer(id),.integer(type),.integer(source),.text(amount),.text(date),destination.map(SQLValue.integer) ?? .null,received.map(SQLValue.text) ?? .null,.text(fee),charged.map(SQLValue.integer) ?? .null,.text("Synthetic notes")])
    }
    func lifecycle(fault: (@Sendable (ReplacementBoundary) throws -> Void)? = nil) throws -> DatabaseLifecycle {
        try DatabaseLifecycle(directory: root, resources: resources, fault: fault)
    }
}

@Suite("Account history and schema upgrade")
struct AccountHistoryTests {
    @Test
    func legacyUpgradePreservesFinanceAndIconSelection() throws {
        let f = try HistoryFixture(); defer { f.remove() }; try f.legacy()
        let db = try SQLiteConnection(url: f.url)
        try f.insert(db,id:1,type:3,amount:"10.00",destination:2,received:"13.00",fee:"2.00",charged:1)
        let before = try db.rows("SELECT * FROM transactions").map(\.values)
        try db.close()
        let life = try f.lifecycle(); let snapshot = try life.open()
        let home = try life.home(expectedGeneration:snapshot.generation,month:f.month)
        let history = try life.history(accountID:1,expectedGeneration:snapshot.generation,month:f.month)
        #expect(history.account.balance == 88 && history.account.expenses == 2)
        #expect(home.groups.flatMap(\.accounts).first { $0.id == 1 }?.balance == history.account.balance)
        #expect(history.page.rows[0].symbol == "cart")
        #expect(history.page.rows[0].feeCurrency?.code == "USD")
        try life.close()
        let upgraded = try SQLiteConnection(url:f.url)
        #expect(try DatabaseMigrator.version(upgraded) == 2)
        #expect(try upgraded.rows("SELECT * FROM transactions").map(\.values) == before)
        try upgraded.run("UPDATE categories SET name='Renamed',icon_id=16 WHERE id=10")
        try upgraded.close()
        let reopened = try f.lifecycle(); let current = try reopened.open()
        #expect(try reopened.history(accountID:1,expectedGeneration:current.generation,month:f.month).page.rows[0].symbol == "cup.and.saucer")
        let exported = try reopened.exportSnapshot(expectedGeneration:current.generation)
        let copy = try SQLiteConnection(url:exported,readOnly:true)
        #expect(try DatabaseMigrator.version(copy) == 2)
        try copy.close()
        let restored = try reopened.importDatabase(from:exported,expectedGeneration:current.generation)
        #expect(try reopened.history(accountID:1,expectedGeneration:restored.generation,month:f.month).page.rows[0].symbol == "cup.and.saucer")
        try reopened.discardExport(exported); try reopened.close()
    }

    @Test(arguments: ReplacementBoundary.allCases)
    func upgradeInterruptionRecovers(_ boundary: ReplacementBoundary) throws {
        let f = try HistoryFixture(); defer { f.remove() }; try f.legacy()
        let interrupted = try f.lifecycle { if $0 == boundary { throw LifecycleInterruption() } }
        #expect(throws: LifecycleInterruption.self) { try interrupted.open() }
        let recovered = try f.lifecycle(); let snapshot = try recovered.open()
        #expect(snapshot.accountCount == 2)
        try recovered.close()
        let db = try SQLiteConnection(url:f.url,readOnly:true)
        #expect(try DatabaseMigrator.version(db) == 2)
        #expect(try db.rows("PRAGMA foreign_key_check").isEmpty)
        try db.close()
    }

    @Test
    func migrationFailureKeepsLegacyAndRejectsAmbiguousDefaults() throws {
        let f = try HistoryFixture(); defer { f.remove() }; try f.legacy()
        let db = try SQLiteConnection(url:f.url)
        try db.run("INSERT INTO categories(id,name,parent_id) VALUES (100,'Groceries',9),(101,'Custom',NULL)")
        var broken = f.resources; broken.iconDefaults = Data("invalid-json".utf8)
        let failed = try DatabaseLifecycle(directory:f.root,resources:broken)
        #expect(throws:(any Error).self) { try failed.open() }
        #expect(try DatabaseMigrator.version(db) == 1)
        try db.close()
        let life = try f.lifecycle(); _ = try life.open(); try life.close()
        let migrated = try SQLiteConnection(url:f.url)
        #expect(try migrated.rows("SELECT icon_id FROM categories WHERE id IN (10,100,101)").allSatisfy { try $0.optionalInteger("icon_id") == nil })
        try migrated.close()
    }

    @Test
    func pagesHaveStableDescendingOrderAndCompleteSummary() throws {
        let f = try HistoryFixture(); defer { f.remove() }; try f.legacy()
        let db = try SQLiteConnection(url:f.url)
        try db.transaction { for id in 1...121 { try f.insert(db,id:Int64(id)) } }
        try f.insert(db,id:122,amount:"0.00",date:"2026-10-01T00:00:00")
        try f.insert(db,id:123,type:2,amount:"20.00",date:"2026-09-30T23:59:59")
        try db.close()
        let life = try f.lifecycle(); let snapshot = try life.open()
        let history = try life.history(accountID:1,expectedGeneration:snapshot.generation,month:f.month)
        #expect(history.account.balance == -1 && history.account.expenses == 121 && history.account.income == 0)
        #expect(history.page.rows.first?.id == 121 && history.page.rows.last?.id == 72)
        var ids = history.page.rows.map(\.id), cursor = history.page.next
        while let next = cursor {
            let page = try life.historyPage(accountID:1,expectedGeneration:snapshot.generation,cursor:next)
            ids += page.rows.map(\.id); cursor = page.next
        }
        #expect(ids == Array(stride(from:Int64(121),through:1,by:-1)) + [122,123])
        #expect(Set(ids).count == 123)
        let replaced = try life.reset(expectedGeneration:snapshot.generation)
        #expect(throws:DatabaseError.staleDataset) { try life.historyPage(accountID:1,expectedGeneration:replaced.generation,cursor:history.page.next!) }
        try life.close()
    }

    @Test
    func indexedPagesAndLegacyImportRecovery() throws {
        let f = try HistoryFixture(); defer { f.remove() }; try f.legacy()
        let db = try SQLiteConnection(url:f.url)
        try db.transaction { for id in 1...5000 { try f.insert(db,id:Int64(id)) } }
        try db.close()
        let life = try f.lifecycle(); let initial = try life.open()
        let migrated = try SQLiteConnection(url:f.url,readOnly:true)
        let details = try migrated.rows("EXPLAIN QUERY PLAN " + HistoryRead.pageQuery(cursor:true), parameters:[.integer(1),.text("2026-10-24T12:00:00"),.integer(3000),.integer(1),.text("2026-10-24T12:00:00"),.integer(3000)]).map { try $0.text("detail") }
        #expect(details.contains { $0.contains("SEARCH transactions USING INDEX transactions_source_history_idx") })
        #expect(details.contains { $0.contains("SEARCH transactions USING INDEX transactions_destination_history_idx") })
        #expect(!details.contains { $0.contains("SCAN transactions") })
        let page = try life.historyPage(accountID:1,expectedGeneration:initial.generation,cursor:HistoryCursor(generation:initial.generation,accountID:1,date:"2026-10-24T12:00:00",id:3000))
        #expect(page.rows.count == 50 && page.rows.first?.id == 2999)
        try migrated.close(); try life.close()
        let source = try HistoryFixture(); defer { source.remove() }; try source.legacy()
        let sourceBytes = try Data(contentsOf:source.url)
        let destination = try HistoryFixture(); defer { destination.remove() }
        let recovery = try destination.lifecycle()
        let restored = try recovery.importDatabase(from:source.url,expectedGeneration:nil)
        #expect(restored.accountCount == 2)
        #expect(try Data(contentsOf:source.url) == sourceBytes)
        let imported = try SQLiteConnection(url:destination.url,readOnly:true)
        #expect(try DatabaseMigrator.version(imported) == 2)
        try imported.close(); try recovery.close()
    }

    @Test
    func legacyDailyBackupRemainsUsableAndImportSourceUnchanged() throws {
        let f = try HistoryFixture(); defer { f.remove() }; try f.legacy()
        let sourceBytes = try Data(contentsOf:f.url)
        let folder = f.root.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let backup = folder.appendingPathComponent("Trexpend-Auto-2026-10-25-" + UUID().uuidString + ".sqlite")
        try sourceBytes.write(to:backup)
        let life = try f.lifecycle(); let initial = try life.open()
        let empty = try life.history(accountID:1,expectedGeneration:initial.generation,month:f.month)
        #expect(empty.page.rows.isEmpty && empty.page.next == nil && empty.account.balance == 100)
        #expect(empty.account.income == 0 && empty.account.expenses == 0 && empty.convertedBalance == 137)
        let now = LocalDateTime.calendar(in:.gmt).date(from:DateComponents(year:2026,month:10,day:25,hour:12))!
        #expect(try life.dailyBackup(in:folder,now:now,timeZone:.gmt,expectedGeneration:initial.generation) == backup)
        #expect(try Data(contentsOf:backup) == sourceBytes)
        let restored = try life.importDatabase(from:backup,expectedGeneration:initial.generation)
        #expect(restored.accountCount == 2 && restored.generation != initial.generation)
        #expect(try Data(contentsOf:backup) == sourceBytes)
        try life.close()
    }

    @Test
    func transferReceiverFeeAndMissingConversion() throws {
        let f = try HistoryFixture(); defer { f.remove() }; try f.legacy()
        let db = try SQLiteConnection(url:f.url)
        try f.insert(db,id:1,type:3,amount:"10.00",destination:2,received:"13.00",fee:"3.00",charged:2)
        try f.insert(db,id:2,type:2,source:2,amount:"5.00")
        try db.run("DELETE FROM exchange_rates"); try db.close()
        let life = try f.lifecycle(); let snapshot = try life.open()
        let source = try life.history(accountID:1,expectedGeneration:snapshot.generation,month:f.month)
        let receiver = try life.history(accountID:2,expectedGeneration:snapshot.generation,month:f.month)
        #expect(source.account.balance == 90 && source.account.expenses == 0 && source.convertedBalance == nil)
        #expect(receiver.account.balance == 65 && receiver.account.expenses == 3 && receiver.account.income == 5)
        #expect(receiver.difference == 2 && source.difference == 0)
        let transfer = receiver.page.rows.first { $0.type == .transfer }!
        #expect(transfer.incoming && transfer.amount == 13 && transfer.counterpartAmount == 10)
        #expect(transfer.feeCurrency?.code == "CAD" && transfer.feeAccountName == "Synthetic cash")
        try life.close()
    }

    @Test
    @MainActor
    func iconsResolveAndStatePagesMerge() async throws {
        let f = try HistoryFixture(); defer { f.remove() }; try f.legacy()
        let db = try SQLiteConnection(url:f.url)
        try db.transaction { for id in 1...65 { try f.insert(db,id:Int64(id)) } }; try db.close()
        let dependencies = AppDependencies(directory:f.root); await dependencies.start()
        let state = HistoryState()
        await state.load(accountID:1,database:dependencies.database,session:dependencies.session,month:f.month)
        #expect(state.rows.count == 50 && state.days.count == 1)
        try await dependencies.database.close()
        await state.loadMore(database:dependencies.database,session:dependencies.session)
        #expect(state.rows.count == 50 && state.pageError != nil && state.next != nil)
        _ = try await dependencies.database.open()
        await state.loadMore(database:dependencies.database,session:dependencies.session)
        #expect(state.rows.count == 65 && state.days.count == 1 && state.next == nil)
        #expect(CategoryIconView.resolvedSymbol(nil) == "square.grid.2x2")
        #expect(CategoryIconView.resolvedSymbol("not.a.real.symbol.synthetic") == "square.grid.2x2")
        let symbols = try SQLiteConnection(url:f.url,readOnly:true)
        for row in try symbols.rows("SELECT system_name FROM category_icons") { #expect(UIImage(systemName:try row.text("system_name")) != nil) }
        try symbols.close()
        let settings = SettingsState(dependencies:dependencies)
        #expect(await settings.setDisplayCurrency(1))
        await state.load(accountID:1,database:dependencies.database,session:dependencies.session,month:f.month)
        #expect(state.content?.displayCurrency.code == "USD" && state.content?.convertedBalance == nil)
        #expect(state.rows.count == 50 && state.next != nil)
        let store = dependencies.database
        let oldGeneration = dependencies.session.snapshot!.generation
        let month = f.month
        async let reading: AccountHistorySnapshot? = try? store.history(accountID:1,expectedGeneration:oldGeneration,month:month)
        let replacement = try await store.reset(expectedGeneration:oldGeneration)
        let previousRead = await reading
        #expect(previousRead == nil || previousRead?.generation == oldGeneration)
        dependencies.session.publish(replacement,settings:dependencies.settings)
        await state.loadMore(database:dependencies.database,session:dependencies.session)
        await state.load(accountID:1,database:dependencies.database,session:dependencies.session,month:f.month)
        #expect(state.content == nil && state.rows.isEmpty && state.error != nil)
        try await dependencies.database.close()
    }
}
