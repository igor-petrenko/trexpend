import Foundation
import Observation

@MainActor
@Observable
final class TransactionEditorState {
    var draft = TransactionDraft(localDate: "")
    private(set) var context: TransactionEditorContext?
    private var initial: TransactionDraft?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private var hasSaved = false
    var error: String?
    var roundingMessage: String?
    private var recipients: [Int64: Int64] = [:]
    private var resolvedSources: Set<Int64> = []
    private var suggestionRequest = UUID()
    var isDirty: Bool { initial.map { draft != $0 } ?? false }
    var source: EditorAccount? { context?.accounts.first { $0.id == draft.accountID } }
    var receiver: EditorAccount? { context?.accounts.first { $0.id == draft.receiverID } }
    var isTransfer: Bool { draft.type == .transfer }
    var showsReceiverAmount: Bool { isTransfer && source?.currency.id != receiver?.currency.id }

    func load(database: DatabaseStore, generation: UUID, transactionID: Int64?, accountID: Int64?, now: Date = Date()) async {
        guard context == nil, !isLoading else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let loaded = try await database.editor(transactionID: transactionID, expectedGeneration: generation)
            var value: TransactionDraft
            if let original = loaded.original { value = try .editing(original) }
            else {
                value = TransactionDraft(localDate: try LocalDateTime(instant: now, timeZone: .current).storage)
                let requested = accountID ?? loaded.settings.defaultAccountID
                value.accountID = loaded.accounts.first { $0.id == requested && $0.isOpen }?.id
                value.categoryID = loaded.categories.first { $0.id == loaded.settings.lastCreatedCategoryID && $0.active }?.id
                if value.categoryID == nil {
                    let general = loaded.categories.filter { $0.name == "General" && $0.parentID == nil && $0.active }
                    if general.count == 1 { value.categoryID = general[0].id }
                }
            }
            context = loaded; draft = value; initial = value
        } catch { self.error = error.localizedDescription }
    }

    func refreshCategories(database: DatabaseStore, generation: UUID) async {
        guard let context, context.generation == generation, !isSaving, !hasSaved else { return }
        do {
            let fresh = try await database.editor(transactionID: nil, expectedGeneration: generation)
            guard !Task.isCancelled, self.context?.generation == generation, !isSaving, !hasSaved else { return }
            self.context = TransactionEditorContext(generation: generation, accounts: context.accounts, categories: fresh.categories,
                settings: fresh.settings, converter: context.converter, original: context.original)
        } catch { self.error = error.localizedDescription }
    }

    func changeType(_ type: LedgerTransactionType, database: DatabaseStore) async {
        let transferCategory = context?.categories.first { $0.id == context?.settings.transferCategoryID && $0.active }?.id
        draft.changeType(type, transferCategory: transferCategory)
        if type == .transfer { await suggestRecipient(database: database) }
    }

    func changeSource(_ id: Int64, database: DatabaseStore) async {
        draft.accountID = id
        if isTransfer { await suggestRecipient(database: database) }
    }

    func chooseReceiver(_ id: Int64) {
        suggestionRequest = UUID()
        draft.receiverID = id; draft.receiverIsManual = true
        suggestAmount()
    }

    private func suggestRecipient(database: DatabaseStore) async {
        guard isTransfer, !draft.receiverIsManual, let source = draft.accountID, let context else { suggestAmount(); return }
        let request = UUID(); suggestionRequest = request
        do {
            if !resolvedSources.contains(source) {
                let id = try await database.recipient(source: source, expectedGeneration: context.generation)
                guard suggestionRequest == request else { return }
                resolvedSources.insert(source); recipients[source] = id
            }
            guard suggestionRequest == request, isTransfer, !draft.receiverIsManual, draft.accountID == source else { return }
            draft.receiverID = recipients[source]
            suggestAmount()
        } catch { self.error = error.localizedDescription }
    }

    func suggestAmount() {
        guard isTransfer, !draft.receiverAmountIsManual, let context, let source, let receiver else { return }
        if source.currency.id == receiver.currency.id { draft.receiverAmount = draft.amount; return }
        do {
            let amount = try MoneyCodec.parseInput(draft.amount, places: source.currency.decimalPlaces)
            let suggested = try context.converter.suggestedAmount(MonetaryAmount(value: amount, currencyID: source.currency.id), to: receiver.currency.ledger)
            draft.receiverAmount = try MoneyCodec.encode(suggested, places: receiver.currency.decimalPlaces)
        } catch { draft.receiverAmount = "" }
    }

    func changeAmount(_ text: String) {
        draft.amount = text
        // An explicitly changed same-currency principal updates its hidden side.
        if isTransfer, source?.currency.id == receiver?.currency.id {
            draft.receiverAmount = text
        } else { suggestAmount() }
    }

    func dateChanged(_ date: Date) {
        do {
            let day = try LocalDateTime(instant: date, timeZone: .current)
            draft.localDate = try TransactionDateRules.changingDay(of: LocalDateTime(storage: draft.localDate), to: day).storage
        } catch { self.error = error.localizedDescription }
    }

    func timeChanged(_ date: Date) {
        do {
            let time = try LocalDateTime(instant: date, timeZone: .current)
            let day = try LocalDateTime(storage: draft.localDate)
            draft.localDate = try LocalDateTime(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute, second: time.second).storage
        } catch { self.error = error.localizedDescription }
    }

    var pickerDate: Date {
        guard let local = try? LocalDateTime(storage: draft.localDate) else { return Date() }
        return LocalDateTime.calendar(in: .current).date(from: local.components) ?? Date()
    }

    func save(dependencies: AppDependencies, confirmRounding: Bool = false) async -> Bool {
        guard let context, !isSaving, !hasSaved else { return false }
        isSaving = true; error = nil
        defer { isSaving = false }
        do {
            guard dependencies.session.snapshot?.generation == context.generation else { throw DatabaseError.staleDataset }
            let values = try TransactionWrite.validate(draft, context: context, now: Date(), timeZone: .current)
            if !confirmRounding, !values.roundedFields.isEmpty {
                roundingMessage = values.roundedFields.joined(separator: "\n")
                return false
            }
            let result = try await dependencies.database.saveTransaction(draft, context: context, now: Date(), timeZone: .current)
            hasSaved = true
            dependencies.session.transactionDidCommit(result, settings: dependencies.settings)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
