import Foundation

nonisolated struct CategoryIcon: Identifiable, Equatable, Sendable {
    let id: Int64
    let name: String
    let symbol: String
}

nonisolated struct ManagedCategory: Identifiable, Equatable, Sendable {
    let id: Int64
    let name: String
    let parentID: Int64?
    let active: Bool
    let favorite: Bool
    let iconID: Int64?
    let symbol: String?
    let sortOrder: Int64
    let path: String
    let depth: Int
    let directCount: Int64
    let subtreeCount: Int64
    let childCount: Int
}

nonisolated struct CategoryCatalog: Sendable {
    let generation: UUID
    let categories: [ManagedCategory]
    let icons: [CategoryIcon]

    func descendants(of id: Int64) -> Set<Int64> {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return [] }
        let depth = categories[index].depth
        return Set(categories.dropFirst(index + 1).prefix { $0.depth > depth }.map(\.id))
    }
}

nonisolated struct CategoryDraft: Equatable, Sendable {
    var name = ""
    var parentID: Int64? = nil
    var iconID: Int64? = nil
    var favorite = false
    var active = true

    static func editing(_ row: SQLRow) throws -> Self {
        try Self(name: row.text("name"), parentID: row.optionalInteger("parent_id"), iconID: row.optionalInteger("icon_id"),
                 favorite: row.integer("favorite") == 1, active: row.integer("is_active") == 1)
    }
}

nonisolated struct CategoryEditorContext: Sendable {
    let generation: UUID
    let original: SQLRow?
    let catalog: CategoryCatalog
}

nonisolated struct CategoryReorderContext: Sendable {
    let generation: UUID
    let parentID: Int64?
    let originals: [SQLRow]
    let catalog: CategoryCatalog
}

nonisolated enum CategoryError: Error, LocalizedError {
    case name, parent, used, children, changed
    var errorDescription: String? {
        switch self {
        case .name: "Enter a category name."
        case .parent: "Choose a valid parent outside this category's descendants."
        case .used: "This category has transactions. Hide it instead of deleting it."
        case .children: "Move or delete all subcategories before deleting this category."
        case .changed: "The category or sibling list changed. Reopen it before saving."
        }
    }
}
