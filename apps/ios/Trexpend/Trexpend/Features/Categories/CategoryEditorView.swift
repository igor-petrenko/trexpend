import SwiftUI

struct CategoryEditorView: View {
    let dependencies: AppDependencies
    let generation: UUID
    var categoryID: Int64? = nil
    var parentID: Int64? = nil
    @State private var state = CategoryEditorState()
    @State private var showsDiscard = false
    @State private var showsDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let context = state.context { form(context) }
                else if state.isLoading { ProgressView("Loading category") }
                else {
                    ContentUnavailableView {
                        Label("Could not load category", systemImage: "exclamationmark.triangle")
                    } description: { Text(state.error ?? "Try opening the category again.") }
                    actions: { Button("Retry") { Task { await load() } } }
                }
            }
            .navigationTitle(categoryID == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if state.isDirty { showsDiscard = true } else { dismiss() } }.disabled(state.isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { if await state.save(dependencies: dependencies) { dismiss() } }
                } label: {
                    HStack { if state.isSaving { ProgressView().tint(.white) }; Text("Save").font(.headline) }
                        .frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.borderedProminent).padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
                    .disabled(state.context == nil || state.isSaving || dependencies.session.isBusy)
            }
        }
        .interactiveDismissDisabled(state.isDirty || state.isSaving)
        .alert("Discard changes?", isPresented: $showsDiscard) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Continue editing", role: .cancel) {}
        }
        .alert("Delete category?", isPresented: $showsDelete) {
            Button("Delete category", role: .destructive) {
                Task { if await state.save(dependencies: dependencies, deleting: true) { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This unused category will be permanently deleted.") }
        .alert("Could not complete action", isPresented: Binding(get: { state.error != nil && state.context != nil }, set: { if !$0 { state.error = nil } })) {
            Button("OK", role: .cancel) { state.error = nil }
        } message: { Text(state.error ?? "") }
        .onChange(of: dependencies.session.snapshot?.generation) { _, current in if current != generation { dismiss() } }
        .task { await load() }
    }

    private func form(_ context: CategoryEditorContext) -> some View {
        Form {
            Section("Category") {
                TextField("Name", text: $state.draft.name)
                NavigationLink {
                    CategoryParentPicker(catalog: context.catalog, excluded: state.excludedParents, selected: $state.draft.parentID)
                } label: {
                    LabeledContent("Parent", value: context.catalog.categories.first { $0.id == state.draft.parentID }?.path ?? "None (root category)")
                }
                NavigationLink {
                    CategoryIconPicker(icons: context.catalog.icons, selected: $state.draft.iconID)
                } label: {
                    HStack {
                        Text("Icon")
                        Spacer()
                        CategoryIconView(symbol: context.catalog.icons.first { $0.id == state.draft.iconID }?.symbol, color: .accentColor)
                    }
                }
                Toggle("Favorite", isOn: $state.draft.favorite)
            }
            Section {
                Toggle("Active", isOn: $state.draft.active)
            } footer: { Text("Hidden categories remain in history. Hiding a parent does not hide its subcategories.") }
            if let record = state.record {
                Section("Usage") {
                    LabeledContent("Direct transactions", value: String(record.directCount))
                    LabeledContent("Entire branch", value: String(record.subtreeCount))
                    LabeledContent("Subcategories", value: String(record.childCount))
                }
                Section {
                    if state.canDelete {
                        Button("Delete category", role: .destructive) { showsDelete = true }
                    } else {
                        Text(record.directCount > 0 ? "This category has transactions. Turn off Active to hide it while preserving history." : "Move or delete its subcategories before deleting this category.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.disabled(state.isSaving).scrollDismissesKeyboard(.interactively)
    }
    private func load() async { await state.load(dependencies: dependencies, generation: generation, id: categoryID, parentID: parentID) }
}

private struct CategoryParentPicker: View {
    let catalog: CategoryCatalog
    let excluded: Set<Int64>
    @Binding var selected: Int64?
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Button { selected = nil; dismiss() } label: {
                HStack { Text("None (root category)"); Spacer(); if selected == nil { Image(systemName: "checkmark") } }
            }
            ForEach(catalog.categories.filter { !excluded.contains($0.id) && (search.isEmpty || $0.path.localizedCaseInsensitiveContains(search)) }) { category in
                Button { selected = category.id; dismiss() } label: {
                    HStack(spacing: 10) {
                        CategoryIconView(symbol: category.symbol, color: .accentColor)
                        VStack(alignment: .leading) {
                            Text(category.path).foregroundStyle(.primary)
                            if !category.active { Text("Hidden").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if selected == category.id { Image(systemName: "checkmark") }
                    }
                }
            }
        }.navigationTitle("Parent category").searchable(text: $search)
    }
}

private struct CategoryIconPicker: View {
    let icons: [CategoryIcon]
    @Binding var selected: Int64?
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                tile(id: nil, name: "General (default)", symbol: nil)
                ForEach(icons.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { icon in
                    tile(id: icon.id, name: icon.name, symbol: icon.symbol)
                }
            }.padding()
        }.background(Color(.systemGroupedBackground)).navigationTitle("Category icon").searchable(text: $search)
    }
    private func tile(id: Int64?, name: String, symbol: String?) -> some View {
        Button { selected = id; dismiss() } label: {
            VStack(spacing: 8) {
                CategoryIconView(symbol: symbol, color: .accentColor)
                Text(name).font(.caption).foregroundStyle(.primary).multilineTextAlignment(.center)
                if selected == id { Image(systemName: "checkmark").accessibilityLabel("Selected") }
            }.frame(maxWidth: .infinity, minHeight: 108).padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected == id ? Color.accentColor : .clear, lineWidth: 2))
        }.buttonStyle(.plain).accessibilityAddTraits(selected == id ? .isSelected : [])
    }
}
