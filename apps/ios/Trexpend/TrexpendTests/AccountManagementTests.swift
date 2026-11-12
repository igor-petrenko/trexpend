import Foundation
import Testing
@testable import Trexpend

private struct AccountCheckFailure: Error { let message: String }
private func accountCheck(_ condition: Bool, _ message: String) throws {
    guard condition else { throw AccountCheckFailure(message: message) }
}
private struct AccountFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("AccountChecks-" + UUID().uuidString)
    let resources: DatabaseResources
    init() throws { resources = try .bundled() }
    func lifecycle(_ name: String = "working") throws -> DatabaseLifecycle {
        try DatabaseLifecycle(directory: root.appendingPathComponent(name), resources: resources)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func image() throws -> Data {
        guard let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=") else { throw AccountError.image }
        return try AccountImageCodec.normalize(data)
    }
    func create(_ lifecycle: DatabaseLifecycle, generation: UUID, name: String = "Synthetic account", initial: String = "100.00") throws -> Int64 {
        let context = try lifecycle.accountEditor(accountID: nil, expectedGeneration: generation)
        var draft = AccountDraft()
        draft.name = name; draft.currencyID = context.catalog.currencies.first { $0.code == "USD" }!.id
        draft.initialBalance = initial; draft.bankID = 1
        _ = try lifecycle.saveAccount(draft, context: context, now: Date())
        return try lifecycle.managedAccounts(expectedGeneration: generation).accounts.first { $0.name == name }!.id
    }
}

