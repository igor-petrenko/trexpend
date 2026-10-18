import Foundation
import Testing
@testable import Trexpend

private struct StorageFixture {
    let root: URL
    let resources: DatabaseResources

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("StorageTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        resources = try .bundled()
    }

    func remove() throws { try FileManager.default.removeItem(at: root) }
    func lifecycle(_ name: String = "working", fault: (@Sendable (ReplacementBoundary) throws -> Void)? = nil) throws -> DatabaseLifecycle {
        try DatabaseLifecycle(directory: root.appendingPathComponent(name), resources: resources, fault: fault)
    }

    func populatedSource() throws -> URL {
        let lifecycle = try lifecycle("source")
        let snapshot = try lifecycle.open()
        try lifecycle.close()
        let db = try SQLiteConnection(url: lifecycle.workingURL)
        try db.run("INSERT INTO accounts(id,name,currency_id,initial_balance,status,account_type,created_at,updated_at) VALUES (1,?,?,'10.00',1,1,?,?)", parameters: [.text("Synthetic account"), .integer(snapshot.settings.displayCurrencyID), .text("2026-01-01T00:00:00Z"), .text("2026-01-01T00:00:00Z")])
        try db.run("UPDATE app_settings SET user_name=?, default_account_id=1", parameters: [.text("Synthetic user")])
        let category = try db.rows("SELECT id FROM categories ORDER BY id LIMIT 1")[0].integer("id")
        try db.run("INSERT INTO transactions(id,transaction_type,account_id,amount,date,category_id,notes,fee,created_at,updated_at) VALUES (1,1,1,'2.50','2026-01-01T12:00:00',?,?,'0.00','2026-01-01T12:00:00.123456Z','2026-01-01T12:00:00.123456Z')", parameters: [.integer(category), .text("Synthetic note\0 preserved")])
        try db.close()
        return lifecycle.workingURL
    }
}

