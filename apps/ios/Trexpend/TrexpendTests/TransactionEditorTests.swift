import Foundation
import Testing
import SwiftUI
import UIKit
@testable import Trexpend

private struct EditorFixture {
    let root: URL
    let resources: DatabaseResources
    let now = ISO8601DateFormatter().date(from: "2026-10-29T16:00:00Z")!
    let zone = TimeZone(identifier: "America/Toronto")!
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("EditorTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        resources = try .bundled()
        let db = try SQLiteConnection(url: root.appendingPathComponent("ledger.sqlite"), create: true)
        try db.execute(resources.schema); try db.execute(resources.defaults)
        try db.execute("INSERT INTO accounts(id,name,currency_id,initial_balance,status,account_type,created_at,updated_at) VALUES (1,'Synthetic USD',1,'0.00',1,1,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z'),(2,'Synthetic CAD',34,'0.00',1,3,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z'),(3,'Closed USD',1,'0.00',2,1,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')")
        try db.execute("UPDATE app_settings SET default_account_id=1; INSERT INTO exchange_rates(from_currency_id,to_currency_id,rate,updated_at) VALUES (1,34,'1.37','2026-01-01T00:00:00Z')")
        try db.close()
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func life() throws -> DatabaseLifecycle { try DatabaseLifecycle(directory: root, resources: resources) }
    func draft(_ context: TransactionEditorContext, transfer: Bool = false) -> TransactionDraft {
        var draft = TransactionDraft(localDate: "2026-10-29T12:00:00")
        draft.accountID = 1; draft.categoryID = context.categories.first { $0.active }!.id
        draft.amount = "10,00"
        if transfer { draft.type = .transfer; draft.receiverID = 2; draft.receiverAmount = "13.70"; draft.fee = "1.00" }
        return draft
    }
}

@Suite("Transaction editor persistence and state")
struct TransactionEditorTests {
    @Test func createEditAndPreferencesAreAtomic() throws {
        let f = try EditorFixture(); defer { f.remove() }
        let life = try f.life(); let snapshot = try life.open()
        let context = try life.editor(transactionID: nil, expectedGeneration: snapshot.generation)
        let draft = f.draft(context, transfer: true)
        let created = try life.saveTransaction(draft, context: context, now: f.now, timeZone: f.zone)
        #expect(created.snapshot.settings.lastCreatedCategoryID == draft.categoryID)
        #expect(try life.recipient(source: 1, expectedGeneration: snapshot.generation) == 2)
        let edit = try life.editor(transactionID: created.id, expectedGeneration: snapshot.generation)
        var edited = try TransactionDraft.editing(edit.original!)
        edited.notes = "Changed synthetic note"; edited.categoryID = context.categories.last!.id
        let updated = try life.saveTransaction(edited, context: edit, now: f.now.addingTimeInterval(10), timeZone: f.zone)
        #expect(updated.snapshot.settings.lastCreatedCategoryID == draft.categoryID)
        let result = try life.editor(transactionID: created.id, expectedGeneration: snapshot.generation).original!
        #expect(try result.text("created_at") == edit.original!.text("created_at"))
        #expect(try result.optionalText("date_with_offset") == edit.original!.optionalText("date_with_offset"))
        #expect(try result.text("amount") == "10.00")
        #expect(throws: EditorError.self) { try life.saveTransaction(edited, context: edit, now: f.now, timeZone: f.zone) }
        try life.close()
    }

    @Test func feeOwnershipAndTypeCleanup() throws {
        let f = try EditorFixture(); defer { f.remove() }
        let life = try f.life(); let snapshot = try life.open()
        let context = try life.editor(transactionID: nil, expectedGeneration: snapshot.generation)
        var draft = f.draft(context, transfer: true); draft.feeFromReceiver = true
        let created = try life.saveTransaction(draft, context: context, now: f.now, timeZone: f.zone)
        let month = try CalendarMonth(year: 2026, month: 10)
        let home = try life.home(expectedGeneration: snapshot.generation, month: month)
        let rows = home.groups.flatMap(\.accounts)
        #expect(rows.first { $0.id == 1 }?.balance == -10)
        #expect(rows.first { $0.id == 2 }?.balance == Decimal(string: "12.70"))
        #expect(rows.first { $0.id == 2 }?.expenses == 1)
        let edit = try life.editor(transactionID: created.id, expectedGeneration: snapshot.generation)
        var ordinary = try TransactionDraft.editing(edit.original!)
        ordinary.changeType(.income, transferCategory: context.settings.transferCategoryID)
        _ = try life.saveTransaction(ordinary, context: edit, now: f.now, timeZone: f.zone)
        let row = try life.editor(transactionID: created.id, expectedGeneration: snapshot.generation).original!
        #expect(try row.optionalInteger("to_account_id") == nil)
        #expect(try row.optionalInteger("fee_account_id") == nil)
        #expect(try row.text("fee") == "0.00")
        try life.close()
    }

