import Foundation

nonisolated enum CategoryWrite {
    private static func checkOriginal(_ db: SQLiteConnection, context: CategoryEditorContext) throws {
        if let original = context.original {
            guard let row = try db.rows("SELECT * FROM categories WHERE id=?", parameters: [.integer(original.integer("id"))]).first,
                  row.values == original.values else { throw CategoryError.changed }
        }
    }

    static func save(_ db: SQLiteConnection, draft: CategoryDraft, context: CategoryEditorContext) throws {
        try checkOriginal(db, context: context)
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CategoryError.name }
        let id = try context.original?.integer("id")
        var seen: Set<Int64> = id.map { [$0] } ?? []
        var current = draft.parentID
        while let parent = current {
            guard seen.insert(parent).inserted,
                  let row = try db.rows("SELECT parent_id FROM categories WHERE id=?", parameters: [.integer(parent)]).first else { throw CategoryError.parent }
            current = try row.optionalInteger("parent_id")
        }
        if let icon = draft.iconID {
            guard try !db.rows("SELECT id FROM category_icons WHERE id=?", parameters: [.integer(icon)]).isEmpty else { throw DatabaseError.invalidData }
        }
        let oldParent = try context.original?.optionalInteger("parent_id")
        let order: Int64
        if let original = context.original, oldParent == draft.parentID { order = try original.integer("sort_order") }
        else {
            let maximum = try db.rows("SELECT max(sort_order) AS n FROM categories WHERE parent_id IS ?", parameters: [draft.parentID.map(SQLValue.integer) ?? .null])[0].optionalInteger("n") ?? -1
            guard maximum < Int64.max else { throw DatabaseError.invalidData }
            order = maximum + 1
        }
        var values: [SQLValue] = [.text(draft.name), draft.parentID.map(SQLValue.integer) ?? .null, draft.iconID.map(SQLValue.integer) ?? .null,
            .integer(draft.favorite ? 1 : 0), .integer(draft.active ? 1 : 0), .integer(order)]
        if let id {
            values.append(.integer(id))
            try db.run("UPDATE categories SET name=?,parent_id=?,icon_id=?,favorite=?,is_active=?,sort_order=? WHERE id=?", parameters: values)
        } else {
            try db.run("INSERT INTO categories(name,parent_id,icon_id,favorite,is_active,sort_order) VALUES (?,?,?,?,?,?)", parameters: values)
        }
    }

    static func delete(_ db: SQLiteConnection, context: CategoryEditorContext) throws {
        guard let original = context.original else { throw CategoryError.changed }
        try checkOriginal(db, context: context)
        let id = try original.integer("id")
        guard try db.rows("SELECT id FROM transactions WHERE category_id=? LIMIT 1", parameters: [.integer(id)]).isEmpty else { throw CategoryError.used }
        guard try db.rows("SELECT id FROM categories WHERE parent_id=? LIMIT 1", parameters: [.integer(id)]).isEmpty else { throw CategoryError.children }
        try db.run("DELETE FROM categories WHERE id=?", parameters: [.integer(id)])
    }

    static func reorder(_ db: SQLiteConnection, ids: [Int64], context: CategoryReorderContext) throws {
        let expected = try context.originals.map { try $0.integer("id") }
        guard ids.count == expected.count, Set(ids) == Set(expected),
              try CategoryRead.orderedRows(db, parentID: context.parentID).map(\.values) == context.originals.map(\.values) else { throw CategoryError.changed }
        if let parent = context.parentID {
            guard try !db.rows("SELECT id FROM categories WHERE id=?", parameters: [.integer(parent)]).isEmpty else { throw CategoryError.changed }
        }
        for (position, id) in ids.enumerated() {
            try db.run("UPDATE categories SET sort_order=? WHERE id=?", parameters: [.integer(Int64(position)), .integer(id)])
        }
    }
}