@Suite("Database lifecycle")
struct DatabaseLifecycleTests {
    @Test
    func bundledResourcesAndFreshDefaults() throws {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool == true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool == true)
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle()
        let snapshot = try lifecycle.open()
        #expect(snapshot.settings.displayCurrencyCode == "USD")
        #expect(snapshot.settings.defaultAccountID == nil)
        #expect(snapshot.settings.userName == nil)
        #expect(snapshot.accountCount == 0 && snapshot.transactionCount == 0)
        try lifecycle.close()
        let db = try SQLiteConnection(url: lifecycle.workingURL, readOnly: true)
        #expect(try db.rows("SELECT count(*) AS n FROM categories")[0].integer("n") == 64)
        #expect(try db.rows("SELECT count(*) AS n FROM currencies")[0].integer("n") == 168)
        #expect(try db.rows("SELECT count(*) AS n FROM exchange_rates")[0].integer("n") == 0)
        try db.close()
    }

    @Test
    func reopenDoesNotReseed() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle()
        _ = try lifecycle.open()
        try lifecycle.close()
        let db = try SQLiteConnection(url: lifecycle.workingURL)
        try db.run("UPDATE categories SET name=? WHERE id=1", parameters: [.text("Synthetic renamed category")])
        try db.run("UPDATE app_settings SET display_currency_id=(SELECT id FROM currencies WHERE code='CAD')")
        try db.close()
        let reopened = try fixture.lifecycle()
        #expect(try reopened.open().settings.displayCurrencyCode == "CAD")
        try reopened.close()
        let read = try SQLiteConnection(url: lifecycle.workingURL, readOnly: true)
        #expect(try read.rows("SELECT name FROM categories WHERE id=1")[0].text("name") == "Synthetic renamed category")
        try read.close()
    }

    @Test
    func importPreservesSourceAndPortableData() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let originalBytes = try Data(contentsOf: source)
        let lifecycle = try fixture.lifecycle()
        let before = try lifecycle.open()
        let after = try lifecycle.importDatabase(from: source, expectedGeneration: before.generation)
        #expect(after.generation != before.generation)
        #expect(after.accountCount == 1 && after.transactionCount == 1)
        #expect(after.settings.userName == "Synthetic user")
        #expect(after.settings.defaultAccountID == 1)
        #expect(try Data(contentsOf: source) == originalBytes)
        #expect(throws: DatabaseError.staleDataset) { try lifecycle.current(expectedGeneration: before.generation) }
        try lifecycle.close()
        let db = try SQLiteConnection(url: lifecycle.workingURL, readOnly: true)
        #expect(try db.rows("SELECT notes FROM transactions")[0].text("notes") == "Synthetic note\0 preserved")
        #expect(try db.rows("SELECT updated_at FROM transactions")[0].text("updated_at") == "2026-01-01T12:00:00.123456Z")
        try db.close()
    }

    @Test(arguments: ["foreign", "version", "schema", "scale", "cycle", "settings", "timestamp", "fk"])
    func invalidCandidatePreservesCurrent(_ kind: String) throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let db = try SQLiteConnection(url: source)
        switch kind {
        case "foreign": try db.execute("PRAGMA application_id=0")
        case "version": try db.execute("PRAGMA user_version=2")
        case "schema": try db.execute("CREATE TABLE unexpected(id INTEGER)")
        case "scale": try db.run("UPDATE transactions SET amount='2.501'")
        case "cycle": try db.run("UPDATE categories SET parent_id=id WHERE id=1")
        case "settings": try db.run("DELETE FROM app_settings")
        case "timestamp": try db.run("UPDATE transactions SET date='2026-02-30T00:00:00'")
        default:
            try db.execute("PRAGMA foreign_keys=OFF")
            try db.run("UPDATE transactions SET account_id=999")
        }
        try db.close()
        let lifecycle = try fixture.lifecycle()
        let before = try lifecycle.open()
        let bytes = try Data(contentsOf: lifecycle.workingURL)
        #expect(throws: (any Error).self) { try lifecycle.importDatabase(from: source, expectedGeneration: before.generation) }
        #expect(try lifecycle.current(expectedGeneration: before.generation) == before)
        #expect(try Data(contentsOf: lifecycle.workingURL) == bytes)
        try lifecycle.close()
    }

    @Test(arguments: ReplacementBoundary.allCases)
    func restartRecoveryAtEveryBoundary(_ boundary: ReplacementBoundary) throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let lifecycle = try fixture.lifecycle(fault: { point in if point == boundary { throw LifecycleInterruption() } })
        let before = try lifecycle.open()
        #expect(throws: LifecycleInterruption.self) { try lifecycle.importDatabase(from: source, expectedGeneration: before.generation) }
        let restarted = try fixture.lifecycle()
        let recovered = try restarted.open()
        let committed = boundary == .commitWritten || boundary == .cleanupStarted
        #expect(recovered.accountCount == (committed ? 1 : 0))
        #expect(recovered.settings.userName == (committed ? "Synthetic user" : nil))
        try restarted.close()
        // Recovery and cleanup must be idempotent across another process restart.
        let again = try fixture.lifecycle()
        #expect(try again.open().accountCount == recovered.accountCount)
        try again.close()
    }

    @Test
    func ordinaryFailureRollsBackImmediately() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let lifecycle = try fixture.lifecycle(fault: { point in if point == .newOpened { throw DatabaseError.fileAccess } })
        let before = try lifecycle.open()
        #expect(throws: DatabaseError.fileAccess) { try lifecycle.importDatabase(from: source, expectedGeneration: before.generation) }
        #expect(try lifecycle.current(expectedGeneration: before.generation) == before)
        try lifecycle.close()
    }

    @Test
    func corruptExistingDataIsNeverRecreated() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let folder = fixture.root.appendingPathComponent("working")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("ledger.sqlite")
        let original = Data("Synthetic non-database".utf8)
        try original.write(to: url)
        let lifecycle = try fixture.lifecycle()
        #expect(throws: (any Error).self) { try lifecycle.open() }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test
    func schemaMissingSeedFailsWithoutPublishing() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let lifecycle = try DatabaseLifecycle(directory: fixture.root.appendingPathComponent("invalid"), resources: DatabaseResources(schema: fixture.resources.schema, defaults: ""))
        #expect(throws: (any Error).self) { try lifecycle.open() }
        #expect(!FileManager.default.fileExists(atPath: lifecycle.workingURL.path))
    }

    @Test
    func unexpectedRecoveryArtifactsFailClosed() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let folder = fixture.root.appendingPathComponent("working")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("Synthetic recovery artifact".utf8).write(to: folder.appendingPathComponent("previous.sqlite"))
        #expect(throws: DatabaseError.recoveryRequired) { try fixture.lifecycle().open() }
    }

    @Test
    func sidecarInputIsRejected() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        try Data().write(to: URL(fileURLWithPath: source.path + "-wal"))
        let lifecycle = try fixture.lifecycle()
        let before = try lifecycle.open()
        #expect(throws: DatabaseError.invalidDatabase) { try lifecycle.importDatabase(from: source, expectedGeneration: before.generation) }
        #expect(try lifecycle.current(expectedGeneration: before.generation).accountCount == 0)
        try lifecycle.close()
    }

    @Test
    func asyncFacadeSerializesOperations() async throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let store = DatabaseStore(directory: fixture.root.appendingPathComponent("async"), resources: fixture.resources)
        let initial = try await store.open()
        async let first = store.current(expectedGeneration: initial.generation)
        async let second = store.current(expectedGeneration: initial.generation)
        let values = try await (first, second)
        #expect(values.0 == initial && values.1 == initial)
        try await store.close()
    }
}

