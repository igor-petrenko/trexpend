import Foundation

@MainActor
final class AppDependencies {
    let backupDirectory: URL
    let database: DatabaseStore
    let files: DatabaseFileCoordinator
    let settings = SettingsStore()
    let session = AppSession()

    init(directory: URL? = nil) {
        let root = directory ?? URL.applicationSupportDirectory.appendingPathComponent("Trexpend", isDirectory: true)
        backupDirectory = directory?.appendingPathComponent("Backups") ?? URL.documentsDirectory.appendingPathComponent("Backups", isDirectory: true)
        database = DatabaseStore(directory: root)
        files = DatabaseFileCoordinator(store: database)
    }

    func start() async {
        await session.start(store: database, settings: settings)
        await session.backUpIfNeeded(store: database, folder: backupDirectory)
    }
}