    @Test func validationFailureAndReplacementPreserveData() throws {
        let f = try EditorFixture(); defer { f.remove() }
        let life = try f.life(); let snapshot = try life.open()
        let context = try life.editor(transactionID: nil, expectedGeneration: snapshot.generation)
        var draft = f.draft(context, transfer: true); draft.receiverID = 1
        #expect(throws: EditorError.self) { try life.saveTransaction(draft, context: context, now: f.now, timeZone: f.zone) }
        #expect(try life.current(expectedGeneration: snapshot.generation).transactionCount == 0)
        #expect(try life.current(expectedGeneration: snapshot.generation).settings.lastCreatedCategoryID == nil)
        draft.receiverID = 2
        _ = try life.reset(expectedGeneration: snapshot.generation)
        #expect(throws: DatabaseError.staleDataset) { try life.saveTransaction(draft, context: context, now: f.now, timeZone: f.zone) }
        try life.close()
    }

    @Test func databaseFailureRollsBackRecordAndPreference() throws {
        let f = try EditorFixture(); defer { f.remove() }
        let life = try f.life(); let snapshot = try life.open()
        let context = try life.editor(transactionID: nil, expectedGeneration: snapshot.generation)
        let db = try SQLiteConnection(url: f.root.appendingPathComponent("ledger.sqlite"))
        try db.execute("CREATE TRIGGER fail_preference BEFORE UPDATE OF last_created_category_id ON app_settings BEGIN SELECT RAISE(ABORT,'Synthetic failure'); END")
        #expect(throws: (any Error).self) { try TransactionWrite.save(db, draft: f.draft(context), context: context, now: f.now, timeZone: f.zone) }
        #expect(try db.rows("SELECT count(*) AS n FROM transactions")[0].integer("n") == 0)
        #expect(try db.rows("SELECT last_created_category_id FROM app_settings")[0].optionalInteger("last_created_category_id") == nil)
        try db.close(); try life.close()
    }

    @Test func closedRecordAndUnequalSameCurrencyValuesSurviveEdit() throws {
        let f = try EditorFixture(); defer { f.remove() }
        let life = try f.life(); let snapshot = try life.open()
        let db = try SQLiteConnection(url: f.root.appendingPathComponent("ledger.sqlite"))
        try db.execute("INSERT INTO transactions(transaction_type,account_id,amount,to_account_id,to_amount,date,date_with_offset,category_id,fee,fee_account_id,created_at,updated_at) VALUES (3,3,'10.00',1,'9.00','2026-01-01T12:00:00',NULL,10,'0.00',3,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')")
        try db.close()
        let context = try life.editor(transactionID: 1, expectedGeneration: snapshot.generation)
        var draft = try TransactionDraft.editing(context.original!); draft.notes = "Correction"
        _ = try life.saveTransaction(draft, context: context, now: f.now, timeZone: f.zone)
        let row = try life.editor(transactionID: 1, expectedGeneration: snapshot.generation).original!
        #expect(try row.text("to_amount") == "9.00")
        #expect(try row.optionalText("date_with_offset") == nil)
        try life.close()
    }

