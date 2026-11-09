import Foundation
import Observation

@MainActor
@Observable
final class AccountEditorState {
    var draft = AccountDraft()
    private(set) var context: AccountEditorContext?
    private var didCommit = false
    private var initial: AccountDraft?
    private(set) var isLoading = false
    private(set) var isSaving = false
    var isImporting = false
    var error: String?
    var isDirty: Bool { initial.map { $0 != draft } ?? false }
    var currency: CurrencyInfo? { context?.catalog.currencies.first { $0.id == draft.currencyID } }

    func load(dependencies: AppDependencies, generation: UUID, accountID: Int64?) async {
        guard context == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await dependencies.database.accountEditor(accountID: accountID, expectedGeneration: generation)
            guard dependencies.session.snapshot?.generation == generation else { throw DatabaseError.staleDataset }
            var value = AccountDraft()
            if let row = result.original { value = try .editing(row) }
            else {
                value.currencyID = dependencies.session.snapshot?.settings.displayCurrencyID
                value.openDate = try LocalDateTime(instant: Date(), timeZone: .current).calendarDay
            }
            context = result; draft = value; initial = value
        } catch { self.error = error.localizedDescription }
    }

    func save(dependencies: AppDependencies, deleting: Bool = false) async -> Bool {
        guard !isSaving, !isImporting, !didCommit, let context,
              dependencies.session.snapshot?.generation == context.generation,
              dependencies.session.beginOperation() else { return false }
        isSaving = true; error = nil
        defer { isSaving = false; dependencies.session.endOperation() }
        do {
            let result: DatabaseSnapshot
            if deleting { result = try await dependencies.database.deleteAccount(context: context) }
            else { result = try await dependencies.database.saveAccount(draft, context: context, now: Date()) }
            didCommit = true
            dependencies.session.accountsDidCommit(result, settings: dependencies.settings)
            return true
        } catch {
            self.error = error.localizedDescription
            dependencies.session.handleRecoveryFailure(error, settings: dependencies.settings)
            return false
        }
    }
}
