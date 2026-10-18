import Observation

@MainActor
@Observable
final class SettingsStore {
    private(set) var values: DatasetSettings?

    func load(_ snapshot: DatabaseSnapshot) { values = snapshot.settings }
    func clear() { values = nil }
}