    @Test @MainActor func defaultCreationAndManualRecipientBehavior() async throws {
        let f = try EditorFixture(); defer { f.remove() }
        let store = DatabaseStore(directory: f.root, resources: f.resources)
        let snapshot = try await store.open()
        let state = TransactionEditorState()
        await state.load(database: store, generation: snapshot.generation, transactionID: nil, accountID: nil, now: f.now)
        #expect(state.draft.accountID == 1 && !state.isDirty)
        state.changeAmount("1000")
        let category = state.draft.categoryID
        await state.changeType(.income, database: store)
        #expect(state.draft.amount == "1000" && state.draft.categoryID == category)
        await state.changeType(.transfer, database: store)
        #expect(state.draft.receiverID == 2 && state.draft.categoryID == snapshot.settings.transferCategoryID)
        #expect(state.draft.receiverAmount == "1370.00")
        state.chooseReceiver(2); state.draft.receiverAmount = "123"; state.draft.receiverAmountIsManual = true
        await state.changeSource(2, database: store)
        #expect(state.draft.receiverID == 2 && state.draft.amount == "1000" && state.draft.receiverAmount == "123")
        await state.changeType(.expense, database: store)
        #expect(state.draft.accountID == 2 && state.draft.amount == "1000" && state.draft.receiverID == nil)
        try await store.close()
    }

    @Test func roundingZeroAndOccurrenceValidation() throws {
        let f = try EditorFixture(); defer { f.remove() }
        let life = try f.life(); let snapshot = try life.open()
        let context = try life.editor(transactionID: nil, expectedGeneration: snapshot.generation)
        var draft = f.draft(context); draft.amount = "0.004"
        let values = try TransactionWrite.validate(draft, context: context, now: f.now, timeZone: f.zone)
        #expect(values.amount == "0.00" && values.roundedFields.count == 1)
        draft.localDate = "2026-10-30T00:00:00"
        #expect(throws: FinanceError.futureDate) { try TransactionWrite.validate(draft, context: context, now: f.now, timeZone: f.zone) }
        try life.close()
    }
    @Test func bootstrapAndPreferenceSnapshotRoundTrip() throws {
        let f = try EditorFixture(); defer { f.remove() }
        let db = try SQLiteConnection(url: f.root.appendingPathComponent("ledger.sqlite"))
        try db.execute("INSERT INTO accounts(id,name,currency_id,initial_balance,status,account_type,created_at,updated_at) VALUES (4,'Synthetic second cash',34,'0.00',1,3,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')")
        for (id, target, date) in [(1,2,"2026-01-01T00:00:00"),(2,2,"2026-01-02T00:00:00"),(3,4,"2026-01-03T00:00:00"),(4,4,"2026-01-04T00:00:00")] {
            try db.run("INSERT INTO transactions(id,transaction_type,account_id,amount,to_account_id,to_amount,date,category_id,fee,fee_account_id,created_at,updated_at) VALUES (?,3,1,'1.00',?,'1.00',?,10,'0.00',1,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')", parameters: [.integer(Int64(id)),.integer(Int64(target)),.text(date)])
        }
        try db.close()
        let life = try f.life(); let snapshot = try life.open()
        #expect(try life.recipient(source: 1, expectedGeneration: snapshot.generation) == 4)
        let context = try life.editor(transactionID: nil, expectedGeneration: snapshot.generation)
        _ = try life.saveTransaction(f.draft(context, transfer: true), context: context, now: f.now, timeZone: f.zone)
        let exported = try life.exportSnapshot(expectedGeneration: snapshot.generation)
        let restored = try life.importDatabase(from: exported, expectedGeneration: snapshot.generation)
        #expect(try life.recipient(source: 1, expectedGeneration: restored.generation) == 2)
        #expect(restored.settings.lastCreatedCategoryID == context.categories.first { $0.active }?.id)
        let reset = try life.reset(expectedGeneration: restored.generation)
        #expect(reset.settings.lastCreatedCategoryID == nil && reset.transactionCount == 0 && reset.accountCount == 0)
        try life.discardExport(exported); try life.close()
    }