@Suite("Account management")
struct AccountManagementTests {
    @Test func migrationPreservesLegacyRecordsAndLinksExactBanks() throws {
        let f = try AccountFixture(); defer { f.remove() }
        let url = f.root.appendingPathComponent("legacy.sqlite")
        try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: true)
        let db = try SQLiteConnection(url: url, create: true)
        try db.execute(f.resources.schema); try db.execute(f.resources.defaults)
        var old = f.resources; old.accountMigration = ""
        try DatabaseMigrator.upgrade(db, resources: old)
        try db.execute("""
            INSERT INTO accounts(id,name,currency_id,initial_balance,status,account_type,bank,account_number,created_at,updated_at)
            VALUES(1,'',1,'-10.00',1,1,'CIBC','0012','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z'),
            (2,'Duplicate',1,'0.00',1,1,'cibc','0001','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z');
            """)
        let before = try db.rows("SELECT * FROM accounts ORDER BY id")
        try DatabaseMigrator.upgrade(db, resources: f.resources)
        let after = try db.rows("SELECT * FROM accounts ORDER BY id")
        for (a,b) in zip(before,after) {
            for (key,value) in a.values { try accountCheck(b.values[key] == value, "Migration changed existing account fields.") }
        }
        try accountCheck(try after[0].optionalInteger("bank_id") == 2, "Exact bank was not linked.")
        try accountCheck(try after[1].optionalInteger("bank_id") != 2, "Distinct bank spelling was merged.")
        _ = try DatabaseValidator(resources: f.resources).validate(db, generation: UUID())
        try db.close()
    }

    @Test func createsEditsAndPreservesFinancialHistory() throws {
        let f = try AccountFixture(); defer { f.remove() }
        let lifecycle = try f.lifecycle(); let snapshot = try lifecycle.open(); let g = snapshot.generation
        let id = try f.create(lifecycle, generation: g, initial: "-100")
        let editor = try lifecycle.editor(transactionID: nil, expectedGeneration: g)
        var expense = TransactionDraft(localDate: "2026-01-01T12:00:00")
        expense.accountID = id; expense.categoryID = editor.categories.first!.id; expense.amount = "2.50"
        _ = try lifecycle.saveTransaction(expense, context: editor, now: Date(), timeZone: .gmt)
        let before = try lifecycle.accountEditor(accountID: id, expectedGeneration: g)
        var draft = try AccountDraft.editing(before.original!)
        draft.name = "Updated account"; draft.initialBalance = "200,50"; draft.accountNumber = "00045"; draft.notes = "Preserved notes"
        _ = try lifecycle.saveAccount(draft, context: before, now: Date())
        let account = try lifecycle.managedAccounts(expectedGeneration: g).accounts.first!
        try accountCheck(account.balance == 198, "Updated initial balance was not applied exactly.")
        let month = try CalendarMonth(year: 2026, month: 1)
        let history = try lifecycle.history(accountID: id, expectedGeneration: g, month: month)
        try accountCheck(history.account.expenses == Decimal(string: "2.50") && history.page.rows.count == 1, "Account edit changed history or monthly totals.")
        let all = try lifecycle.allHistory(expectedGeneration: g, month: month)
        try accountCheck(all.summary.totalBalance == 198, "All balance was not refreshed.")
        let saved = try lifecycle.accountEditor(accountID: id, expectedGeneration: g).original!
        try accountCheck(try saved.text("account_number") == "00045", "Leading zeros were lost.")
        try accountCheck(saved.values["current_balance"] == .null, "Derived balance was persisted.")
        try lifecycle.close()
    }

    @Test func rejectedWritesAreAtomicAndStaleFormsCannotSave() throws {
        let f = try AccountFixture(); defer { f.remove() }
        let lifecycle = try f.lifecycle(); let g = try lifecycle.open().generation
        let id = try f.create(lifecycle, generation: g)
        let context = try lifecycle.accountEditor(accountID: id, expectedGeneration: g)
        var draft = try AccountDraft.editing(context.original!)
        draft.name = "   "
        do { _ = try lifecycle.saveAccount(draft, context: context, now: Date()); throw AccountCheckFailure(message: "Empty name accepted.") }
        catch AccountError.name {}
        draft = try .editing(context.original!); draft.currencyID = context.catalog.currencies.first { $0.code == "CAD" }!.id
        do { _ = try lifecycle.saveAccount(draft, context: context, now: Date()); throw AccountCheckFailure(message: "Currency change accepted.") }
        catch AccountError.currency {}
        draft = try .editing(context.original!); draft.newImage = try f.image(); draft.appearance.color = "invalid"
        do { _ = try lifecycle.saveAccount(draft, context: context, now: Date()); throw AccountCheckFailure(message: "Invalid color accepted.") }
        catch DatabaseError.sqlite {}
        try lifecycle.close()
        let db = try SQLiteConnection(url: lifecycle.workingURL)
        try accountCheck(try db.rows("SELECT count(*) AS n FROM account_custom_images")[0].integer("n") == 0, "Failed save left an orphan image.")
        try db.close()
        _ = try lifecycle.open()
        _ = try lifecycle.setAccountFavorite(true, accountID: id, expectedGeneration: g)
        draft = try .editing(context.original!)
        do { _ = try lifecycle.saveAccount(draft, context: context, now: Date()); throw AccountCheckFailure(message: "Stale form saved.") }
        catch AccountError.changed {}
        _ = try lifecycle.reset(expectedGeneration: g)
        do { _ = try lifecycle.saveAccount(draft, context: context, now: Date()); throw AccountCheckFailure(message: "Old dataset saved.") }
        catch DatabaseError.staleDataset {}
        try lifecycle.close()
    }

    @Test func imagesSurviveExportImportAndResetToDefault() throws {
        let f = try AccountFixture(); defer { f.remove() }
        let lifecycle = try f.lifecycle(); let g = try lifecycle.open().generation
        let id = try f.create(lifecycle, generation: g)
        let context = try lifecycle.accountEditor(accountID: id, expectedGeneration: g)
        var draft = try AccountDraft.editing(context.original!); let image = try f.image(); draft.newImage = image
        _ = try lifecycle.saveAccount(draft, context: context, now: Date())
        let exported = try lifecycle.exportSnapshot(expectedGeneration: g)
        let target = try f.lifecycle("imported"); let empty = try target.open()
        let imported = try target.importDatabase(from: exported, expectedGeneration: empty.generation)
        let record = try target.accountEditor(accountID: id, expectedGeneration: imported.generation)
        let imageID = try record.original!.integer("custom_image_id")
        let pickerAccount = try target.accountCatalog(expectedGeneration: imported.generation).first { $0.id == id }!
        try accountCheck(pickerAccount.appearance.customImageID == imageID && pickerAccount.type == draft.type, "Account picker lost image metadata or account type.")
        try accountCheck(try target.customAccountImage(id: imageID, expectedGeneration: imported.generation) == image, "Backup lost image bytes.")
        var reset = try AccountDraft.editing(record.original!); reset.appearance.customImageID = nil; reset.appearance.imageID = 3
        _ = try target.saveAccount(reset, context: record, now: Date())
        try accountCheck(try target.customAccountImage(id: imageID, expectedGeneration: imported.generation) == nil, "Unused image was not removed.")
        try target.close(); try lifecycle.close()
    }

    @Test func closureClearsDefaultAndDeletionProtectsTransfers() throws {
        let f = try AccountFixture(); defer { f.remove() }
        let lifecycle = try f.lifecycle(); let g = try lifecycle.open().generation
        let a = try f.create(lifecycle, generation: g, name: "Sender")
        let b = try f.create(lifecycle, generation: g, name: "Receiver")
        _ = try lifecycle.setDefaultAccount(a, expectedGeneration: g)
        let editor = try lifecycle.editor(transactionID: nil, expectedGeneration: g)
        var transfer = TransactionDraft(localDate: "2026-01-01T12:00:00")
        transfer.type = .transfer; transfer.accountID = a; transfer.receiverID = b
        transfer.categoryID = editor.categories.first!.id; transfer.amount = "10"; transfer.receiverAmount = "9"; transfer.fee = "1"; transfer.feeFromReceiver = true
        _ = try lifecycle.saveTransaction(transfer, context: editor, now: Date(), timeZone: .gmt)
        for id in [a,b] {
            let context = try lifecycle.accountEditor(accountID: id, expectedGeneration: g)
            do { _ = try lifecycle.deleteAccount(context: context); throw AccountCheckFailure(message: "Referenced account deleted.") }
            catch AccountError.referenced {}
        }
        let context = try lifecycle.accountEditor(accountID: a, expectedGeneration: g)
        var closed = try AccountDraft.editing(context.original!); closed.isOpen = false
        let result = try lifecycle.saveAccount(closed, context: context, now: Date())
        try accountCheck(result.settings.defaultAccountID == nil, "Closed account remained default.")
        let closedHistory = try lifecycle.history(accountID: a, expectedGeneration: g, month: CalendarMonth(year: 2026, month: 1))
        try accountCheck(!closedHistory.account.isOpen && !closedHistory.page.rows.isEmpty, "Closure lost history or account eligibility.")
        let updated = try lifecycle.accountEditor(accountID: a, expectedGeneration: g)
        try accountCheck(try updated.original!.optionalText("close_date") != nil, "Closure date missing.")
        var reopened = try AccountDraft.editing(updated.original!); reopened.isOpen = true
        _ = try lifecycle.saveAccount(reopened, context: updated, now: Date())
        try accountCheck(try lifecycle.accountEditor(accountID: a, expectedGeneration: g).original!.optionalText("close_date") == nil, "Reopen retained closure date.")
        let unused = try f.create(lifecycle, generation: g, name: "Unused")
        let deletion = try lifecycle.accountEditor(accountID: unused, expectedGeneration: g)
        _ = try lifecycle.deleteAccount(context: deletion)
        try accountCheck(try lifecycle.managedAccounts(expectedGeneration: g).accounts.count == 2, "Unused account deletion failed.")
        try lifecycle.close()
    }

    @Test func imageLimitsAndDailyBackupAreEnforced() throws {
        let f = try AccountFixture(); defer { f.remove() }
        for invalid in [Data(), Data("not an image".utf8), Data(repeating: 0, count: AccountImageCodec.inputLimit + 1)] {
            do { _ = try AccountImageCodec.normalize(invalid); throw AccountCheckFailure(message: "Unsupported image accepted.") }
            catch AccountError.image {}
        }
        let lifecycle = try f.lifecycle(); let g = try lifecycle.open().generation
        let id = try f.create(lifecycle, generation: g)
        let context = try lifecycle.accountEditor(accountID: id, expectedGeneration: g)
        var draft = try AccountDraft.editing(context.original!); let image = try f.image(); draft.newImage = image
        _ = try lifecycle.saveAccount(draft, context: context, now: Date())
        let backup = try lifecycle.dailyBackup(in: f.root.appendingPathComponent("Backups"), now: Date(), timeZone: .gmt, expectedGeneration: g)
        let db = try SQLiteConnection(url: backup, readOnly: true)
        try accountCheck(try db.rows("SELECT png_data FROM account_custom_images")[0].blob("png_data") == image, "Daily backup lost image bytes.")
        _ = try DatabaseValidator(resources: f.resources).validate(db, generation: g)
        try db.close(); try lifecycle.close()
    }

    @MainActor @Test func accountCommitRefreshesBothHistoryProjections() async throws {
        let f = try AccountFixture(); defer { f.remove() }
        let deps = AppDependencies(directory: f.root.appendingPathComponent("session"))
        await deps.session.start(store: deps.database, settings: deps.settings)
        let g = deps.session.snapshot!.generation
        let state = AccountEditorState()
        await state.load(dependencies: deps, generation: g, accountID: nil)
        state.draft.name = "Session account"; state.draft.initialBalance = "10"
        try accountCheck(state.isDirty, "Edited draft not tracked.")
        try accountCheck(await state.save(dependencies: deps), "Account state did not save.")
        let account = try await deps.database.managedAccounts(expectedGeneration: g).accounts.first!
        let context = try await deps.database.editor(transactionID: nil, expectedGeneration: g)
        for number in 1...60 {
            var expense = TransactionDraft(localDate: "2026-01-01T12:00:00")
            expense.accountID = account.id; expense.categoryID = context.categories.first!.id; expense.amount = "0"
            expense.notes = String(number)
            let saved = try await deps.database.saveTransaction(expense, context: context, now: Date(), timeZone: .gmt)
            deps.session.transactionDidCommit(saved, settings: deps.settings)
        }
        let month = try CalendarMonth(year: 2026, month: 1)
        let all = AllHistoryState(); let history = HistoryState()
        await all.ensureLoaded(database: deps.database, session: deps.session, month: month)
        await all.loadMore(database: deps.database, session: deps.session)
        await history.ensureLoaded(accountID: account.id, database: deps.database, session: deps.session, month: month)
        await history.loadMore(database: deps.database, session: deps.session)
        try accountCheck(all.rows.count == 60 && history.rows.count == 60, "Initial history range missing.")
        let editor = AccountEditorState()
        await editor.load(dependencies: deps, generation: g, accountID: account.id)
        editor.draft.name = "Renamed session account"; editor.draft.initialBalance = "20"
        try accountCheck(await editor.save(dependencies: deps), "Account edit failed.")
        await all.ensureLoaded(database: deps.database, session: deps.session, month: month)
        await history.ensureLoaded(accountID: account.id, database: deps.database, session: deps.session, month: month)
        try accountCheck(all.rows.count == 60 && history.rows.count == 60, "Account edit discarded loaded history range.")
        try accountCheck(all.content?.summary.totalBalance == 20 && history.content?.account.balance == 20, "History summaries were stale after account save.")
        try accountCheck(history.content?.account.name == "Renamed session account", "History metadata did not refresh.")
        try await deps.database.close()
    }


    @Test(arguments: ReplacementBoundary.allCases)
    func interruptedV3UpgradeRemainsRecoverable(_ boundary: ReplacementBoundary) throws {
        let f = try AccountFixture(); defer { f.remove() }
        let directory = f.root.appendingPathComponent("upgrade")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try SQLiteConnection(url: directory.appendingPathComponent("ledger.sqlite"), create: true)
        try db.execute(f.resources.schema); try db.execute(f.resources.defaults)
        var old = f.resources; old.accountMigration = ""
        try DatabaseMigrator.upgrade(db, resources: old)
        try db.execute("""
            INSERT INTO accounts(id,name,currency_id,initial_balance,status,account_type,bank,created_at,updated_at)
            VALUES(1,'Legacy account',1,'12.00',1,1,'CIBC','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z');
            """)
        try db.close()
        let interrupted = try DatabaseLifecycle(directory: directory, resources: f.resources) {
            if $0 == boundary { throw LifecycleInterruption() }
        }
        do { _ = try interrupted.open(); throw AccountCheckFailure(message: "Upgrade boundary was not reached.") }
        catch is LifecycleInterruption {}
        let recovered = try DatabaseLifecycle(directory: directory, resources: f.resources)
        let snapshot = try recovered.open()
        let catalog = try recovered.managedAccounts(expectedGeneration: snapshot.generation)
        try accountCheck(catalog.accounts.count == 1 && catalog.accounts[0].balance == 12 && catalog.accounts[0].bankID == 2, "Interrupted upgrade lost account data.")
        let archives = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Recovery").path)
        try accountCheck(archives.contains { $0.hasPrefix("Before-v5-") }, "Pre-upgrade recovery copy missing.")
        try recovered.close()
    }

}
