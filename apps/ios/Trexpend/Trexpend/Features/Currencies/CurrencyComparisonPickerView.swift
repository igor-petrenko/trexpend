import SwiftUI

struct CurrencyComparisonSelection: Identifiable {
    let id = UUID()
    let catalog: CurrencyCatalog
}

struct CurrencyComparisonPickerView: View {
    let dependencies: AppDependencies
    let selection: CurrencyComparisonSelection
    @State private var ids: [Int64]
    @State private var search = ""
    @State private var message: String?
    @State private var isSaving = false
    @State private var confirmsDiscard = false
    @Environment(\.dismiss) private var dismiss
    private var dirty: Bool { ids != selection.catalog.comparisonIDs }

    init(dependencies: AppDependencies, selection: CurrencyComparisonSelection) {
        self.dependencies = dependencies; self.selection = selection
        _ids = State(initialValue: selection.catalog.comparisonIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if ids.isEmpty { Text("No comparison currencies selected").foregroundStyle(.secondary) }
                    ForEach(ids, id: \.self) { id in
                        if let currency = selection.catalog.currencies.first(where: { $0.id == id }) {
                            HStack(spacing: 12) {
                                Button { ids.removeAll { $0 == id } } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }.buttonStyle(.borderless).accessibilityLabel("Remove \(currency.code)")
                                currencyLabel(currency)
                            }
                        }
                    }.onMove { source, destination in ids.move(fromOffsets: source, toOffset: destination) }
                } header: { Text("Selected") } footer: {
                    Text("Drag the handles to reorder. This selection is shared by all currencies. The currency you are viewing is omitted from its own tiles.")
                }
                Section("Add currencies") {
                    let choices = available
                    if choices.isEmpty { Text("No currencies found").foregroundStyle(.secondary) }
                    ForEach(choices) { currency in
                        Button { ids.append(currency.id) } label: {
                            HStack {
                                currencyLabel(currency)
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(.tint)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .disabled(isSaving)
            .searchable(text: $search, prompt: "Find currencies to add")
            .navigationTitle("Comparison Currencies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if dirty { confirmsDiscard = true } else { dismiss() } }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(dirty || isSaving)
            .confirmationDialog("Discard changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Continue Editing", role: .cancel) {}
            }
            .alert("Could not save currencies", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
            .onChange(of: dependencies.session.snapshot?.generation) { _, value in
                if value != selection.catalog.generation { dismiss() }
            }
        }
        .presentationDetents([.large])
    }

    private var available: [CurrencyInfo] {
        let chosen = Set(ids)
        return selection.catalog.currencies.filter {
            !chosen.contains($0.id) && (search.isEmpty || $0.code.localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search))
        }
    }
    private func currencyLabel(_ currency: CurrencyInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(currency.code).font(.body.weight(.medium))
            Text(currency.name).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func save() async {
        guard !isSaving else { return }
        isSaving = true; defer { isSaving = false }
        do {
            let catalog = try await dependencies.database.saveComparisonCurrencies(ids, original: selection.catalog.comparisonIDs,
                expectedGeneration: selection.catalog.generation)
            guard dependencies.session.snapshot?.generation == catalog.generation else { return }
            dependencies.session.rateMetadataDidChange(generation: catalog.generation)
            dismiss()
        } catch { message = (error as? LocalizedError)?.errorDescription ?? "The comparison currencies could not be saved." }
    }
}
