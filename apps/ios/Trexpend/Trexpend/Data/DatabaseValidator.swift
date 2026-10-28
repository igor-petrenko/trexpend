import Foundation

nonisolated final class DatabaseValidator {
    private let timestampFormatter = ISO8601DateFormatter()
    private let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let expectedSchema: [Int64: [[String: SQLValue]]]
    private static let schemaQuery = "SELECT type, name, tbl_name, sql FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"

    init(resources: DatabaseResources) throws {
        let reference = try SQLiteConnection(url: nil, create: true)
        try reference.execute(resources.schema)
        let v1 = try reference.rows(Self.schemaQuery).map(\.values)
        if !resources.migration.isEmpty { try reference.execute(resources.migration) }
        expectedSchema = try [1: v1, 2: reference.rows(Self.schemaQuery).map(\.values)]
        try reference.close()
    }

    func validate(_ db: SQLiteConnection, generation: UUID) throws -> DatabaseSnapshot {
        try db.withValidationBudget { try validateContents(db, generation: generation) }
    }

    private func validateContents(_ db: SQLiteConnection, generation: UUID) throws -> DatabaseSnapshot {
        try checkSchema(db)
        guard try db.rows("PRAGMA integrity_check").map({ try $0.text("integrity_check") }) == ["ok"],
              try db.rows("PRAGMA foreign_key_check").isEmpty else { throw DatabaseError.invalidDatabase }
        var currencies: [Int64: Int] = [:]
        try db.forEach("SELECT id, code, decimal_places FROM currencies") { row in
            let id = try row.integer("id")
            let scale = try row.integer("decimal_places")
            guard id > 0, (0...18).contains(scale), !(try row.text("code")).isEmpty else { throw DatabaseError.invalidData }
            currencies[id] = Int(scale)
        }
        var accounts: [Int64: Int64] = [:]
        try db.forEach("SELECT * FROM accounts") { row in
            let id = try row.integer("id")
            let currencyID = try row.integer("currency_id")
            guard id > 0, let places = currencies[currencyID] else { throw DatabaseError.invalidData }
            accounts[id] = currencyID
            _ = try MoneyCodec.decode(row.text("initial_balance"), places: places, signed: true)
            if let limit = try row.optionalText("credit_limit") { _ = try MoneyCodec.decode(limit, places: places) }
            for field in ["open_date", "exp_date", "close_date"] {
                if let day = try row.optionalText(field) {
                    guard day.count == 10 else { throw DatabaseError.invalidData }
                    _ = try LocalDateTime(storage: day + "T00:00:00")
                }
            }
            try timestamp(row.text("created_at"), utc: true)
            try timestamp(row.text("updated_at"), utc: true)
        }
        try categories(db)
        try db.forEach("SELECT * FROM transactions") { row in
            guard try row.integer("id") > 0,
                  let sourceCurrency = accounts[try row.integer("account_id")],
                  let sourcePlaces = currencies[sourceCurrency] else { throw DatabaseError.invalidData }
            _ = try MoneyCodec.decode(row.text("amount"), places: sourcePlaces)
            _ = try LocalDateTime(storage: row.text("date"))
            if let offset = try row.optionalText("date_with_offset") { try timestamp(offset, utc: false) }
            try timestamp(row.text("created_at"), utc: true)
            try timestamp(row.text("updated_at"), utc: true)
            if try row.integer("transaction_type") == 3 {
                guard let destination = try row.optionalInteger("to_account_id"), let destinationCurrency = accounts[destination],
                      let destinationPlaces = currencies[destinationCurrency],
                      let feeAccount = try row.optionalInteger("fee_account_id"), let feeCurrency = accounts[feeAccount],
                      let feePlaces = currencies[feeCurrency] else { throw DatabaseError.invalidData }
                _ = try MoneyCodec.decode(row.text("to_amount"), places: destinationPlaces)
                _ = try MoneyCodec.decode(row.text("fee"), places: feePlaces)
            } else {
                _ = try MoneyCodec.decode(row.text("fee"), places: sourcePlaces)
            }
        }
        try db.forEach("SELECT * FROM exchange_rates") { row in
            guard try row.integer("id") > 0 else { throw DatabaseError.invalidData }
            _ = try MoneyCodec.decodeRate(row.text("rate"))
            try timestamp(row.text("updated_at"), utc: true)
        }
        return try snapshot(db, generation: generation)
    }

    // Working data was validated before publication. Opening reads only schema,
    // references, settings, and counts; full history audits belong to import/export.
    func snapshot(_ db: SQLiteConnection, generation: UUID) throws -> DatabaseSnapshot {
        try checkSchema(db)
        let settingsRows = try db.rows("SELECT s.*, c.code FROM app_settings s JOIN currencies c ON c.id=s.display_currency_id")
        guard settingsRows.count == 1, let row = settingsRows.first, try row.integer("id") == 1 else { throw DatabaseError.invalidData }
        let settings = try DatasetSettings(displayCurrencyID: row.integer("display_currency_id"), displayCurrencyCode: row.text("code"),
                                           defaultAccountID: row.optionalInteger("default_account_id"), userName: row.optionalText("user_name"))
        return try DatabaseSnapshot(generation: generation, settings: settings,
                                    accountCount: count(db, table: "accounts"), transactionCount: count(db, table: "transactions"))
    }

    private func checkSchema(_ db: SQLiteConnection) throws {
        guard try db.rows("PRAGMA application_id").first?.integer("application_id") == 0x54525850 else { throw DatabaseError.invalidDatabase }
        let version = try DatabaseMigrator.version(db)
        // V1 accepts the canonical schema, including constraints and triggers,
        // not an arbitrary database that merely uses the same table names.
        guard try db.rows(Self.schemaQuery).map(\.values) == expectedSchema[version] else { throw DatabaseError.invalidDatabase }
        try references(db)
        if version == 2 {
            for row in try db.rows("SELECT id,code,name,system_name FROM category_icons") {
                guard try row.integer("id") > 0, !(try row.text("code")).isEmpty, !(try row.text("name")).isEmpty, !(try row.text("system_name")).isEmpty else { throw DatabaseError.invalidData }
            }
        }
    }

    private func count(_ db: SQLiteConnection, table: String) throws -> Int64 {
        // Callers supply fixed internal table names, never user input.
        guard let row = try db.rows("SELECT count(*) AS n FROM " + table).first else { throw DatabaseError.invalidData }
        return try row.integer("n")
    }

    private func references(_ db: SQLiteConnection) throws {
        let expected = ["transaction_types": ["1:expense", "2:income", "3:transfer"],
                        "account_statuses": ["1:open", "2:closed"],
                        "account_types": ["1:checking", "2:credit_card", "3:cash", "4:deposit"]]
        for (table, values) in expected {
            let actual = try db.rows("SELECT id, code FROM " + table + " ORDER BY id").map { try String($0.integer("id")) + ":" + $0.text("code") }
            guard actual == values else { throw DatabaseError.invalidData }
        }
        let images = try db.rows("SELECT id, source, asset_name FROM account_images ORDER BY id")
        let assets = ["account_checking", "account_credit_card", "account_cash", "account_deposit"]
        guard images.count == assets.count else { throw DatabaseError.invalidData }
        for (offset, row) in images.enumerated() {
            guard try row.integer("id") == offset + 1, try row.text("source") == "built_in",
                  try row.text("asset_name") == assets[offset] else { throw DatabaseError.invalidData }
        }
    }

    private func categories(_ db: SQLiteConnection) throws {
        var parents: [Int64: Int64] = [:]
        for row in try db.rows("SELECT id, parent_id FROM categories") {
            let id = try row.integer("id")
            guard id > 0 else { throw DatabaseError.invalidData }
            if let parent = try row.optionalInteger("parent_id") { parents[id] = parent }
        }
        var done: Set<Int64> = []
        for id in parents.keys {
            try db.checkBudget()
            var path: Set<Int64> = []
            var current: Int64? = id
            while let node = current, !done.contains(node) {
                guard path.insert(node).inserted else { throw DatabaseError.invalidData }
                current = parents[node]
            }
            done.formUnion(path)
        }
    }

    private func timestamp(_ value: String, utc: Bool) throws {
        let suffix = utc ? "Z" : "[+-][0-9]{2}:[0-9]{2}"
        guard value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]{1,9})?" + suffix + "$", options: .regularExpression) == value.startIndex..<value.endIndex else { throw DatabaseError.invalidData }
        _ = try LocalDateTime(storage: String(value.prefix(19)))
        let formatter = value.contains(".") ? fractionalTimestampFormatter : timestampFormatter
        guard formatter.date(from: value) != nil else { throw DatabaseError.invalidData }
        if !utc {
            let offset = value.suffix(6)
            guard let hours = Int(offset.dropFirst().prefix(2)), let minutes = Int(offset.suffix(2)),
                  hours <= 14, minutes < 60, hours < 14 || minutes == 0 else { throw DatabaseError.invalidData }
        }
    }
}
