import SwiftUI

struct CategoryPickerView: View {
    let categories: [EditorCategory]
    let selectableIDs: Set<Int64>
    let selected: Int64?
    let choose: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private func path(_ category: EditorCategory) -> String {
        var names = [category.name]; var parent = category.parentID; var seen: Set<Int64> = [category.id]
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        while let id = parent, seen.insert(id).inserted, let node = byID[id] {
            names.insert(node.name, at: 0); parent = node.parentID
        }
        return names.joined(separator: " > ")
    }
    private var visibleCategories: [EditorCategory] {
        var visible = selectableIDs
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        for category in categories where selectableIDs.contains(category.id) {
            var parent = category.parentID
            var seen: Set<Int64> = [category.id]
            while let id = parent, seen.insert(id).inserted, let node = byID[id] {
                visible.insert(id); parent = node.parentID
            }
        }
        return categories.filter { visible.contains($0.id) }
    }
    private func select(_ id: Int64) { choose(id); dismiss() }
    var body: some View {
        List {
            if !search.isEmpty {
                ForEach(categories.filter { selectableIDs.contains($0.id) && path($0).localizedCaseInsensitiveContains(search) }) { category in
                    Button { select(category.id) } label: {
                        CategoryChoiceLabel(category: category, title: path(category), selected: selected == category.id)
                    }
                }
            } else {
                let favorites = categories.filter { $0.favorite && selectableIDs.contains($0.id) }
                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { category in
                            Button { select(category.id) } label: {
                                CategoryChoiceLabel(category: category, title: path(category), selected: selected == category.id)
                            }
                        }
                    }
                }
                Section("Categories") {
                    let ids = Set(visibleCategories.map(\.id))
                    ForEach(visibleCategories.filter { $0.parentID == nil || !ids.contains($0.parentID!) }) { category in
                        CategoryBranch(category: category, categories: visibleCategories, selectableIDs: selectableIDs, selected: selected, visited: [], choose: select)
                    }
                }
            }
        }.navigationTitle("Category").searchable(text: $search)
    }
}

private struct CategoryBranch: View {
    let category: EditorCategory
    let categories: [EditorCategory]
    let selectableIDs: Set<Int64>
    let selected: Int64?
    let visited: Set<Int64>
    let choose: (Int64) -> Void
    var body: some View {
        let seen = visited.union([category.id])
        let children = categories.filter { $0.parentID == category.id && !seen.contains($0.id) }
        if children.isEmpty { row }
        else {
            DisclosureGroup {
                ForEach(children) { child in
                    CategoryBranch(category: child, categories: categories, selectableIDs: selectableIDs, selected: selected, visited: seen, choose: choose)
                }
            } label: { row }
        }
    }
    private var row: some View {
        Button { choose(category.id) } label: {
            CategoryChoiceLabel(category: category, title: category.name, selected: selected == category.id)
        }.disabled(!selectableIDs.contains(category.id))
    }
}


private struct CategoryChoiceLabel: View {
    let category: EditorCategory
    let title: String
    let selected: Bool
    var body: some View {
        HStack(spacing: 10) {
            CategoryIconView(symbol: category.symbol, color: .accentColor)
            VStack(alignment: .leading) {
                Text(title).foregroundStyle(.primary)
                if !category.active { Text("Hidden").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if category.favorite { Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityLabel("Favorite") }
            if selected { Image(systemName: "checkmark") }
        }
    }
}
