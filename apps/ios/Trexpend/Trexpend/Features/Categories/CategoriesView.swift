import SwiftUI

struct CategoriesView: View {
    let dependencies: AppDependencies
    @State private var catalog: CategoryCatalog?
    @State private var error: String?
    @State private var search = ""
    @State private var filter = Filter.active
    @State private var expanded: Set<Int64> = []
    @State private var presentation: Destination?
    private enum Filter: String, CaseIterable { case active = "Active", hidden = "Hidden", all = "All" }
    private enum Destination: Identifiable {
        case editor(Int64?, Int64?), reorder(Int64?)
        var id: String {
            switch self {
            case .editor(let id, let parent): "edit-" + String(id ?? -1) + "-" + String(parent ?? -1)
            case .reorder(let parent): "order-" + String(parent ?? -1)
            }
        }
    }
    private struct Key: Equatable { let generation: UUID?; let revision: UInt64 }
    private var key: Key { Key(generation: dependencies.session.snapshot?.generation, revision: dependencies.session.transactionRevision) }
    private var matchingIDs: Set<Int64> {
        Set((catalog?.categories ?? []).filter {
            (filter == .all || $0.active == (filter == .active)) && (search.isEmpty || $0.path.localizedCaseInsensitiveContains(search))
        }.map(\.id))
    }
    private var includedIDs: Set<Int64> {
        guard let catalog else { return [] }
        let matches = matchingIDs
        let indexed = Dictionary(uniqueKeysWithValues: catalog.categories.map { ($0.id, $0) })
        var included = matches
        for id in matches {
            var parent = indexed[id]?.parentID
            while let id = parent, let node = indexed[id], included.insert(id).inserted { parent = node.parentID }
        }
        return included
    }
    private var visible: [ManagedCategory] {
        guard let catalog else { return [] }
        let included = includedIDs
        let indexed = Dictionary(uniqueKeysWithValues: catalog.categories.map { ($0.id, $0) })
        return catalog.categories.filter { item in
            guard included.contains(item.id) else { return false }
            if !search.isEmpty { return true }
            var parent = item.parentID
            while let id = parent, let node = indexed[id] {
                guard expanded.contains(id) else { return false }
                parent = node.parentID
            }
            return true
        }
    }
    var body: some View {
        Group {
            if dependencies.session.snapshot == nil { DatabaseStatusView(session: dependencies.session) }
            else if catalog != nil {
                List {
                    Section {
                        Picker("Visibility", selection: $filter) {
                            ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    if visible.isEmpty {
                        ContentUnavailableView("No categories", systemImage: "square.grid.2x2", description: Text("Add a category or change the search and visibility filter."))
                    }
                    Section {
                        ForEach(visible) { category in row(category) }
                    } header: {
                        HStack { Text("Categories"); Spacer(); Text("Transactions") }
                    } footer: { Text("Counts show transactions assigned directly to each category.") }
                }.searchable(text: $search).refreshable { await load() }
            } else if let error {
                ContentUnavailableView {
                    Label("Could not load categories", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: { Button("Retry") { Task { await load() } } }
            } else { ProgressView("Loading categories") }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reorder", systemImage: "arrow.up.arrow.down") { presentation = .reorder(nil) }
                    .disabled(catalog == nil || dependencies.session.isBusy)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add category", systemImage: "plus") { presentation = .editor(nil, nil) }
                    .disabled(dependencies.session.snapshot == nil || dependencies.session.isBusy)
            }
        }
        .fullScreenCover(item: $presentation) { destination in
            if let generation = dependencies.session.snapshot?.generation {
                switch destination {
                case .editor(let id, let parent):
                    CategoryEditorView(dependencies: dependencies, generation: generation, categoryID: id, parentID: parent)
                case .reorder(let parent):
                    CategoryReorderView(dependencies: dependencies, generation: generation, parentID: parent)
                }
            }
        }
        .task(id: key) { await load() }
    }

    private func row(_ category: ManagedCategory) -> some View {
        HStack(spacing: 8) {
            Button { presentation = .editor(category.id, nil) } label: {
                HStack(spacing: 10) {
                    CategoryIconView(symbol: category.symbol, color: .accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(category.name.isEmpty ? "Unnamed category" : category.name).foregroundStyle(.primary)
                            if category.favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).accessibilityLabel("Favorite") }
                        }
                        if !matchingIDs.contains(category.id) { Text("Parent group").font(.caption).foregroundStyle(.secondary) }
                        if !category.active { Text("Hidden").font(.caption).foregroundStyle(.secondary) }
                        if category.childCount > 0 { Text(String(category.childCount) + " subcategories").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 4)
                    Text(String(category.directCount)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(.quaternary, in: Capsule())
                        .accessibilityLabel(String(category.directCount) + " direct transactions")
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if search.isEmpty, catalog?.categories.contains(where: { $0.parentID == category.id && includedIDs.contains($0.id) }) == true {
                Button {
                    if expanded.contains(category.id) { expanded.remove(category.id) } else { expanded.insert(category.id) }
                } label: {
                    Image(systemName: expanded.contains(category.id) ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).frame(width: 36, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel((expanded.contains(category.id) ? "Collapse " : "Expand ") + category.name)
            }
        }
        .padding(.leading, CGFloat(min(category.depth, 4)) * 12)
        .contextMenu {
            Button("Add subcategory", systemImage: "plus") { presentation = .editor(nil, category.id) }
            if category.childCount > 0 {
                Button("Reorder subcategories", systemImage: "arrow.up.arrow.down") { presentation = .reorder(category.id) }
            }
        }
    }

    private func load() async {
        let requested = key
        guard let generation = requested.generation else { catalog = nil; return }
        do {
            let result = try await dependencies.database.categoryCatalog(expectedGeneration: generation)
            guard !Task.isCancelled, key == requested else { return }
            catalog = result; error = nil
        } catch {
            guard !Task.isCancelled, key == requested else { return }
            catalog = nil; self.error = error.localizedDescription
        }
    }
}
