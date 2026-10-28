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
    var migration: String = ""
    var iconDefaults: Data = Data("[]".utf8)

    static func bundled() throws -> Self {
        guard let schemaURL = Bundle.main.url(forResource: "001_initial", withExtension: "sql"),
              let defaultsURL = Bundle.main.url(forResource: "001_defaults", withExtension: "sql"),
              let migrationURL = Bundle.main.url(forResource: "002_category_icons_and_history", withExtension: "sql"),
              let iconsURL = Bundle.main.url(forResource: "002_category_icon_defaults", withExtension: "json") else { throw DatabaseError.missingResource }
        return try Self(schema: String(contentsOf: schemaURL, encoding: .utf8), defaults: String(contentsOf: defaultsURL, encoding: .utf8), migration: String(contentsOf: migrationURL, encoding: .utf8), iconDefaults: Data(contentsOf: iconsURL))
    }
}
