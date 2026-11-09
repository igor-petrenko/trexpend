import Foundation
import Observation

@MainActor
@Observable
final class TransactionDeletionState {
    private(set) var target: TransactionDeletionTarget?
    private(set) var isBusy = false
    private(set) var didDelete = false
    var showsAlert = false
    private(set) var error: String?

    func request(transactionID: Int64, database: DatabaseStore, session: AppSession) async {
        guard !isBusy, target == nil, let generation = session.snapshot?.generation else { return }
        isBusy = true; didDelete = false; error = nil
        defer { isBusy = false }
        do {
            let value = try await database.deletionTarget(transactionID: transactionID, expectedGeneration: generation)
            guard session.snapshot?.generation == generation else { return }
            request(value)
        } catch {
            guard session.snapshot?.generation == generation else { return }
            self.error = error.localizedDescription; showsAlert = true
        }
    }

    func request(_ target: TransactionDeletionTarget) {
        didDelete = false
        self.target = target; error = nil; showsAlert = true
    }

    func cancel() { target = nil; error = nil; showsAlert = false }

    func confirm(database: DatabaseStore, session: AppSession, settings: SettingsStore) async {
        guard !isBusy, let target else { return }
        isBusy = true; error = nil; showsAlert = false
        defer { isBusy = false }
        do {
            let result = try await database.deleteTransaction(target)
            self.target = nil
            guard session.snapshot?.generation == result.snapshot.generation else { return }
            session.transactionDidCommit(result, settings: settings)
            didDelete = true
        } catch {
            self.target = nil
            guard session.snapshot?.generation == target.generation else { return }
            self.error = error.localizedDescription; showsAlert = true
        }
    }
}