@Suite("Database export and reset")
struct DatabaseExportResetTests {
    @Test
    func lockedBackupFailsWithoutChangingLedgerAndCanRetry() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle()
        let initial = try lifecycle.open()
        let blocker = try SQLiteConnection(url: lifecycle.workingURL)
        try blocker.execute("BEGIN EXCLUSIVE;")
        #expect(throws: DatabaseError.sqlite) { try lifecycle.exportSnapshot(expectedGeneration: initial.generation) }
        try blocker.execute("ROLLBACK;")
        try blocker.close()
        let exports = lifecycle.exportsDirectory
        #expect(try FileManager.default.contentsOfDirectory(atPath: exports.path).isEmpty)
        #expect(try lifecycle.current(expectedGeneration: initial.generation) == initial)
        let exported = try lifecycle.exportSnapshot(expectedGeneration: initial.generation)
        try lifecycle.discardExport(exported)
        try lifecycle.close()
    }

    @Test
    func unavailableImportSourcePreservesDataset() async throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let store = DatabaseStore(directory: fixture.root.appendingPathComponent("unavailable"), resources: fixture.resources)
        let initial = try await store.open()
        let coordinator = DatabaseFileCoordinator(store: store)
        do {
            _ = try await coordinator.importDatabase(from: fixture.root.appendingPathComponent("missing.sqlite"), expectedGeneration: initial.generation)
            Issue.record("An unavailable source must fail.")
        } catch {}
        #expect(try await store.current(expectedGeneration: initial.generation) == initial)
        try await store.close()
    }

    @Test
    func snapshotReopensAndRestoresIndependently() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let lifecycle = try fixture.lifecycle()
        let initial = try lifecycle.open()
        let imported = try lifecycle.importDatabase(from: source, expectedGeneration: initial.generation)
        let exported = try lifecycle.exportSnapshot(expectedGeneration: imported.generation)
        try DatabaseLifecycle.requireStandalone(exported)
        let bytes = try Data(contentsOf: exported)
        let reset = try lifecycle.reset(expectedGeneration: imported.generation)
        #expect(reset.accountCount == 0 && reset.transactionCount == 0)
        #expect(reset.settings.displayCurrencyCode == "USD" && reset.settings.userName == nil && reset.settings.defaultAccountID == nil)
        #expect(try Data(contentsOf: exported) == bytes)
        let restored = try lifecycle.importDatabase(from: exported, expectedGeneration: reset.generation)
        #expect(restored.accountCount == 1 && restored.transactionCount == 1)
        #expect(restored.settings == imported.settings)
        #expect(throws: DatabaseError.staleDataset) { try lifecycle.reset(expectedGeneration: imported.generation) }
        try lifecycle.discardExport(exported)
        #expect(!FileManager.default.fileExists(atPath: exported.path))
        try lifecycle.close()
    }

    @Test(arguments: ReplacementBoundary.allCases)
    func resetRecoveryAtEveryBoundary(_ boundary: ReplacementBoundary) throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let initial = try fixture.lifecycle()
        let empty = try initial.open()
        _ = try initial.importDatabase(from: source, expectedGeneration: empty.generation)
        try initial.close()
        let interrupted = try fixture.lifecycle(fault: { point in if point == boundary { throw LifecycleInterruption() } })
        let before = try interrupted.open()
        #expect(throws: LifecycleInterruption.self) { try interrupted.reset(expectedGeneration: before.generation) }
        let restarted = try fixture.lifecycle()
        let after = try restarted.open()
        let committed = boundary == .commitWritten || boundary == .cleanupStarted
        #expect(after.accountCount == (committed ? 0 : 1))
        #expect(after.settings.userName == (committed ? nil : "Synthetic user"))
        try restarted.close()
    }

    @Test
    func resetRestoresCategoryCatalogWithoutReseedingImports() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let sourceDB = try SQLiteConnection(url: source)
        try sourceDB.run("UPDATE categories SET name=? WHERE id=1", parameters: [.text("Synthetic custom category")])
        try sourceDB.run("UPDATE app_settings SET display_currency_id=(SELECT id FROM currencies WHERE code='CAD')")
        try sourceDB.close()
        let lifecycle = try fixture.lifecycle()
        let initial = try lifecycle.open()
        let imported = try lifecycle.importDatabase(from: source, expectedGeneration: initial.generation)
        #expect(imported.settings.displayCurrencyCode == "CAD")
        let before = try SQLiteConnection(url: lifecycle.workingURL, readOnly: true)
        #expect(try before.rows("SELECT name FROM categories WHERE id=1")[0].text("name") == "Synthetic custom category")
        try before.close()
        let reset = try lifecycle.reset(expectedGeneration: imported.generation)
        #expect(reset.settings.displayCurrencyCode == "USD")
        let after = try SQLiteConnection(url: lifecycle.workingURL, readOnly: true)
        #expect(try after.rows("SELECT name FROM categories WHERE id=1")[0].text("name") == "Bills")
        #expect(try after.rows("SELECT count(*) AS n FROM categories")[0].integer("n") == 64)
        try after.close()
        try lifecycle.close()
    }

    @Test
    func cleanupNeverDeletesArbitraryFiles() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let lifecycle = try fixture.lifecycle()
        _ = try lifecycle.open()
        #expect(throws: DatabaseError.fileAccess) { try lifecycle.discardExport(source) }
        #expect(FileManager.default.fileExists(atPath: source.path))
        try lifecycle.close()
    }
}

