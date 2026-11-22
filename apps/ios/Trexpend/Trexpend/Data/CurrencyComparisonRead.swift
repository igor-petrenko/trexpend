import Foundation

nonisolated enum CurrencyComparisonRead {
    static func ids(_ db: SQLiteConnection) throws -> [Int64] {
        let available = Set(try db.rows("SELECT id FROM currencies").map { try $0.integer("id") })
        return try db.rows("SELECT currency_id,sort_order FROM currency_comparison_currencies ORDER BY sort_order,currency_id").map { row in
            let id = try row.integer("currency_id")
            guard id > 0, available.contains(id), try row.integer("sort_order") >= 0 else { throw DatabaseError.invalidData }
            return id
        }
    }
}

nonisolated enum CurrencyComparisonWrite {
    static func save(_ db: SQLiteConnection, ids: [Int64], original: [Int64]) throws {
        guard try CurrencyComparisonRead.ids(db) == original else { throw CurrencyComparisonError.changed }
        let available = Set(try db.rows("SELECT id FROM currencies").map { try $0.integer("id") })
        guard Set(ids).count == ids.count, ids.allSatisfy({ $0 > 0 && available.contains($0) }) else { throw CurrencyComparisonError.invalidSelection }
        try db.run("DELETE FROM currency_comparison_currencies")
        for (index, id) in ids.enumerated() {
            try db.run("INSERT INTO currency_comparison_currencies(currency_id,sort_order) VALUES(?,?)", parameters: [.integer(id), .integer(Int64(index))])
        }
    }
}

nonisolated enum CurrencyComparisonError: Error, LocalizedError {
    case invalidSelection, changed
    var errorDescription: String? {
        switch self {
        case .invalidSelection: "Choose valid currencies without duplicates."
        case .changed: "The comparison currencies changed. Reopen the selection and try again."
        }
    }
}
