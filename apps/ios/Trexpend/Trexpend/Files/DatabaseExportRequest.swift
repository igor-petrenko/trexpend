import Foundation

nonisolated struct DatabaseExportRequest: Identifiable, Sendable {
    let id = UUID()
    let url: URL
}