    @Test @MainActor func committedWriteRefreshesLoadedRangesAndRejectsOldCursor() async throws {
        let f = try EditorFixture(); defer { f.remove() }
        let db = try SQLiteConnection(url: f.root.appendingPathComponent("ledger.sqlite"))
        try db.transaction {
            for id in 1...130 {
                try db.run("INSERT INTO transactions(id,transaction_type,account_id,amount,date,category_id,fee,created_at,updated_at) VALUES (?,1,1,'1.00','2026-10-28T12:00:00',10,'0.00','2026-10-28T16:00:00Z','2026-10-28T16:00:00Z')", parameters: [.integer(Int64(id))])
            }
        }
        try db.close()
        let store = DatabaseStore(directory: f.root, resources: f.resources)
        let session = AppSession(); let settings = SettingsStore()
        await session.start(store: store, settings: settings)
        let snapshot = try #require(session.snapshot)
        let month = try CalendarMonth(year: 2026, month: 10)
        let all = AllHistoryState(); let account = HistoryState()
        await all.ensureLoaded(database: store, session: session, month: month)
        await account.ensureLoaded(accountID: 1, database: store, session: session, month: month)
        await all.loadMore(database: store, session: session)
        await account.loadMore(database: store, session: session)
        #expect(all.rows.count == 100 && account.rows.count == 100)
        let oldID = all.rows.last!.id
        let cursor = try #require(all.next)
        let context = try await store.editor(transactionID: nil, expectedGeneration: snapshot.generation)
        let commit = try await store.saveTransaction(f.draft(context), context: context, now: f.now, timeZone: f.zone)
        session.transactionDidCommit(commit, settings: settings)
        await #expect(throws: DatabaseError.staleDataset) {
            try await store.allHistoryPage(expectedGeneration: snapshot.generation, cursor: cursor, expectedRevision: 0)
        }
        await all.ensureLoaded(database: store, session: session, month: month)
        await account.ensureLoaded(accountID: 1, database: store, session: session, month: month)
        #expect(all.loadedRevision == 1 && account.loadedRevision == 1)
        #expect(all.rows.contains { $0.id == oldID } && account.rows.contains { $0.id == oldID })
        #expect(all.content?.summary.expenses == 140)
        #expect(Set(all.rows.map(\.id)).count == all.rows.count)
        try await store.close()
        // Reappearance without another write still reuses the coherent loaded range.
        await all.ensureLoaded(database: store, session: session, month: month)
        #expect(all.error == nil && all.rows.count >= 100)
    }

    @Test @MainActor func failedSaveKeepsDraftAndSuccessfulSaveCannotRepeat() async throws {
        let f = try EditorFixture(); defer { f.remove() }
        let dependencies = AppDependencies(directory: f.root)
        await dependencies.session.start(store: dependencies.database, settings: dependencies.settings)
        let snapshot = try #require(dependencies.session.snapshot)
        let state = TransactionEditorState()
        await state.load(database: dependencies.database, generation: snapshot.generation, transactionID: nil, accountID: nil, now: f.now)
        state.changeAmount("12.34"); state.draft.categoryID = nil
        #expect(await state.save(dependencies: dependencies) == false)
        #expect(state.draft.amount == "12.34" && state.isDirty && state.error != nil)
        state.draft.categoryID = state.context!.categories.first { $0.active }!.id
        #expect(await state.save(dependencies: dependencies))
        #expect(await state.save(dependencies: dependencies) == false)
        #expect(dependencies.session.snapshot?.transactionCount == 1)
        #expect(dependencies.session.transactionRevision == 1)
        try await dependencies.database.close()
    }

