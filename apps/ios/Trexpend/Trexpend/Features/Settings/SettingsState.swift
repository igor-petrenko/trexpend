import Foundation
import Observation

@MainActor
@Observable
final class SettingsState {
    private let dependencies: AppDependencies
    var pendingImport: URL?
    var message: String?
    var exportRequest: DatabaseExportRequest?
    private var activeExport: URL?
    private var exportOutcome: Bool?
    private var exporterHasDismissed = false

    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    func importSelected(source: URL) async {
        let generation = dependencies.session.snapshot?.generation
        guard dependencies.session.beginOperation(allowsUnavailable: true) else { return }
        pendingImport = nil
        defer { dependencies.session.endOperation() }
        do {
            let snapshot = try await dependencies.files.importDatabase(from: source, expectedGeneration: generation)
            dependencies.session.publish(snapshot, settings: dependencies.settings)
        } catch {
            dependencies.session.handleRecoveryFailure(error, settings: dependencies.settings)
            message = AppSession.message(for: error)
        }
    }
    func exportCopy() async {
        guard let generation = dependencies.session.snapshot?.generation,
              dependencies.session.beginOperation() else { return }
        do {
            let url = try await dependencies.database.exportSnapshot(expectedGeneration: generation)
            activeExport = url
            exportRequest = DatabaseExportRequest(url: url)
            exportOutcome = nil
            exporterHasDismissed = false
        } catch {
            dependencies.session.endOperation()
            message = AppSession.message(for: error)
        }
    }

    func finishExport(saved: Bool) {
        guard activeExport != nil else { return }
        exportOutcome = saved
        exportRequest = nil
        completeExportIfDismissed()
    }

    func exporterDismissed() {
        exporterHasDismissed = true
        completeExportIfDismissed()
    }

    private func completeExportIfDismissed() {
        guard exporterHasDismissed, let saved = exportOutcome, let url = activeExport else { return }
        activeExport = nil
        exportOutcome = nil
        Task {
            do { try await dependencies.database.discardExport(url) }
            catch { if !saved { message = DatabaseError.fileAccess.errorDescription } }
            dependencies.session.endOperation()
            if saved { message = "Database copy saved." }
        }
    }

    func reset() async {
        let generation = dependencies.session.snapshot?.generation
        guard dependencies.session.beginOperation(allowsUnavailable: true) else { return }
        defer { dependencies.session.endOperation() }
        do {
            let snapshot = try await dependencies.database.reset(expectedGeneration: generation)
            dependencies.session.publish(snapshot, settings: dependencies.settings)
        } catch {
            dependencies.session.handleRecoveryFailure(error, settings: dependencies.settings)
            message = AppSession.message(for: error)
        }
    }
}