@Suite("Storage failure boundaries")
struct StorageFailureBoundaryTests {
    @Test
    func validationBudgetInterruptsExpensiveSQL() throws {
        let db = try SQLiteConnection(url: nil, create: true)
        #expect(throws: DatabaseError.validationTimedOut) {
            try db.withValidationBudget(seconds: 0.001) {
                try db.rows("WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<10000000) SELECT max(x) FROM n")
            }
        }
        #expect(try db.rows("SELECT 1 AS value")[0].integer("value") == 1)
        try db.close()
    }

    @Test
    func committedCleanupFailureIsNotReportedAsRollback() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let lifecycle = try fixture.lifecycle(fault: { point in if point == .cleanupStarted { throw DatabaseError.fileAccess } })
        let initial = try lifecycle.open()
        let imported = try lifecycle.importDatabase(from: source, expectedGeneration: initial.generation)
        #expect(imported.accountCount == 1)
        try lifecycle.close()
        let reopened = try fixture.lifecycle()
        #expect(try reopened.open().accountCount == 1)
        try reopened.close()
    }

    @Test
    func restartDuringRollbackCleanupKeepsRestoredDataset() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let lifecycle = try fixture.lifecycle(fault: { point in if point == .candidateMoved { throw LifecycleInterruption() } })
        let initial = try lifecycle.open()
        #expect(throws: LifecycleInterruption.self) { try lifecycle.importDatabase(from: source, expectedGeneration: initial.generation) }
        let directory = lifecycle.workingURL.deletingLastPathComponent()
        try FileManager.default.removeItem(at: lifecycle.workingURL)
        try FileManager.default.copyItem(at: directory.appendingPathComponent("previous.sqlite"), to: lifecycle.workingURL)
        try Data(#"{"version":1,"phase":"rolledBack"}"#.utf8).write(to: directory.appendingPathComponent("replacement.json"))
        let restarted = try fixture.lifecycle()
        #expect(try restarted.open().accountCount == 0)
        try restarted.close()
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("previous.sqlite").path))
    }

    @Test
    func coordinatedSourceImportPreservesSource() async throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let bytes = try Data(contentsOf: source)
        let store = DatabaseStore(directory: fixture.root.appendingPathComponent("coordinated"), resources: fixture.resources)
        let snapshot = try await store.open()
        let coordinator = DatabaseFileCoordinator(store: store)
        let imported = try await coordinator.importDatabase(from: source, expectedGeneration: snapshot.generation)
        #expect(imported.accountCount == 1)
        #expect(try Data(contentsOf: source) == bytes)
        try await store.close()
    }
}

