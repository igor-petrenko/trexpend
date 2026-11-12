import Foundation
import Observation

@MainActor
@Observable
final class CategoryEditorState {
    var draft = CategoryDraft()
    private(set) var context: CategoryEditorContext?
    private var initial: CategoryDraft?
    private var didCommit = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    var error: String?
    var isDirty: Bool { initial.map { $0 != draft } ?? false }
    var record: ManagedCategory? {
        guard let original = context?.original, let id = try? original.integer("id") else { return nil }
        return context?.catalog.categories.first { $0.id == id }
    }
    var canDelete: Bool { record.map { $0.directCount == 0 && $0.childCount == 0 } ?? false }
    var excludedParents: Set<Int64> {
        guard let record, let context else { return [] }
        return context.catalog.descendants(of: record.id).union([record.id])
    }

    func load(dependencies: AppDependencies, generation: UUID, id: Int64?, parentID: Int64?) async {
        guard context == nil, !isLoading else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let loaded = try await dependencies.database.categoryEditor(id: id, expectedGeneration: generation)
            guard dependencies.session.snapshot?.generation == generation else { throw DatabaseError.staleDataset }
            var value = CategoryDraft()
            if let original = loaded.original { value = try .editing(original) }
            else { value.parentID = parentID }
            draft = value; initial = value; context = loaded
        } catch { self.error = error.localizedDescription }
    }

    func save(dependencies: AppDependencies, deleting: Bool = false) async -> Bool {
        guard let context, !isSaving, !didCommit, dependencies.session.snapshot?.generation == context.generation,
              dependencies.session.beginOperation() else { return false }
        isSaving = true; error = nil
        defer { isSaving = false; dependencies.session.endOperation() }
        do {
            let snapshot: DatabaseSnapshot
            if deleting { snapshot = try await dependencies.database.deleteCategory(context: context) }
            else { snapshot = try await dependencies.database.saveCategory(draft, context: context) }
            didCommit = true
            dependencies.session.categoriesDidCommit(snapshot, settings: dependencies.settings)
            return true
        } catch {
            self.error = error.localizedDescription
            dependencies.session.handleRecoveryFailure(error, settings: dependencies.settings)
            return false
        }
    }
}
