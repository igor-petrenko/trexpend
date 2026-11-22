import Foundation

@MainActor
final class AppDependencies {
    let backupDirectory: URL
    let database: DatabaseStore
    let files: DatabaseFileCoordinator
    let settings = SettingsStore()
    let session = AppSession()
    let rates: CurrencyRefreshCoordinator

    init(directory: URL? = nil, rates: CurrencyRefreshCoordinator? = nil) {
        self.rates = rates ?? CurrencyRefreshCoordinator()
        let root = directory ?? URL.applicationSupportDirectory.appendingPathComponent("Trexpend", isDirectory: true)
        backupDirectory = directory?.appendingPathComponent("Backups") ?? URL.documentsDirectory.appendingPathComponent("Backups", isDirectory: true)
        database = DatabaseStore(directory: root)
        files = DatabaseFileCoordinator(store: database)
    }

    func start() async {
        await session.start(store: database, settings: settings)
        Task { await rates.refresh(dependencies: self) }
        await session.backUpIfNeeded(store: database, folder: backupDirectory)
    }
}