@Suite("Export presentation completion")
@MainActor
struct ExportPresentationTests {
    @Test(arguments: [true, false])
    func dismissalAndDelegateMayArriveInEitherOrder(_ dismissalFirst: Bool) async throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let dependencies = AppDependencies(directory: fixture.root.appendingPathComponent("presentation"))
        await dependencies.start()
        let state = SettingsState(dependencies: dependencies)
        await state.exportCopy()
        #expect(dependencies.session.isBusy)
        #expect(state.exportRequest != nil)
        if dismissalFirst {
            state.exporterDismissed()
            #expect(dependencies.session.isBusy)
            state.finishExport(saved: false)
        } else {
            state.finishExport(saved: false)
            #expect(dependencies.session.isBusy)
            state.exporterDismissed()
        }
        for _ in 0..<100 where dependencies.session.isBusy {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!dependencies.session.isBusy)
        #expect(state.exportRequest == nil)
        #expect(state.message == nil)
        try await dependencies.database.close()
    }
}

@Suite("Database reliability regressions")
struct DatabaseReliabilityTests {
    private var corruptBytes: Data { Data("Synthetic corrupt ledger".utf8) }

    @Test
    func largeWorkingHistoryOpensWithoutFullAudit() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let db = try SQLiteConnection(url: source)
        try db.execute("INSERT INTO transactions(id,transaction_type,account_id,amount,date,category_id,fee,created_at,updated_at) WITH RECURSIVE n(x) AS (VALUES(2) UNION ALL SELECT x+1 FROM n WHERE x<100000) SELECT x,1,1,'1.00','2026-01-01T12:00:00',1,'0.00','2026-01-01T12:00:00Z','2026-01-01T12:00:00Z' FROM n")
        try db.close()
        let lifecycle = try fixture.lifecycle("source")
        let snapshot = try lifecycle.open()
        #expect(snapshot.transactionCount == 100000)
        #expect(try lifecycle.current(expectedGeneration: snapshot.generation) == snapshot)
        try lifecycle.close()
    }

    @Test(arguments: [true, false])
    func unavailableDatasetCanImportOrReset(_ imports: Bool) throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let source = try fixture.populatedSource()
        let lifecycle = try fixture.lifecycle()
        try FileManager.default.createDirectory(at: lifecycle.directory, withIntermediateDirectories: true)
        try corruptBytes.write(to: lifecycle.workingURL)
        #expect(throws: (any Error).self) { try lifecycle.open() }
        let restored = try imports ? lifecycle.importDatabase(from: source, expectedGeneration: nil) : lifecycle.reset(expectedGeneration: nil)
        #expect(restored.accountCount == (imports ? 1 : 0))
        let archives = try FileManager.default.contentsOfDirectory(at: lifecycle.directory.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        #expect(try Data(contentsOf: archives[0].appendingPathComponent("ledger.sqlite")) == corruptBytes)
        #expect(throws: DatabaseError.staleDataset) { try lifecycle.reset(expectedGeneration: nil) }
        try lifecycle.close()
        #expect(try fixture.lifecycle().open().accountCount == restored.accountCount)
    }

    @Test(arguments: ReplacementBoundary.allCases)
    func interruptedUnavailableReplacementPreservesOldData(_ boundary: ReplacementBoundary) throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle(fault: { if $0 == boundary { throw LifecycleInterruption() } })
        try FileManager.default.createDirectory(at: lifecycle.directory, withIntermediateDirectories: true)
        try corruptBytes.write(to: lifecycle.workingURL)
        #expect(throws: LifecycleInterruption.self) { try lifecycle.reset(expectedGeneration: nil) }
        let restarted = try fixture.lifecycle()
        if boundary == .commitWritten || boundary == .cleanupStarted {
            #expect(try restarted.open().accountCount == 0)
            try restarted.close()
        } else {
            #expect(throws: (any Error).self) { try restarted.open() }
            #expect(try Data(contentsOf: restarted.workingURL) == corruptBytes)
            #expect(try restarted.reset(expectedGeneration: nil).accountCount == 0)
            try restarted.close()
        }
        let archives = try FileManager.default.contentsOfDirectory(at: lifecycle.directory.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        #expect(try Data(contentsOf: archives[0].appendingPathComponent("ledger.sqlite")) == corruptBytes)
    }

    @Test
    func invalidRecoveryImportKeepsUnreadableFileUntouched() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle()
        try FileManager.default.createDirectory(at: lifecycle.directory, withIntermediateDirectories: true)
        try corruptBytes.write(to: lifecycle.workingURL)
        let invalid = fixture.root.appendingPathComponent("invalid.sqlite")
        try corruptBytes.write(to: invalid)
        #expect(throws: (any Error).self) { try lifecycle.importDatabase(from: invalid, expectedGeneration: nil) }
        #expect(try Data(contentsOf: lifecycle.workingURL) == corruptBytes)
    }

    @Test
    func resetWorksWhenOnlyBrokenRecoveryArtifactsExist() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle()
        try FileManager.default.createDirectory(at: lifecycle.directory, withIntermediateDirectories: true)
        try corruptBytes.write(to: lifecycle.directory.appendingPathComponent("replacement.json"))
        #expect(throws: (any Error).self) { try lifecycle.open() }
        #expect(try lifecycle.reset(expectedGeneration: nil).accountCount == 0)
        try lifecycle.close()
    }

    @Test
    func startupCleansAbandonedExportsButNotActiveOnes() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle()
        let before = try lifecycle.open()
        let abandoned = try lifecycle.exportSnapshot(expectedGeneration: before.generation)
        _ = try lifecycle.open()
        #expect(FileManager.default.fileExists(atPath: abandoned.path))
        try lifecycle.close()
        let legacy = lifecycle.directory.appendingPathComponent("Exports")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try corruptBytes.write(to: legacy.appendingPathComponent("old.sqlite"))
        let restarted = try fixture.lifecycle()
        _ = try restarted.open()
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        try restarted.close()
    }

    @Test
    func dailyBackupsArePortableAndRetentionIsScoped() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle()
        let snapshot = try lifecycle.open()
        let folder = fixture.root.appendingPathComponent("visible-backups")
        let old = Date(timeIntervalSince1970: 0)
        let first = try lifecycle.dailyBackup(in: folder, now: old, timeZone: .gmt, expectedGeneration: snapshot.generation)
        let again = try lifecycle.dailyBackup(in: folder, now: old, timeZone: .gmt, expectedGeneration: snapshot.generation)
        #expect(first == again)
        let manual = folder.appendingPathComponent("My-own-backup.sqlite")
        try corruptBytes.write(to: manual)
        let now = old.addingTimeInterval(31 * 86400)
        let latest = try lifecycle.dailyBackup(in: folder, now: now, timeZone: .gmt, expectedGeneration: snapshot.generation)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: manual.path))
        let db = try SQLiteConnection(url: latest, readOnly: true)
        #expect(try DatabaseValidator(resources: fixture.resources).validate(db, generation: UUID()).accountCount == 0)
        try db.close()
        _ = try lifecycle.reset(expectedGeneration: snapshot.generation)
        #expect(FileManager.default.fileExists(atPath: latest.path))
        try lifecycle.close()
    }

    @Test
    func backupFailurePreservesLedgerAndAllowsRetry() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle()
        let snapshot = try lifecycle.open()
        let folder = fixture.root.appendingPathComponent("unwritable")
        try corruptBytes.write(to: folder)
        #expect(throws: (any Error).self) { try lifecycle.dailyBackup(in: folder, now: Date(), timeZone: .gmt, expectedGeneration: snapshot.generation) }
        #expect(try lifecycle.current(expectedGeneration: snapshot.generation) == snapshot)
        try FileManager.default.removeItem(at: folder)
        _ = try lifecycle.dailyBackup(in: folder, now: Date(), timeZone: .gmt, expectedGeneration: snapshot.generation)
        try lifecycle.close()
    }
}

