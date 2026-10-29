import Foundation

// Safety invariant: every mutable field below is accessed exclusively inside
// enqueue's serial queue block. No SQLite handle or lifecycle object escapes.
// Keep the Sendable bridge confined to this facade; replace it with a checked
// executor abstraction if the agreed serial-queue architecture changes.
nonisolated final class DatabaseStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.trexpend.database", qos: .userInitiated)
    private let directory: URL
    private let resources: DatabaseResources?
    private var lifecycle: DatabaseLifecycle?

    init(directory: URL, resources: DatabaseResources? = nil) {
        self.directory = directory
        self.resources = resources
    }

    func open() async throws -> DatabaseSnapshot {
        try await enqueue { try $0.open() }
    }

    func current(expectedGeneration: UUID) async throws -> DatabaseSnapshot {
        try await enqueue { try $0.current(expectedGeneration: expectedGeneration) }
    }

    func home(expectedGeneration: UUID, month: CalendarMonth) async throws -> HomeSnapshot {
        try await enqueue { try $0.home(expectedGeneration: expectedGeneration, month: month) }
    }

    func history(accountID: Int64, expectedGeneration: UUID, month: CalendarMonth) async throws -> AccountHistorySnapshot {
        try await enqueue { try $0.history(accountID: accountID, expectedGeneration: expectedGeneration, month: month) }
    }

    func historyPage(accountID: Int64, expectedGeneration: UUID, cursor: HistoryCursor) async throws -> HistoryPage {
        try await enqueue { try $0.historyPage(accountID: accountID, expectedGeneration: expectedGeneration, cursor: cursor) }
    }

    func allHistory(expectedGeneration: UUID, month: CalendarMonth) async throws -> AllHistorySnapshot {
        try await enqueue { try $0.allHistory(expectedGeneration: expectedGeneration, month: month) }
    }

    func allHistoryPage(expectedGeneration: UUID, cursor: AllHistoryCursor) async throws -> AllHistoryPage {
        try await enqueue { try $0.allHistoryPage(expectedGeneration: expectedGeneration, cursor: cursor) }
    }

    func currencyCatalog(expectedGeneration: UUID) async throws -> [CurrencyInfo] {
        try await enqueue { try $0.currencyCatalog(expectedGeneration: expectedGeneration) }
    }

    func setDisplayCurrency(_ id: Int64, expectedGeneration: UUID) async throws -> DatabaseSnapshot {
        try await enqueue { try $0.setDisplayCurrency(id, expectedGeneration: expectedGeneration) }
    }

    func importDatabase(from url: URL, expectedGeneration: UUID?) async throws -> DatabaseSnapshot {
        try await enqueue { try $0.importDatabase(from: url, expectedGeneration: expectedGeneration) }
    }

    func reset(expectedGeneration: UUID?) async throws -> DatabaseSnapshot {
        try await enqueue { try $0.reset(expectedGeneration: expectedGeneration) }
    }

    func exportSnapshot(expectedGeneration: UUID) async throws -> URL {
        try await enqueue { try $0.exportSnapshot(expectedGeneration: expectedGeneration) }
    }

    func discardExport(_ url: URL) async throws {
        try await enqueue { try $0.discardExport(url) }
    }

    func dailyBackup(in folder: URL, now: Date, timeZone: TimeZone, expectedGeneration: UUID) async throws -> URL {
        try await enqueue { try $0.dailyBackup(in: folder, now: now, timeZone: timeZone, expectedGeneration: expectedGeneration) }
    }

    func close() async throws {
        try await enqueue { try $0.close() }
    }

    private func enqueue<T: Sendable>(_ work: @escaping @Sendable (DatabaseLifecycle) throws -> T) async throws -> T {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                dispatchPrecondition(condition: .onQueue(queue))
                do {
                    if lifecycle == nil {
                        let configured = try resources ?? DatabaseResources.bundled()
                        lifecycle = try DatabaseLifecycle(directory: directory, resources: configured)
                    }
                    guard let lifecycle else { throw DatabaseError.sqlite }
                    continuation.resume(returning: try work(lifecycle))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
