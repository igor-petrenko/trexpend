import Foundation

nonisolated final class DatabaseFileCoordinator: Sendable {
    private let store: DatabaseStore

    init(store: DatabaseStore) { self.store = store }

    @concurrent
    func importDatabase(from source: URL, expectedGeneration: UUID?) async throws -> DatabaseSnapshot {
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TrexpendImport-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let staged = folder.appendingPathComponent("source.sqlite")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { readable in
            do {
                try DatabaseLifecycle.requireStandalone(readable)
                let values = try readable.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size > 0, size <= 512 * 1024 * 1024 else { throw DatabaseError.invalidDatabase }
                try FileManager.default.copyItem(at: readable, to: staged)
            } catch { copyError = error }
        }
        if let copyError { throw copyError }
        guard coordinationError == nil else { throw DatabaseError.fileAccess }
        try Task.checkCancellation()
        return try await store.importDatabase(from: staged, expectedGeneration: expectedGeneration)
    }
}
