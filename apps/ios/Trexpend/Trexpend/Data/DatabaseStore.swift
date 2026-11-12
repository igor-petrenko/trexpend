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

    func history(accountID: Int64, expectedGeneration: UUID, month: CalendarMonth, retainingThrough: String? = nil, retainingID: Int64? = nil) async throws -> AccountHistorySnapshot {
        try await enqueue { try $0.history(accountID: accountID, expectedGeneration: expectedGeneration, month: month, retainingThrough: retainingThrough, retainingID: retainingID) }
    }

    func historyPage(accountID: Int64, expectedGeneration: UUID, cursor: HistoryCursor, expectedRevision: UInt64? = nil) async throws -> HistoryPage {
        try await enqueue { try $0.historyPage(accountID: accountID, expectedGeneration: expectedGeneration, cursor: cursor, expectedRevision: expectedRevision) }
    }

    func allHistory(expectedGeneration: UUID, month: CalendarMonth, retainingThrough: String? = nil, retainingID: Int64? = nil) async throws -> AllHistorySnapshot {
        try await enqueue { try $0.allHistory(expectedGeneration: expectedGeneration, month: month, retainingThrough: retainingThrough, retainingID: retainingID) }
    }

    func allHistoryPage(expectedGeneration: UUID, cursor: AllHistoryCursor, expectedRevision: UInt64? = nil) async throws -> AllHistoryPage {
        try await enqueue { try $0.allHistoryPage(expectedGeneration: expectedGeneration, cursor: cursor, expectedRevision: expectedRevision) }
    }

    func editor(transactionID: Int64?, expectedGeneration: UUID) async throws -> TransactionEditorContext {
        try await enqueue { try $0.editor(transactionID: transactionID, expectedGeneration: expectedGeneration) }
    }

    func recipient(source: Int64, expectedGeneration: UUID) async throws -> Int64? {
        try await enqueue { try $0.recipient(source: source, expectedGeneration: expectedGeneration) }
    }

    func saveTransaction(_ draft: TransactionDraft, context: TransactionEditorContext, now: Date, timeZone: TimeZone) async throws -> TransactionCommit {
        try await enqueue { try $0.saveTransaction(draft, context: context, now: now, timeZone: timeZone) }
    }

    func categoryCatalog(expectedGeneration: UUID) async throws -> CategoryCatalog {
        try await enqueue { try $0.categoryCatalog(expectedGeneration: expectedGeneration) }
    }

    func categoryEditor(id: Int64?, expectedGeneration: UUID) async throws -> CategoryEditorContext {
        try await enqueue { try $0.categoryEditor(id: id, expectedGeneration: expectedGeneration) }
    }

    func categoryReorder(parentID: Int64?, expectedGeneration: UUID) async throws -> CategoryReorderContext {
        try await enqueue { try $0.categoryReorder(parentID: parentID, expectedGeneration: expectedGeneration) }
    }

    func saveCategory(_ draft: CategoryDraft, context: CategoryEditorContext) async throws -> DatabaseSnapshot {
        try await enqueue { try $0.saveCategory(draft, context: context) }
    }

    func deleteCategory(context: CategoryEditorContext) async throws -> DatabaseSnapshot {
        try await enqueue { try $0.deleteCategory(context: context) }
    }

    func reorderCategories(_ ids: [Int64], context: CategoryReorderContext) async throws -> DatabaseSnapshot {
        try await enqueue { try $0.reorderCategories(ids, context: context) }
    }

    func managedAccounts(expectedGeneration: UUID) async throws -> AccountCatalog {
        try await enqueue { try $0.managedAccounts(expectedGeneration: expectedGeneration) }
    }

    func accountEditor(accountID: Int64?, expectedGeneration: UUID) async throws -> AccountEditorContext {
        try await enqueue { try $0.accountEditor(accountID: accountID, expectedGeneration: expectedGeneration) }
    }

    func customAccountImage(id: Int64, expectedGeneration: UUID) async throws -> Data? {
        try await enqueue { try $0.customAccountImage(id: id, expectedGeneration: expectedGeneration) }
    }

    func saveAccount(_ draft: AccountDraft, context: AccountEditorContext, now: Date) async throws -> DatabaseSnapshot {
        try await enqueue { try $0.saveAccount(draft, context: context, now: now) }
    }

    func deleteAccount(context: AccountEditorContext) async throws -> DatabaseSnapshot {
        try await enqueue { try $0.deleteAccount(context: context) }
    }

    func accountCatalog(expectedGeneration: UUID) async throws -> [EditorAccount] {
        try await enqueue { try $0.accountCatalog(expectedGeneration: expectedGeneration) }
    }

    func setDefaultAccount(_ id: Int64?, expectedGeneration: UUID) async throws -> DatabaseSnapshot {
        try await enqueue { try $0.setDefaultAccount(id, expectedGeneration: expectedGeneration) }
    }

    func deletionTarget(transactionID: Int64, expectedGeneration: UUID) async throws -> TransactionDeletionTarget {
        try await enqueue { try $0.deletionTarget(transactionID: transactionID, expectedGeneration: expectedGeneration) }
    }

    func deleteTransaction(_ target: TransactionDeletionTarget) async throws -> TransactionCommit {
        try await enqueue { try $0.deleteTransaction(target) }
    }

    func currencyCatalog(expectedGeneration: UUID) async throws -> [CurrencyInfo] {
        try await enqueue { try $0.currencyCatalog(expectedGeneration: expectedGeneration) }
    }

    func setAccountFavorite(_ favorite: Bool, accountID: Int64, expectedGeneration: UUID) async throws -> DatabaseSnapshot {
        try await enqueue { try $0.setAccountFavorite(favorite, accountID: accountID, expectedGeneration: expectedGeneration) }
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