    @Test @MainActor func renderIsolatedSmallScreenEditor() async throws {
        let f = try EditorFixture(); defer { f.remove() }
        let dependencies = AppDependencies(directory: f.root)
        await dependencies.session.start(store: dependencies.database, settings: dependencies.settings)
        let snapshot = try #require(dependencies.session.snapshot)
        let context = try await dependencies.database.editor(transactionID: nil, expectedGeneration: snapshot.generation)
        var draft = f.draft(context, transfer: true)
        draft.notes = "Synthetic note for a compact-screen editor layout check."
        let commit = try await dependencies.database.saveTransaction(draft, context: context, now: f.now, timeZone: f.zone)
        dependencies.session.transactionDidCommit(commit, settings: dependencies.settings)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; oldWindow?.makeKeyAndVisible() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EditorVisualProof")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for largeText in [false, true] {
            let state = TransactionEditorState()
            await state.load(database: dependencies.database, generation: snapshot.generation, transactionID: commit.id, accountID: nil)
            let view = TransactionEditorView(dependencies: dependencies, generation: snapshot.generation, transactionID: commit.id, state: state)
                .environment(\.dynamicTypeSize, largeText ? .accessibility3 : .large)
            let host = UIHostingController(rootView: view)
            window.rootViewController = host; window.overrideUserInterfaceStyle = .light
            window.makeKeyAndVisible()
            host.view.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            let image = UIGraphicsImageRenderer(size: CGSize(width: 375, height: 667)).image { _ in
                host.view.drawHierarchy(in: CGRect(x: 0, y: 0, width: 375, height: 667), afterScreenUpdates: true)
            }
            let data = try #require(image.pngData())
            try data.write(to: folder.appendingPathComponent(largeText ? "large-text.png" : "normal.png"))
            #expect(!state.isDirty)
        }
        try await dependencies.database.close()
    }

    @Test func v2UpgradeDoesNotChooseDuplicateTransferCategory() throws {
        let f = try EditorFixture(); defer { f.remove() }
        let db = try SQLiteConnection(url: f.root.appendingPathComponent("ledger.sqlite"))
        try db.execute(f.resources.migration)
        try db.execute("PRAGMA user_version=2; INSERT INTO categories(id,name,is_active) VALUES (9999,'Transfer',1)")
        let before = try db.rows("SELECT id,name,parent_id,is_active,favorite FROM categories").map(\.values)
        try db.close()
        let life = try f.life(); let snapshot = try life.open()
        #expect(snapshot.settings.transferCategoryID == nil)
        let after = try SQLiteConnection(url: f.root.appendingPathComponent("ledger.sqlite"), readOnly: true)
        #expect(try DatabaseMigrator.version(after) == 4)
        #expect(try after.rows("SELECT id,name,parent_id,is_active,favorite FROM categories").map(\.values) == before)
        try after.close(); try life.close()
    }

    @Test func movingDateAndAccountRefreshesOriginalAndNewSummaries() throws {
        let f = try EditorFixture(); defer { f.remove() }
        let life = try f.life(); let snapshot = try life.open()
        let context = try life.editor(transactionID: nil, expectedGeneration: snapshot.generation)
        let created = try life.saveTransaction(f.draft(context), context: context, now: f.now, timeZone: f.zone)
        let edit = try life.editor(transactionID: created.id, expectedGeneration: snapshot.generation)
        var draft = try TransactionDraft.editing(edit.original!)
        draft.accountID = 2; draft.localDate = "2026-09-01T00:00:00"
        _ = try life.saveTransaction(draft, context: edit, now: f.now, timeZone: f.zone)
        let home = try life.home(expectedGeneration: snapshot.generation, month: CalendarMonth(year: 2026, month: 10))
        let rows = home.groups.flatMap(\.accounts)
        #expect(rows.first { $0.id == 1 }?.balance == 0)
        #expect(rows.first { $0.id == 2 }?.balance == -10)
        #expect(home.expenses == 0)
        let result = try life.editor(transactionID: created.id, expectedGeneration: snapshot.generation).original!
        #expect(try result.optionalText("date_with_offset") == "2026-09-01T00:00:00-04:00")
        #expect(try result.text("created_at") == edit.original!.text("created_at"))
        try life.close()
    }

    @Test @MainActor func defaultAccountSelectionValidatesAndOnlyAffectsNewDrafts() async throws {
        let f = try EditorFixture(); defer { f.remove() }
        let deps = AppDependencies(directory: f.root)
        await deps.session.start(store: deps.database, settings: deps.settings)
        let generation = try #require(deps.session.snapshot?.generation)
        let settings = SettingsState(dependencies: deps)
        await settings.loadAccounts()
        #expect(await settings.setDefaultAccount(2))
        let draft = TransactionEditorState()
        await draft.load(database: deps.database, generation: generation, transactionID: nil, accountID: nil)
        #expect(draft.draft.accountID == 2)
        #expect(await settings.setDefaultAccount(1))
        #expect(draft.draft.accountID == 2)
        let accountDraft = TransactionEditorState()
        await accountDraft.load(database: deps.database, generation: generation, transactionID: nil, accountID: 2)
        #expect(accountDraft.draft.accountID == 2)
        #expect(await settings.setDefaultAccount(3) == false)
        #expect(deps.settings.values?.defaultAccountID == 1)
        await #expect(throws: FinanceError.missingAccount) {
            try await deps.database.setDefaultAccount(999, expectedGeneration: generation)
        }
        await #expect(throws: DatabaseError.staleDataset) {
            try await deps.database.setDefaultAccount(2, expectedGeneration: UUID())
        }
        #expect(await settings.setDefaultAccount(nil))
        try await deps.database.close()
        let reopened = try await deps.database.open()
        #expect(reopened.settings.defaultAccountID == nil)
        try await deps.database.close()
    }

    @Test(arguments: [false, true])
    func deletingTransferRemovesPrincipalAndFeeButPreservesPreferences(_ receiverFee: Bool) throws {
        let f = try EditorFixture(); defer { f.remove() }
        let life = try f.life(); let snapshot = try life.open()
        let context = try life.editor(transactionID: nil, expectedGeneration: snapshot.generation)
        var draft = f.draft(context, transfer: true); draft.feeFromReceiver = receiverFee
        let created = try life.saveTransaction(draft, context: context, now: f.now, timeZone: f.zone)
        let target = try life.deletionTarget(transactionID: created.id, expectedGeneration: snapshot.generation)
        let deleted = try life.deleteTransaction(target)
        #expect(deleted.snapshot.transactionCount == 0 && deleted.snapshot.accountCount == snapshot.accountCount)
        #expect(deleted.snapshot.settings.lastCreatedCategoryID == draft.categoryID)
        #expect(try life.recipient(source: 1, expectedGeneration: snapshot.generation) == 2)
        let home = try life.home(expectedGeneration: snapshot.generation, month: CalendarMonth(year: 2026, month: 10))
        #expect(home.groups.flatMap(\.accounts).allSatisfy { $0.balance == 0 })
        #expect(home.expenses == 0)
        #expect(throws: EditorError.self) { try life.deleteTransaction(target) }
        try life.close()
    }

    @Test func deleteRejectsChangedRecordAndReplacedDataset() throws {
        let f = try EditorFixture(); defer { f.remove() }
        let life = try f.life(); let snapshot = try life.open()
        let context = try life.editor(transactionID: nil, expectedGeneration: snapshot.generation)
        var draft = f.draft(context)
        let created = try life.saveTransaction(draft, context: context, now: f.now, timeZone: f.zone)
        let target = try life.deletionTarget(transactionID: created.id, expectedGeneration: snapshot.generation)
        let edit = try life.editor(transactionID: created.id, expectedGeneration: snapshot.generation)
        draft.notes = "Synthetic updated record"
        _ = try life.saveTransaction(draft, context: edit, now: f.now.addingTimeInterval(1), timeZone: f.zone)
        #expect(throws: EditorError.self) { try life.deleteTransaction(target) }
        #expect(try life.current(expectedGeneration: snapshot.generation).transactionCount == 1)
        _ = try life.reset(expectedGeneration: snapshot.generation)
        #expect(throws: DatabaseError.staleDataset) { try life.deleteTransaction(target) }
        try life.close()
    }

    @Test @MainActor func deleteConfirmationCancelAndFailedWriteKeepTheRecord() async throws {
        let f = try EditorFixture(); defer { f.remove() }
        let store = DatabaseStore(directory: f.root, resources: f.resources)
        let session = AppSession(); let settings = SettingsStore()
        await session.start(store: store, settings: settings)
        let snapshot = try #require(session.snapshot)
        let context = try await store.editor(transactionID: nil, expectedGeneration: snapshot.generation)
        let created = try await store.saveTransaction(f.draft(context), context: context, now: f.now, timeZone: f.zone)
        session.transactionDidCommit(created, settings: settings)
        let target = try await store.deletionTarget(transactionID: created.id, expectedGeneration: snapshot.generation)
        let deletion = TransactionDeletionState()
        deletion.request(target); deletion.cancel()
        #expect(try await store.current(expectedGeneration: snapshot.generation).transactionCount == 1)
        deletion.request(target)
        try await store.close()
        await deletion.confirm(database: store, session: session, settings: settings)
        #expect(deletion.error != nil && !deletion.didDelete && session.transactionRevision == 1)
        let reopened = try await store.open()
        #expect(reopened.transactionCount == 1)
        try await store.close()
    }

}
