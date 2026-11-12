import Foundation
import Testing
@testable import Trexpend

private struct CategoryCheckFailure: Error { let message: String }
private func categoryCheck(_ condition: Bool, _ message: String) throws {
    guard condition else { throw CategoryCheckFailure(message: message) }
}
private struct CategoryFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CategoryChecks-" + UUID().uuidString)
    let resources: DatabaseResources
    init() throws { resources = try .bundled() }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func lifecycle(_ name: String = "working") throws -> DatabaseLifecycle {
        try DatabaseLifecycle(directory: root.appendingPathComponent(name), resources: resources)
    }
    func create(_ life: DatabaseLifecycle, _ g: UUID, name: String, parent: Int64? = nil, active: Bool = true) throws -> Int64 {
        let context = try life.categoryEditor(id: nil, expectedGeneration: g)
        let draft = CategoryDraft(name: name, parentID: parent, active: active)
        _ = try life.saveCategory(draft, context: context)
        return try life.categoryCatalog(expectedGeneration: g).categories.filter { $0.name == name && $0.parentID == parent }.map(\.id).max()!
    }
}

@Suite("Category management")
struct CategoryManagementTests {
    @Test func v4UpgradePreservesRecordsAndInitializesSiblingOrder() throws {
        let f = try CategoryFixture(); defer { f.remove() }
        try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: true)
        let db = try SQLiteConnection(url: f.root.appendingPathComponent("v4.sqlite"), create: true)
        try db.execute(f.resources.schema); try db.execute(f.resources.defaults)
        var old = f.resources; old.categoryMigration = ""
        try DatabaseMigrator.upgrade(db, resources: old)
        let before = try db.rows("SELECT * FROM categories ORDER BY id")
        let defaults = try db.rows("SELECT * FROM app_settings").map(\.values)
        var broken = f.resources; broken.categoryMigration += "\nSELECT missing_column FROM missing_table;"
        do { try DatabaseMigrator.upgrade(db, resources: broken); throw CategoryCheckFailure(message: "Broken migration succeeded.") }
        catch DatabaseError.sqlite {}
        try categoryCheck(try DatabaseMigrator.version(db) == 4, "Failed migration advanced version.")
        try categoryCheck(try db.rows("SELECT * FROM categories ORDER BY id").map(\.values) == before.map(\.values), "Failed migration changed category data.")
        try DatabaseMigrator.upgrade(db, resources: f.resources)
        try DatabaseMigrator.upgrade(db, resources: f.resources)
        let after = try db.rows("SELECT * FROM categories ORDER BY id")
        try categoryCheck(before.count == after.count, "Upgrade changed category count.")
        for (a,b) in zip(before,after) {
            for (key,value) in a.values { try categoryCheck(b.values[key] == value, "Upgrade changed existing category metadata.") }
        }
        try categoryCheck(try db.rows("SELECT * FROM app_settings").map(\.values) == defaults, "Upgrade changed defaults.")
        for row in after {
            let siblings = try CategoryRead.orderedRows(db, parentID: row.optionalInteger("parent_id"))
            for (index,sibling) in siblings.enumerated() { try categoryCheck(try sibling.integer("sort_order") == index, "Initial sibling order is not contiguous.") }
        }
        _ = try DatabaseValidator(resources: f.resources).validate(db, generation: UUID())
        try categoryCheck(try DatabaseMigrator.version(db) == 5, "Upgrade did not reach v5.")
        try db.close()
    }

    @Test func creationReparentingAndCycleProtection() throws {
        let f = try CategoryFixture(); defer { f.remove() }
        let life = try f.lifecycle(); let g = try life.open().generation
        let parent = try f.create(life, g, name: "Synthetic parent")
        let child = try f.create(life, g, name: "Synthetic child", parent: parent)
        let leaf = try f.create(life, g, name: "Synthetic leaf", parent: child)
        let context = try life.categoryEditor(id: parent, expectedGeneration: g)
        var cycle = try CategoryDraft.editing(context.original!); cycle.parentID = leaf
        do { _ = try life.saveCategory(cycle, context: context); throw CategoryCheckFailure(message: "Cycle was accepted.") }
        catch CategoryError.parent {}
        cycle.parentID = parent
        do { _ = try life.saveCategory(cycle, context: context); throw CategoryCheckFailure(message: "Self parent was accepted.") }
        catch CategoryError.parent {}
        var empty = CategoryDraft(); empty.name = " \n "
        do { _ = try life.saveCategory(empty, context: life.categoryEditor(id: nil, expectedGeneration: g)); throw CategoryCheckFailure(message: "Empty name accepted.") }
        catch CategoryError.name {}
        let destination = try f.create(life, g, name: "Synthetic destination")
        let existing = try f.create(life, g, name: "Existing sibling", parent: destination)
        let childContext = try life.categoryEditor(id: child, expectedGeneration: g)
        var moved = try CategoryDraft.editing(childContext.original!); moved.parentID = destination
        _ = try life.saveCategory(moved, context: childContext)
        let catalog = try life.categoryCatalog(expectedGeneration: g)
        try categoryCheck(catalog.categories.filter { $0.parentID == destination }.map(\.id) == [existing,child], "Moved category was not appended.")
        try categoryCheck(catalog.descendants(of: destination).contains(leaf), "Reparenting lost descendants.")
        _ = try f.create(life, g, name: "Synthetic child", parent: destination)
        try categoryCheck(try life.categoryCatalog(expectedGeneration: g).categories.filter { $0.name == "Synthetic child" && $0.parentID == destination }.count == 2, "Duplicate names were rejected.")
        try life.close()
    }

    @Test func hidingOnlyChangesOneNodeAndPickerKeepsDescendants() throws {
        let f = try CategoryFixture(); defer { f.remove() }
        let life = try f.lifecycle(); let g = try life.open().generation
        let parent = try f.create(life, g, name: "Hide parent")
        let child = try f.create(life, g, name: "Active child", parent: parent)
        let context = try life.categoryEditor(id: parent, expectedGeneration: g)
        var draft = try CategoryDraft.editing(context.original!); draft.active = false
        _ = try life.saveCategory(draft, context: context)
        let editor = try life.editor(transactionID: nil, expectedGeneration: g)
        try categoryCheck(editor.categories.first { $0.id == parent }?.active == false, "Parent was not hidden.")
        try categoryCheck(editor.categories.first { $0.id == child }?.active == true, "Hiding cascaded to a child.")
        try categoryCheck(editor.categories.first { $0.id == child }?.parentID == parent, "Hidden ancestor was lost from picker catalog.")
        let restored = try life.categoryEditor(id: parent, expectedGeneration: g)
        var active = try CategoryDraft.editing(restored.original!); active.active = true
        _ = try life.saveCategory(active, context: restored)
        try life.close()
    }

    @Test func sharedReorderRejectsStaleAndIncompleteLists() throws {
        let f = try CategoryFixture(); defer { f.remove() }
        let life = try f.lifecycle(); let g = try life.open().generation
        let parent = try f.create(life, g, name: "Ordering parent")
        let a = try f.create(life, g, name: "First", parent: parent)
        let b = try f.create(life, g, name: "Hidden", parent: parent, active: false)
        let c = try f.create(life, g, name: "Last", parent: parent)
        let context = try life.categoryReorder(parentID: parent, expectedGeneration: g)
        do { _ = try life.reorderCategories([c,a], context: context); throw CategoryCheckFailure(message: "Partial reorder accepted.") }
        catch CategoryError.changed {}
        do { _ = try life.reorderCategories([a,a,c], context: context); throw CategoryCheckFailure(message: "Duplicate reorder accepted.") }
        catch CategoryError.changed {}
        _ = try life.reorderCategories([c,b,a], context: context)
        let picker = try life.editor(transactionID: nil, expectedGeneration: g)
        try categoryCheck(picker.categories.filter { $0.parentID == parent }.map(\.id) == [c,b,a], "Picker did not use shared order.")
        do { _ = try life.reorderCategories([a,b,c], context: context); throw CategoryCheckFailure(message: "Stale reorder accepted.") }
        catch CategoryError.changed {}
        let current = try life.categoryReorder(parentID: parent, expectedGeneration: g)
        _ = try f.create(life, g, name: "New sibling", parent: parent)
        do { _ = try life.reorderCategories([a,b,c], context: current); throw CategoryCheckFailure(message: "Sibling insertion did not invalidate reorder.") }
        catch CategoryError.changed {}
        try life.close()
    }

    @Test func usageDeletionGuardsAndHistoryRemainCorrect() throws {
        let f = try CategoryFixture(); defer { f.remove() }
        let life = try f.lifecycle(); let g = try life.open().generation
        let parent = try f.create(life, g, name: "Usage parent")
        let child = try f.create(life, g, name: "Usage child", parent: parent)
        let empty = try f.create(life, g, name: "Unused")
        try life.close()
        let db = try SQLiteConnection(url: life.workingURL)
        try db.execute("""
            INSERT INTO accounts(id,name,currency_id,initial_balance,status,account_type,created_at,updated_at)
            VALUES(1,'Synthetic sender',1,'100.00',1,1,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z'),
            (2,'Synthetic receiver',1,'50.00',1,1,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z');
            """)
        try db.run("INSERT INTO transactions(id,transaction_type,account_id,amount,date,category_id,fee,created_at,updated_at) VALUES(1,1,1,'2.50','2026-01-01T12:00:00',?,'0.00','2026-01-01T12:00:00Z','2026-01-01T12:00:00Z')", parameters: [.integer(parent)])
        try db.run("INSERT INTO transactions(id,transaction_type,account_id,to_account_id,amount,to_amount,fee,fee_account_id,date,category_id,created_at,updated_at) VALUES(2,3,1,2,'10.00','9.00','1.00',2,'2026-01-02T12:00:00',?,'2026-01-02T12:00:00Z','2026-01-02T12:00:00Z')", parameters: [.integer(child)])
        let before = try db.rows("SELECT * FROM transactions ORDER BY id").map(\.values)
        try db.run("UPDATE app_settings SET last_created_category_id=?,transfer_category_id=?", parameters: [.integer(empty), .integer(empty)])
        try db.close(); _ = try life.open()
        let month = try CalendarMonth(year: 2026, month: 1)
        let balances = try life.home(expectedGeneration: g, month: month)
        let catalog = try life.categoryCatalog(expectedGeneration: g)
        try categoryCheck(catalog.categories.first { $0.id == parent }?.directCount == 1 && catalog.categories.first { $0.id == parent }?.subtreeCount == 2, "Parent counts double-counted transfers or descendants.")
        let used = try life.categoryEditor(id: child, expectedGeneration: g)
        do { _ = try life.deleteCategory(context: used); throw CategoryCheckFailure(message: "Used category deleted.") }
        catch CategoryError.used {}
        var changed = try CategoryDraft.editing(used.original!); changed.name = "Renamed child"; changed.iconID = 16; changed.active = false
        _ = try life.saveCategory(changed, context: used)
        let original = try life.editor(transactionID: 2, expectedGeneration: g)
        let draft = try TransactionDraft.editing(original.original!)
        _ = try TransactionWrite.validate(draft, context: original, now: Date(), timeZone: .gmt)
        let refreshed = try life.home(expectedGeneration: g, month: month)
        try categoryCheck(refreshed.totalBalance == balances.totalBalance && refreshed.expenses == balances.expenses, "Category edit changed finances.")
        let deletion = try life.categoryEditor(id: empty, expectedGeneration: g)
        let saved = try life.deleteCategory(context: deletion)
        try categoryCheck(saved.settings.lastCreatedCategoryID == nil && saved.settings.transferCategoryID == nil, "Delete did not clear defaults.")
        let unusedParent = try f.create(life, g, name: "Unused parent")
        _ = try f.create(life, g, name: "Hidden child", parent: unusedParent, active: false)
        do { _ = try life.deleteCategory(context: life.categoryEditor(id: unusedParent, expectedGeneration: g)); throw CategoryCheckFailure(message: "Parent with hidden child deleted.") }
        catch CategoryError.children {}
        try life.close()
        let after = try SQLiteConnection(url: life.workingURL, readOnly: true)
        try categoryCheck(try after.rows("SELECT * FROM transactions ORDER BY id").map(\.values) == before, "Category management rewrote transactions.")
        try after.close()
    }

    @Test func staleEditorsAndBackupOrderAreProtected() throws {
        let f = try CategoryFixture(); defer { f.remove() }
        let life = try f.lifecycle(); let g = try life.open().generation
        let parent = try f.create(life, g, name: "Backup parent")
        let a = try f.create(life, g, name: "Backup A", parent: parent)
        let b = try f.create(life, g, name: "Backup B", parent: parent)
        let original = try life.categoryEditor(id: a, expectedGeneration: g)
        var draft = try CategoryDraft.editing(original.original!); draft.favorite = true; draft.iconID = 16
        _ = try life.saveCategory(draft, context: original)
        do { _ = try life.saveCategory(draft, context: original); throw CategoryCheckFailure(message: "Stale editor accepted.") }
        catch CategoryError.changed {}
        _ = try life.reorderCategories([b,a], context: life.categoryReorder(parentID: parent, expectedGeneration: g))
        let backup = try life.dailyBackup(in: f.root.appendingPathComponent("Backups"), now: Date(), timeZone: .gmt, expectedGeneration: g)
        let backupDB = try SQLiteConnection(url: backup, readOnly: true)
        let backedOrder = try CategoryRead.orderedRows(backupDB, parentID: parent).map { try $0.integer("id") }
        try categoryCheck(backedOrder == [b,a], "Daily backup lost category order.")
        _ = try DatabaseValidator(resources: f.resources).validate(backupDB, generation: g)
        try backupDB.close()
        let export = try life.exportSnapshot(expectedGeneration: g)
        let target = try f.lifecycle("restored"); let empty = try target.open()
        let imported = try target.importDatabase(from: export, expectedGeneration: empty.generation)
        let catalog = try target.categoryCatalog(expectedGeneration: imported.generation)
        try categoryCheck(catalog.categories.filter { $0.parentID == parent }.map(\.id) == [b,a], "Backup lost custom order.")
        try categoryCheck(catalog.categories.first { $0.id == a }?.iconID == 16 && catalog.categories.first { $0.id == a }?.favorite == true, "Backup lost category metadata.")
        _ = try life.reset(expectedGeneration: g)
        do { _ = try life.saveCategory(draft, context: original); throw CategoryCheckFailure(message: "Old dataset draft accepted.") }
        catch DatabaseError.staleDataset {}
        try target.close(); try life.close()
    }

    @MainActor @Test func categoryCommitsRefreshDraftsAndRetainedHistory() async throws {
        let f = try CategoryFixture(); defer { f.remove() }
        let deps = AppDependencies(directory: f.root.appendingPathComponent("session"))
        await deps.session.start(store: deps.database, settings: deps.settings)
        let g = deps.session.snapshot!.generation
        let categoryState = CategoryEditorState()
        await categoryState.load(dependencies: deps, generation: g, id: nil, parentID: nil)
        categoryState.draft.name = "Session category"
        try categoryCheck(await categoryState.save(dependencies: deps), "Category state save failed.")
        let id = try await deps.database.categoryCatalog(expectedGeneration: g).categories.first { $0.name == "Session category" }!.id
        let accountContext = try await deps.database.accountEditor(accountID: nil, expectedGeneration: g)
        var accountDraft = AccountDraft(); accountDraft.name = "Synthetic account"
        accountDraft.currencyID = accountContext.catalog.currencies.first { $0.code == "USD" }!.id
        let accountSaved = try await deps.database.saveAccount(accountDraft, context: accountContext, now: Date())
        deps.session.accountsDidCommit(accountSaved, settings: deps.settings)
        let account = try await deps.database.accountCatalog(expectedGeneration: g).first!.id
        let context = try await deps.database.editor(transactionID: nil, expectedGeneration: g)
        var lastID: Int64 = 0
        for index in 1...60 {
            var draft = TransactionDraft(localDate: "2026-01-01T12:00:00")
            draft.accountID = account; draft.categoryID = id; draft.amount = "0"; draft.notes = String(index)
            let saved = try await deps.database.saveTransaction(draft, context: context, now: Date(), timeZone: .gmt)
            deps.session.transactionDidCommit(saved, settings: deps.settings); lastID = saved.id
        }
        let transaction = TransactionEditorState()
        await transaction.load(database: deps.database, generation: g, transactionID: lastID, accountID: nil)
        transaction.draft.amount = "3.25"; transaction.draft.notes = "Unsaved note"
        let entered = transaction.draft
        let original = transaction.context!.original!.values
        let month = try CalendarMonth(year: 2026, month: 1)
        let all = AllHistoryState(); let history = HistoryState()
        await all.ensureLoaded(database: deps.database, session: deps.session, month: month)
        await all.loadMore(database: deps.database, session: deps.session)
        await history.ensureLoaded(accountID: account, database: deps.database, session: deps.session, month: month)
        await history.loadMore(database: deps.database, session: deps.session)
        let editing = CategoryEditorState()
        await editing.load(dependencies: deps, generation: g, id: id, parentID: nil)
        editing.draft.name = "Changed session category"; editing.draft.iconID = 16; editing.draft.active = false
        try categoryCheck(await editing.save(dependencies: deps), "Category edit failed.")
        await transaction.refreshCategories(database: deps.database, generation: g)
        try categoryCheck(transaction.draft == entered && transaction.context!.original!.values == original, "Catalog refresh lost draft values or original transaction.")
        try categoryCheck(transaction.context!.categories.first { $0.id == id }?.active == false, "Editor catalog was not refreshed.")
        await all.ensureLoaded(database: deps.database, session: deps.session, month: month)
        await history.ensureLoaded(accountID: account, database: deps.database, session: deps.session, month: month)
        try categoryCheck(all.rows.count == 60 && history.rows.count == 60, "Category change discarded loaded history range.")
        try categoryCheck(all.rows.first?.transaction.category == "Changed session category" && history.rows.first?.symbol == "cup.and.saucer", "History labels or icons remained stale.")
        try categoryCheck(await transaction.save(dependencies: deps), "Hidden original category could not be retained during edit.")
        var newDraft = TransactionDraft(localDate: "2026-01-01T12:00:00")
        newDraft.accountID = account; newDraft.categoryID = id; newDraft.amount = "1"
        do { _ = try await deps.database.saveTransaction(newDraft, context: context, now: Date(), timeZone: .gmt); throw CategoryCheckFailure(message: "Stale catalog permitted a hidden category on a new transaction.") }
        catch EditorError.category {}
        try await deps.database.close()
    }

    @Test(arguments: ReplacementBoundary.allCases)
    func interruptedV4UpgradePreservesData(_ boundary: ReplacementBoundary) throws {
        let f = try CategoryFixture(); defer { f.remove() }
        let directory = f.root.appendingPathComponent("upgrade")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try SQLiteConnection(url: directory.appendingPathComponent("ledger.sqlite"), create: true)
        try db.execute(f.resources.schema); try db.execute(f.resources.defaults)
        var old = f.resources; old.categoryMigration = ""
        try DatabaseMigrator.upgrade(db, resources: old)
        let before = try db.rows("SELECT id,name,parent_id,is_active,favorite,icon_id FROM categories ORDER BY id").map(\.values)
        try db.close()
        let interrupted = try DatabaseLifecycle(directory: directory, resources: f.resources) {
            if $0 == boundary { throw LifecycleInterruption() }
        }
        do { _ = try interrupted.open(); throw CategoryCheckFailure(message: "Interruption boundary not reached.") }
        catch is LifecycleInterruption {}
        let recovered = try DatabaseLifecycle(directory: directory, resources: f.resources)
        _ = try recovered.open(); try recovered.close()
        let after = try SQLiteConnection(url: directory.appendingPathComponent("ledger.sqlite"), readOnly: true)
        try categoryCheck(try after.rows("SELECT id,name,parent_id,is_active,favorite,icon_id FROM categories ORDER BY id").map(\.values) == before, "Interrupted upgrade changed category metadata.")
        try categoryCheck(try DatabaseMigrator.version(after) == 5, "Interrupted upgrade did not recover to v5.")
        _ = try DatabaseValidator(resources: f.resources).validate(after, generation: UUID())
        try after.close()
        let archives = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Recovery").path)
        try categoryCheck(archives.contains { $0.hasPrefix("Before-v5-") }, "Pre-upgrade snapshot missing.")
    }

}
