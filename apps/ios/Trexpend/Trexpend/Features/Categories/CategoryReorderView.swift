import SwiftUI

struct CategoryReorderView: View {
    let dependencies: AppDependencies
    let generation: UUID
    let parentID: Int64?
    @State private var context: CategoryReorderContext?
    @State private var ids: [Int64] = []
    @State private var initial: [Int64] = []
    @State private var error: String?
    @State private var isSaving = false
    @State private var didCommit = false
    @State private var showsDiscard = false
    @Environment(\.dismiss) private var dismiss
    private var dirty: Bool { ids != initial }

    var body: some View {
        NavigationStack {
            Group {
                if let context {
                    List {
                        Section {
                            ForEach(ids, id: \.self) { id in
                                if let category = context.catalog.categories.first(where: { $0.id == id }) {
                                    HStack(spacing: 10) {
                                        CategoryIconView(symbol: category.symbol, color: .accentColor)
                                        VStack(alignment: .leading) {
                                            Text(category.name)
                                            if !category.active { Text("Hidden").font(.caption).foregroundStyle(.secondary) }
                                        }
                                    }
                                }
                            }.onMove { source, destination in ids.move(fromOffsets: source, toOffset: destination) }
                        } header: {
                            Text(context.catalog.categories.first { $0.id == parentID }?.path ?? "Root categories")
                        } footer: { Text("This order is also used when choosing a transaction category. Hidden categories keep their positions.") }
                    }.environment(\.editMode, .constant(.active)).disabled(isSaving)
                } else if let error {
                    ContentUnavailableView {
                        Label("Could not load order", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) } actions: { Button("Retry") { Task { await load() } } }
                } else { ProgressView("Loading categories") }
            }
            .navigationTitle("Reorder categories").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if dirty { showsDiscard = true } else { dismiss() } }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(context == nil || isSaving || didCommit || dependencies.session.isBusy)
                }
            }
        }
        .interactiveDismissDisabled(dirty || isSaving)
        .alert("Discard changes?", isPresented: $showsDiscard) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Continue editing", role: .cancel) {}
        }
        .alert("Could not save order", isPresented: Binding(get: { error != nil && context != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .onChange(of: dependencies.session.snapshot?.generation) { _, value in if value != generation { dismiss() } }
        .task { await load() }
    }
    private func load() async {
        guard context == nil else { return }
        do {
            let result = try await dependencies.database.categoryReorder(parentID: parentID, expectedGeneration: generation)
            guard !Task.isCancelled, dependencies.session.snapshot?.generation == generation else { return }
            let loaded = try result.originals.map { try $0.integer("id") }
            context = result; ids = loaded; initial = loaded; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        guard let context, !isSaving, !didCommit, dependencies.session.snapshot?.generation == generation,
              dependencies.session.beginOperation() else { return }
        isSaving = true; error = nil
        defer { isSaving = false; dependencies.session.endOperation() }
        do {
            let snapshot = try await dependencies.database.reorderCategories(ids, context: context)
            didCommit = true
            dependencies.session.categoriesDidCommit(snapshot, settings: dependencies.settings)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            dependencies.session.handleRecoveryFailure(error, settings: dependencies.settings)
        }
    }
}