@Suite("Startup recovery presentation")
@MainActor
struct StartupRecoveryTests {
    @Test
    func failedStartupCanCancelAndResetFromSettings() async throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let directory = fixture.root.appendingPathComponent("unavailable-ui")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("Synthetic corrupt database".utf8).write(to: directory.appendingPathComponent("ledger.sqlite"))
        let dependencies = AppDependencies(directory: directory)
        await dependencies.start()
        #expect(dependencies.session.snapshot == nil)
        #expect(dependencies.session.showsStartupFailure)
        dependencies.session.showsStartupFailure = false
        let settings = SettingsState(dependencies: dependencies)
        await settings.reset()
        #expect(dependencies.session.snapshot?.accountCount == 0)
        #expect(!dependencies.session.isBusy)
        #expect(!dependencies.session.showsStartupFailure)
        try await dependencies.database.close()
    }
}

@Suite("Automatic backup availability")
@MainActor
struct AutomaticBackupAvailabilityTests {
    @Test
    func backupFailureDoesNotBlockStartupAndForegroundCanRetry() async throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let directory = fixture.root.appendingPathComponent("backup-warning")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dependencies = AppDependencies(directory: directory)
        try Data("Synthetic file blocking backup directory".utf8).write(to: dependencies.backupDirectory)
        await dependencies.start()
        #expect(dependencies.session.snapshot != nil)
        #expect(dependencies.session.backupWarning != nil)
        #expect(!dependencies.session.showsStartupFailure)
        #expect(!dependencies.session.isBusy)
        try FileManager.default.removeItem(at: dependencies.backupDirectory)
        await dependencies.start()
        #expect(dependencies.session.backupWarning == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dependencies.backupDirectory.path).count == 1)
        try await dependencies.database.close()
    }
}

