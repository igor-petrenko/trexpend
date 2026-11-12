import Foundation

nonisolated enum CategoryRead {
    static func orderedRows(_ db: SQLiteConnection, parentID: Int64?) throws -> [SQLRow] {
        try db.rows("SELECT * FROM categories WHERE parent_id IS ? ORDER BY sort_order,name,id", parameters: [parentID.map(SQLValue.integer) ?? .null])
    }

    static func catalog(_ db: SQLiteConnection, generation: UUID, includeUsage: Bool = true) throws -> CategoryCatalog {
        let icons = try db.rows("SELECT id,name,system_name FROM category_icons ORDER BY name,id").map {
            try CategoryIcon(id: $0.integer("id"), name: $0.text("name"), symbol: $0.text("system_name"))
        }
        let symbols = Dictionary(uniqueKeysWithValues: icons.map { ($0.id, $0.symbol) })
        let rows = try db.rows("SELECT * FROM categories ORDER BY sort_order,name,id")
        var grouped: [Int64?: [SQLRow]] = [:]
        for row in rows { grouped[try row.optionalInteger("parent_id"), default: []].append(row) }
        var direct: [Int64: Int64] = [:]
        if includeUsage {
            for row in try db.rows("SELECT category_id,count(*) AS n FROM transactions GROUP BY category_id") {
                direct[try row.integer("category_id")] = try row.integer("n")
            }
        }
        var stack: [(SQLRow, Int, String)] = (grouped[nil] ?? []).reversed().map { ($0, 0, "") }
        var ordered: [(SQLRow, Int, String)] = []
        var seen: Set<Int64> = []
        while let (row, depth, parentPath) = stack.popLast() {
            let id = try row.integer("id")
            guard seen.insert(id).inserted else { throw DatabaseError.invalidData }
            let name = try row.text("name")
            let path = parentPath.isEmpty ? name : parentPath + " > " + name
            ordered.append((row, depth, path))
            for child in (grouped[id] ?? []).reversed() { stack.append((child, depth + 1, path)) }
        }
        guard seen.count == rows.count else { throw DatabaseError.invalidData }
        var totals = direct
        for (row, _, _) in ordered.reversed() {
            if let parent = try row.optionalInteger("parent_id") {
                let (value, overflow) = totals[parent, default: 0].addingReportingOverflow(totals[try row.integer("id"), default: 0])
                guard !overflow else { throw DatabaseError.invalidData }
                totals[parent] = value
            }
        }
        let categories = try ordered.map { row, depth, path in
            let id = try row.integer("id"), icon = try row.optionalInteger("icon_id")
            return try ManagedCategory(id: id, name: row.text("name"), parentID: row.optionalInteger("parent_id"), active: row.integer("is_active") == 1,
                favorite: row.integer("favorite") == 1, iconID: icon, symbol: icon.flatMap { symbols[$0] }, sortOrder: row.integer("sort_order"),
                path: path, depth: depth, directCount: direct[id, default: 0], subtreeCount: totals[id, default: 0], childCount: grouped[id]?.count ?? 0)
        }
        return CategoryCatalog(generation: generation, categories: categories, icons: icons)
    }

    static func editor(_ db: SQLiteConnection, id: Int64?, generation: UUID) throws -> CategoryEditorContext {
        let original: SQLRow?
        if let id {
            guard let row = try db.rows("SELECT * FROM categories WHERE id=?", parameters: [.integer(id)]).first else { throw CategoryError.changed }
            original = row
        } else { original = nil }
        return try CategoryEditorContext(generation: generation, original: original, catalog: catalog(db, generation: generation))
    }

    static func reorder(_ db: SQLiteConnection, parentID: Int64?, generation: UUID) throws -> CategoryReorderContext {
        if let parentID {
            guard try !db.rows("SELECT id FROM categories WHERE id=?", parameters: [.integer(parentID)]).isEmpty else { throw CategoryError.parent }
        }
        return try CategoryReorderContext(generation: generation, parentID: parentID, originals: orderedRows(db, parentID: parentID), catalog: catalog(db, generation: generation))
    }
}
