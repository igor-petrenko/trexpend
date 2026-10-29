import Darwin
import Foundation

nonisolated enum ReplacementBoundary: String, CaseIterable, Sendable {
    case markerWritten, oldMoved, candidateMoved, newOpened, commitWritten, cleanupStarted
}

nonisolated struct LifecycleInterruption: Error {}

// Mutable state is used only by DatabaseStore's serial worker. Tests may use
// their own isolated instance to simulate an interrupted process.
nonisolated final class DatabaseLifecycle {
    let directory: URL
    private let resources: DatabaseResources
    private let validator: DatabaseValidator
    private let fault: (@Sendable (ReplacementBoundary) throws -> Void)?
    private var connection: SQLiteConnection?
    private var generation = UUID()
    private var hasCleanedExports = false
    private var recoveryReplacement = false
    private var replacementHadWorking = true
    private let files = FileManager.default

    var workingURL: URL { directory.appendingPathComponent("ledger.sqlite") }
    private var candidateURL: URL { directory.appendingPathComponent("candidate.sqlite") }
    private var previousURL: URL { directory.appendingPathComponent("previous.sqlite") }
    private var recoveryRequiredURL: URL { directory.appendingPathComponent("recovery-required") }
    var exportsDirectory: URL { directory.appendingPathComponent("TemporaryExports", isDirectory: true) }
    private var markerURL: URL { directory.appendingPathComponent("replacement.json") }

    private struct Marker: Codable {
        let version: Int
        let phase: String
        var unavailable: Bool?
        var hadWorking: Bool?
    }

    init(directory: URL, resources: DatabaseResources, fault: (@Sendable (ReplacementBoundary) throws -> Void)? = nil) throws {
        self.directory = directory
        self.resources = resources
        self.fault = fault
        validator = try DatabaseValidator(resources: resources)
    }

    func open() throws -> DatabaseSnapshot {
        if let connection { return try validator.snapshot(connection, generation: generation) }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        if !hasCleanedExports {
            try remove(directory.appendingPathComponent("Exports"))
            try remove(exportsDirectory)
            hasCleanedExports = true
        }
        try recover()
        guard !exists(recoveryRequiredURL) else { throw DatabaseError.recoveryRequired }
        if !exists(workingURL) {
            guard !exists(previousURL), !exists(candidateURL) else { throw DatabaseError.recoveryRequired }
            let initial = directory.appendingPathComponent("initial.sqlite")
            try remove(initial)
            do {
                try create(at: initial)
                try move(initial, to: workingURL)
            } catch {
                // Failed initialization remains at a staging path, never as a
                // supposedly valid working ledger. Retry can recreate it.
                throw error
            }
        }
        let snapshot = try openWorking()
        if let connection, try DatabaseMigrator.version(connection) == 1 {
            try remove(candidateURL)
            let candidate = try SQLiteConnection(url: candidateURL, create: true)
            try connection.backup(to: candidate)
            try candidate.close()
            try close()
            try prepareCandidate()
            return try replace()
        }
        return snapshot
    }

    func current(expectedGeneration: UUID) throws -> DatabaseSnapshot {
        guard expectedGeneration == generation, let connection else { throw DatabaseError.staleDataset }
        return try validator.snapshot(connection, generation: generation)
    }

    func home(expectedGeneration: UUID, month: CalendarMonth) throws -> HomeSnapshot {
        guard expectedGeneration == generation, let connection else { throw DatabaseError.staleDataset }
        return try connection.transaction(readOnly: true) { try HomeRead.snapshot(connection, generation: generation, month: month) }
    }

    func history(accountID: Int64, expectedGeneration: UUID, month: CalendarMonth) throws -> AccountHistorySnapshot {
        guard expectedGeneration == generation, let connection else { throw DatabaseError.staleDataset }
        return try connection.transaction(readOnly: true) { try HistoryRead.snapshot(connection, accountID: accountID, generation: generation, month: month) }
    }

    func historyPage(accountID: Int64, expectedGeneration: UUID, cursor: HistoryCursor) throws -> HistoryPage {
        guard expectedGeneration == generation, let connection else { throw DatabaseError.staleDataset }
        return try connection.transaction(readOnly: true) { try HistoryRead.page(connection, accountID: accountID, generation: generation, cursor: cursor) }
    }

    func allHistory(expectedGeneration: UUID, month: CalendarMonth) throws -> AllHistorySnapshot {
        guard expectedGeneration == generation, let connection else { throw DatabaseError.staleDataset }
        return try connection.transaction(readOnly: true) { try AllHistoryRead.snapshot(connection, generation: generation, month: month) }
    }

    func allHistoryPage(expectedGeneration: UUID, cursor: AllHistoryCursor) throws -> AllHistoryPage {
        guard expectedGeneration == generation, let connection else { throw DatabaseError.staleDataset }
        return try connection.transaction(readOnly: true) { try AllHistoryRead.page(connection, generation: generation, cursor: cursor) }
    }

    func currencyCatalog(expectedGeneration: UUID) throws -> [CurrencyInfo] {
        guard expectedGeneration == generation, let connection else { throw DatabaseError.staleDataset }
        return try HomeRead.currencies(connection)
    }

    func setDisplayCurrency(_ id: Int64, expectedGeneration: UUID) throws -> DatabaseSnapshot {
        guard expectedGeneration == generation, let connection else { throw DatabaseError.staleDataset }
        try connection.transaction {
            guard try connection.rows("SELECT id FROM currencies WHERE id=?", parameters: [.integer(id)]).count == 1 else { throw DatabaseError.invalidData }
            try connection.run("UPDATE app_settings SET display_currency_id=? WHERE id=1", parameters: [.integer(id)])
        }
        return try validator.snapshot(connection, generation: generation)
    }

    func importDatabase(from source: URL, expectedGeneration: UUID?) throws -> DatabaseSnapshot {
        if expectedGeneration == nil { return try restoreUnavailable(from: source) }
        guard expectedGeneration == generation, connection != nil else { throw DatabaseError.staleDataset }
        try recover()
        try remove(candidateURL)
        try Self.requireStandalone(source)
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 512 * 1024 * 1024 else { throw DatabaseError.invalidDatabase }
        do {
            try files.copyItem(at: source, to: candidateURL)
            try prepareCandidate()
        } catch {
            try remove(candidateURL)
            throw error
        }
        return try replace()
    }

    func reset(expectedGeneration: UUID?) throws -> DatabaseSnapshot {
        if expectedGeneration == nil { return try restoreUnavailable(from: nil) }
        guard expectedGeneration == generation, connection != nil else { throw DatabaseError.staleDataset }
        try recover()
        try remove(candidateURL)
        try create(at: candidateURL)
        return try replace()
    }

    func exportSnapshot(expectedGeneration: UUID) throws -> URL {
        guard expectedGeneration == generation, let connection else { throw DatabaseError.staleDataset }
        let folder = exportsDirectory
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        var excluded = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "Trexpend-" + formatter.string(from: Date()) + "-" + UUID().uuidString.prefix(8) + ".sqlite"
        let url = folder.appendingPathComponent(filename)
        do {
            let destination = try SQLiteConnection(url: url, create: true)
            try connection.backup(to: destination)
            try destination.configureWorking()
            try destination.close()
            try syncFile(url)
            let reopened = try SQLiteConnection(url: url, readOnly: true)
            _ = try validator.validate(reopened, generation: generation)
            try reopened.close()
            return url
        } catch {
            try remove(url)
            throw error
        }
    }

    func discardExport(_ url: URL) throws {
        guard url.deletingLastPathComponent().standardizedFileURL == exportsDirectory.standardizedFileURL else {
            throw DatabaseError.fileAccess
        }
        try remove(url)
    }

    func dailyBackup(in folder: URL, now: Date, timeZone: TimeZone, expectedGeneration: UUID) throws -> URL {
        guard expectedGeneration == generation, connection != nil else { throw DatabaseError.staleDataset }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let calendar = LocalDateTime.calendar(in: timeZone)
        let day = try LocalDateTime(instant: now, timeZone: timeZone).calendarDay
        let cutoff = try LocalDateTime(instant: calendar.date(byAdding: .day, value: -30, to: now)!, timeZone: timeZone).calendarDay
        var owned: [(URL, String)] = []
        for url in try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            let storedName = url.lastPathComponent
            let partial = storedName.hasPrefix(".") && storedName.hasSuffix(".partial")
            let name = partial ? String(storedName.dropFirst().dropLast(8)) : storedName
            guard name.hasPrefix("Trexpend-Auto-"), name.hasSuffix(".sqlite") else { continue }
            let tail = String(name.dropFirst(14).dropLast(7))
            guard tail.count == 47, tail.dropFirst(10).first == "-",
                  UUID(uuidString: String(tail.dropFirst(11))) != nil else { continue }
            let date = String(tail.prefix(10))
            guard (try? LocalDateTime(storage: date + "T00:00:00")) != nil else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true && values.isSymbolicLink != true {
                if partial { try remove(url) } else { owned.append((url, date)) }
            }
        }
        var current: URL?
        for (url, date) in owned where date == day {
            do {
                let db = try SQLiteConnection(url: url, readOnly: true)
                _ = try validator.validate(db, generation: generation)
                try db.close()
                current = url
                break
            } catch { continue }
        }
        if current == nil {
            let snapshot = try exportSnapshot(expectedGeneration: expectedGeneration)
            defer { try? discardExport(snapshot) }
            let final = folder.appendingPathComponent("Trexpend-Auto-" + day + "-" + UUID().uuidString + ".sqlite")
            let temporary = folder.appendingPathComponent("." + final.lastPathComponent + ".partial")
            defer { try? remove(temporary) }
            try files.copyItem(at: snapshot, to: temporary)
            try syncFile(temporary)
            guard Darwin.rename(temporary.path, final.path) == 0 else { throw DatabaseError.fileAccess }
            try syncDirectory(at: folder)
            current = final
        }
        // Delete only recognized app-created snapshots, after a usable current-day
        // copy exists. Files placed here manually are never part of retention.
        for (url, date) in owned where date < cutoff { try remove(url) }
        try syncDirectory(at: folder)
        guard let current else { throw DatabaseError.fileAccess }
        return current
    }

    func close() throws {
        try connection?.close()
        connection = nil
    }

    static func requireStandalone(_ url: URL) throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            if FileManager.default.fileExists(atPath: url.path + suffix) { throw DatabaseError.invalidDatabase }
        }
    }

    private func create(at url: URL) throws {
        let db = try SQLiteConnection(url: url, create: true)
        try db.configureWorking()
        try db.transaction {
            try db.execute(resources.schema)
            try db.execute(resources.defaults)
        }
        try DatabaseMigrator.upgrade(db, resources: resources)
        _ = try validator.validate(db, generation: generation)
        try db.close()
        try Self.requireStandalone(url)
        try syncFile(url)
    }

    private func prepareCandidate() throws {
        let readOnly = try SQLiteConnection(url: candidateURL, readOnly: true)
        _ = try validator.validate(readOnly, generation: generation)
        try readOnly.close()
        let candidate = try SQLiteConnection(url: candidateURL)
        try candidate.configureWorking()
        try DatabaseMigrator.upgrade(candidate, resources: resources)
        _ = try validator.validate(candidate, generation: generation)
        try candidate.close()
        try Self.requireStandalone(candidateURL)
        try syncFile(candidateURL)
    }

    private func restoreUnavailable(from source: URL?) throws -> DatabaseSnapshot {
        guard connection == nil else { throw DatabaseError.staleDataset }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appendingPathComponent("restoration.sqlite")
        for suffix in ["", "-journal", "-wal", "-shm"] { try remove(URL(fileURLWithPath: staged.path + suffix)) }
        defer {
            for suffix in ["", "-journal", "-wal", "-shm"] { try? remove(URL(fileURLWithPath: staged.path + suffix)) }
        }
        if let source {
            try Self.requireStandalone(source)
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size > 0, size <= 512 * 1024 * 1024 else { throw DatabaseError.invalidDatabase }
            try files.copyItem(at: source, to: staged)
            let db = try SQLiteConnection(url: staged, readOnly: true)
            _ = try validator.validate(db, generation: generation)
            try db.close()
            let migrating = try SQLiteConnection(url: staged)
            try migrating.configureWorking()
            try DatabaseMigrator.upgrade(migrating, resources: resources)
            _ = try validator.validate(migrating, generation: generation)
            try migrating.close()
        } else { try create(at: staged) }
        try Data("Recovery requested".utf8).write(to: recoveryRequiredURL)
        try syncFile(recoveryRequiredURL)
        try syncDirectory()
        let archive = directory.appendingPathComponent("Recovery").appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: archive, withIntermediateDirectories: true)
        let owned = ["ledger.sqlite", "previous.sqlite", "candidate.sqlite", "replacement.json", "replacement.tmp", "rollback.sqlite", "initial.sqlite"]
        let names = owned.flatMap { [$0, $0 + "-journal", $0 + "-wal", $0 + "-shm"] }
        for name in names {
            let original = directory.appendingPathComponent(name)
            if exists(original) {
                let copy = archive.appendingPathComponent(name)
                try files.copyItem(at: original, to: copy)
                try syncFile(copy)
            }
        }
        try syncDirectory(at: archive)
        try syncDirectory(at: archive.deletingLastPathComponent())
        try syncDirectory()
        // The archive is now durable. Old journal/marker artifacts must not be
        // interpreted against the new candidate, but the old main file stays
        // available to the shared replacement rollback path.
        for name in names where name != "ledger.sqlite" { try remove(directory.appendingPathComponent(name)) }
        try move(staged, to: candidateURL)
        let candidate = try SQLiteConnection(url: candidateURL)
        try candidate.configureWorking()
        try candidate.close()
        try syncFile(candidateURL)
        recoveryReplacement = true
        replacementHadWorking = exists(workingURL)
        defer { recoveryReplacement = false }
        return try replace()
    }

    private func replace() throws -> DatabaseSnapshot {
        let oldGeneration = generation
        let nextGeneration = UUID()
        var committed: DatabaseSnapshot?
        do {
            try close()
            try writeMarker("switching")
            try fault?(.markerWritten)
            if exists(workingURL) { try move(workingURL, to: previousURL) }
            try fault?(.oldMoved)
            try move(candidateURL, to: workingURL)
            try fault?(.candidateMoved)
            let next = try openWorking(generation: nextGeneration)
            try fault?(.newOpened)
            try writeMarker("committed")
            generation = nextGeneration
            committed = next
            try fault?(.commitWritten)
            try fault?(.cleanupStarted)
            try cleanupCommitted(clearsRecovery: recoveryReplacement)
            return next
        } catch is LifecycleInterruption {
            // The test simulates process termination: the next instance, rather
            // than this stack's catch path, must recover durable artifacts.
            try close()
            throw LifecycleInterruption()
        } catch {
            if let committed {
                // Replacement is already durable. Keep the committed marker for
                // cleanup on the next open, but do not report a false rollback.
                return committed
            }
            do {
                try close()
                try recover(forceRollback: true)
                generation = oldGeneration
                if !recoveryReplacement { _ = try openWorking() }
            } catch {
                throw DatabaseError.recoveryRequired
            }
            throw error
        }
    }

    private func recover(forceRollback: Bool = false) throws {
        guard exists(markerURL) else {
            guard !exists(previousURL) else { throw DatabaseError.recoveryRequired }
            return
        }
        let marker: Marker
        do { marker = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: markerURL)) }
        catch { throw DatabaseError.recoveryRequired }
        guard marker.version == 1 else { throw DatabaseError.recoveryRequired }
        let unavailable = marker.unavailable == true
        if (marker.phase == "committed" && !forceRollback) || marker.phase == "rolledBack" {
            if !unavailable || marker.phase == "committed" {
                guard exists(workingURL) else { throw DatabaseError.recoveryRequired }
                let db = try SQLiteConnection(url: workingURL)
                _ = try validator.snapshot(db, generation: generation)
                try db.close()
            }
            try cleanupCommitted(clearsRecovery: unavailable && marker.phase == "committed")
        } else if marker.phase == "switching" || (marker.phase == "committed" && forceRollback) {
            if exists(previousURL) {
                try Self.requireStandalone(previousURL)
                if exists(workingURL) { try Self.requireStandalone(workingURL) }
                // Keep previous intact until rollback is itself durable, making
                // another interruption during recovery safe to retry.
                let restored = directory.appendingPathComponent("rollback.sqlite")
                try remove(restored)
                try files.copyItem(at: previousURL, to: restored)
                try syncFile(restored)
                try move(restored, to: workingURL, replacing: true)
            } else {
                if unavailable && marker.hadWorking == false {
                    try remove(workingURL)
                } else {
                    guard exists(workingURL), exists(candidateURL) else { throw DatabaseError.recoveryRequired }
                }
            }
            // Validate recovered data before discarding any remaining staging.
            if !unavailable {
                let db = try SQLiteConnection(url: workingURL)
                _ = try validator.snapshot(db, generation: generation)
                try db.close()
            }
            let rollback = Marker(version: 1, phase: "rolledBack", unavailable: marker.unavailable, hadWorking: marker.hadWorking)
            try persistMarker(rollback)
            try cleanupCommitted()
        } else { throw DatabaseError.recoveryRequired }
    }

    private func openWorking(generation requested: UUID? = nil) throws -> DatabaseSnapshot {
        let db = try SQLiteConnection(url: workingURL)
        do {
            try db.configureWorking()
            let snapshot = try validator.snapshot(db, generation: requested ?? generation)
            connection = db
            return snapshot
        } catch {
            try db.close()
            throw error
        }
    }

    private func cleanupCommitted(clearsRecovery: Bool = false) throws {
        try Self.requireStandalone(previousURL)
        try remove(previousURL)
        try remove(candidateURL)
        if clearsRecovery { try remove(recoveryRequiredURL) }
        try remove(markerURL)
        try syncDirectory()
    }

    private func writeMarker(_ phase: String) throws {
        try persistMarker(Marker(version: 1, phase: phase, unavailable: recoveryReplacement ? true : nil, hadWorking: recoveryReplacement ? replacementHadWorking : nil))
    }

    private func persistMarker(_ marker: Marker) throws {
        let temporary = directory.appendingPathComponent("replacement.tmp")
        try JSONEncoder().encode(marker).write(to: temporary)
        try syncFile(temporary)
        try move(temporary, to: markerURL, replacing: true)
    }

    private func exists(_ url: URL) -> Bool { files.fileExists(atPath: url.path) }

    private func remove(_ url: URL) throws {
        if exists(url) { try files.removeItem(at: url) }
    }

    private func move(_ from: URL, to: URL, replacing: Bool = false) throws {
        guard replacing || !exists(to), Darwin.rename(from.path, to.path) == 0 else { throw DatabaseError.fileAccess }
        try syncDirectory()
    }

    private func syncFile(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw DatabaseError.fileAccess }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw DatabaseError.fileAccess }
    }

    private func syncDirectory(at folder: URL? = nil) throws {
        let descriptor = Darwin.open((folder ?? directory).path, O_RDONLY)
        guard descriptor >= 0 else { throw DatabaseError.fileAccess }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw DatabaseError.fileAccess }
    }
}
