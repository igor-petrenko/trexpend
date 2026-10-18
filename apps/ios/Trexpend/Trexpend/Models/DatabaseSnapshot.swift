import Foundation

nonisolated struct DatasetSettings: Equatable, Sendable {
    let displayCurrencyID: Int64
    let displayCurrencyCode: String
    let defaultAccountID: Int64?
    let userName: String?
}

nonisolated struct DatabaseSnapshot: Equatable, Sendable {
    let generation: UUID
    let settings: DatasetSettings
    let accountCount: Int64
    let transactionCount: Int64
}

nonisolated struct DatabaseResources: Sendable {
    let schema: String
    let defaults: String

    static func bundled() throws -> Self {
        guard let schemaURL = Bundle.main.url(forResource: "001_initial", withExtension: "sql"),
              let defaultsURL = Bundle.main.url(forResource: "001_defaults", withExtension: "sql") else { throw DatabaseError.missingResource }
        return try Self(schema: String(contentsOf: schemaURL, encoding: .utf8), defaults: String(contentsOf: defaultsURL, encoding: .utf8))
    }
}