@Suite("Backup retention safety")
struct BackupRetentionSafetyTests {
    @Test
    func failedSnapshotDoesNotPruneOlderBackups() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle()
        let snapshot = try lifecycle.open()
        let folder = fixture.root.appendingPathComponent("retention")
        let first = try lifecycle.dailyBackup(in: folder, now: Date(timeIntervalSince1970: 0), timeZone: .gmt, expectedGeneration: snapshot.generation)
        let blocker = try SQLiteConnection(url: lifecycle.workingURL)
        try blocker.execute("BEGIN EXCLUSIVE")
        #expect(throws: (any Error).self) { try lifecycle.dailyBackup(in: folder, now: Date(timeIntervalSince1970: 31 * 86400), timeZone: .gmt, expectedGeneration: snapshot.generation) }
        #expect(FileManager.default.fileExists(atPath: first.path))
        try blocker.execute("ROLLBACK")
        try blocker.close()
        try lifecycle.close()
    }

    @Test
    func localCalendarDayAndInterruptedPartialAreHandled() throws {
        let fixture = try StorageFixture()
        defer { try? fixture.remove() }
        let lifecycle = try fixture.lifecycle()
        let snapshot = try lifecycle.open()
        let folder = fixture.root.appendingPathComponent("local-days")
        let now = ISO8601DateFormatter().date(from: "2026-07-02T02:00:00Z")!
        let toronto = TimeZone(identifier: "America/Toronto")!
        let first = try lifecycle.dailyBackup(in: folder, now: now, timeZone: toronto, expectedGeneration: snapshot.generation)
        #expect(first.lastPathComponent.contains("2026-07-01"))
        let partial = folder.appendingPathComponent(".Trexpend-Auto-2026-07-01-" + UUID().uuidString + ".sqlite.partial")
        try Data("Synthetic interrupted snapshot".utf8).write(to: partial)
        #expect(try lifecycle.dailyBackup(in: folder, now: now, timeZone: toronto, expectedGeneration: snapshot.generation) == first)
        #expect(!FileManager.default.fileExists(atPath: partial.path))
        try Data("Synthetic damaged daily copy".utf8).write(to: first)
        let replacement = try lifecycle.dailyBackup(in: folder, now: now, timeZone: toronto, expectedGeneration: snapshot.generation)
        #expect(replacement != first)
        try lifecycle.close()
    }
}
