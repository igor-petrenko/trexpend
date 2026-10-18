import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
    enum DatabaseAvailability {
        case notLoaded
        case loading
        case ready(DatabaseSnapshot)
        case failed(String)
    }

    private(set) var databaseAvailability: DatabaseAvailability = .notLoaded
    private(set) var isBusy = false
    var showsStartupFailure = false
    var backupWarning: String?
    var recoveryAction: RecoveryAction?

    enum RecoveryAction: Equatable { case importDatabase, reset }

    var snapshot: DatabaseSnapshot? {
        if case .ready(let snapshot) = databaseAvailability { return snapshot }
        return nil
    }

    func start(store: DatabaseStore, settings: SettingsStore) async {
        guard !isBusy, snapshot == nil else { return }
        isBusy = true
        databaseAvailability = .loading
        defer { isBusy = false }
        do {
            let snapshot = try await store.open()
            publish(snapshot, settings: settings)

        } catch {
            settings.clear()
            databaseAvailability = .failed(Self.message(for: error))
            showsStartupFailure = true
        }
    }

    func backUpIfNeeded(store: DatabaseStore, folder: URL) async {
        guard let snapshot, beginOperation() else { return }
        defer { endOperation() }
        do {
            _ = try await store.dailyBackup(in: folder, now: Date(), timeZone: .current, expectedGeneration: snapshot.generation)
            backupWarning = nil
        } catch { backupWarning = "The automatic backup could not be created. Try again by reopening the app." }
    }

    func beginOperation(allowsUnavailable: Bool = false) -> Bool {
        guard !isBusy, (snapshot != nil || allowsUnavailable) else { return false }
        isBusy = true
        return true
    }

    func endOperation() { isBusy = false }

    func publish(_ snapshot: DatabaseSnapshot, settings: SettingsStore) {
        showsStartupFailure = false
        settings.load(snapshot)
        databaseAvailability = .ready(snapshot)
    }

    func handleRecoveryFailure(_ error: Error, settings: SettingsStore) {
        if error as? DatabaseError == .recoveryRequired {
            settings.clear()
            databaseAvailability = .failed(Self.message(for: error))
        }
    }

    static func message(for error: Error) -> String {
        (error as? DatabaseError)?.errorDescription ?? DatabaseError.invalidData.errorDescription!
    }
}
