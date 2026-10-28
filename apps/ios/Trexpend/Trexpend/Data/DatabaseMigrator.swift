import Foundation

nonisolated enum DatabaseMigrator {
    private struct IconDefault: Decodable { let path: [String]; let code: String }

    static func version(_ db: SQLiteConnection) throws -> Int64 {
        guard try db.rows("PRAGMA application_id")[0].integer("application_id") == 0x54525850 else { throw DatabaseError.invalidDatabase }
        let version = try db.rows("PRAGMA user_version")[0].integer("user_version")
        guard version == 1 || version == 2 else { throw DatabaseError.unsupportedVersion }
        return version
    }

    static func upgrade(_ db: SQLiteConnection, resources: DatabaseResources) throws {
        guard try version(db) == 1 else { return }
        guard !resources.migration.isEmpty else { throw DatabaseError.missingResource }
        try db.transaction {
            try db.execute(resources.migration)
            let mappings = try JSONDecoder().decode([IconDefault].self, from: resources.iconDefaults)
            var categories: [Int64: (String, Int64?)] = [:]
            for row in try db.rows("SELECT id,name,parent_id FROM categories") {
                categories[try row.integer("id")] = (try row.text("name"), try row.optionalInteger("parent_id"))
            }
            var paths: [[String]: [Int64]] = [:]
            for id in categories.keys {
                var path: [String] = [], seen: Set<Int64> = [], current: Int64? = id
                while let node = current {
                    guard seen.insert(node).inserted, let item = categories[node] else { throw DatabaseError.invalidData }
                    path.insert(item.0, at: 0); current = item.1
                }
                paths[path, default: []].append(id)
            }
            var icons: [String: Int64] = [:]
            for row in try db.rows("SELECT id,code FROM category_icons") { icons[try row.text("code")] = try row.integer("id") }
            for mapping in mappings {
                guard let ids = paths[mapping.path], ids.count == 1 else { continue }
                guard let icon = icons[mapping.code] else { throw DatabaseError.invalidData }
                try db.run("UPDATE categories SET icon_id=? WHERE id=? AND icon_id IS NULL", parameters: [.integer(icon), .integer(ids[0])])
            }
            try db.execute("PRAGMA user_version = 2")
        }
    }
}
