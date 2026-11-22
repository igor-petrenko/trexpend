import SwiftUI

struct CurrencyDetailView: View {
    let dependencies: AppDependencies
    let currencyID: Int64
    @State private var catalog: CurrencyCatalog?
    @State private var amount = "1"
    @State private var comparisonEditing: CurrencyComparisonSelection?
    @FocusState private var amountFocused: Bool
    @State private var editing: ManualRateRequest?
    @State private var message: String?
    @State private var isSaving = false
    @State private var confirmsAutomatic = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let catalog, let currency = catalog.currencies.first(where: { $0.id == currencyID }),
               let anchor = catalog.currencies.first(where: { $0.code.uppercased() == "UAH" }) {
                Section(currency.name) {
                    HStack {
                        Text("Amount").onTapGesture { amountFocused = false }
                        TextField("1", text: $amount)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .focused($amountFocused).accessibilityLabel("Amount to compare")
                    }
                    if let amountError {
                        Text(amountError).font(.caption).foregroundStyle(.red)
                            .contentShape(Rectangle()).onTapGesture { amountFocused = false }
                    }
                    Button("Comparison Currencies", systemImage: "slider.horizontal.3") {
                        amountFocused = false
                        comparisonEditing = CurrencyComparisonSelection(catalog: catalog)
                    }
                }
                Section {
                    CurrencyComparisonTiles(currency: currency, catalog: catalog, amount: parsedAmount)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle()).onTapGesture { amountFocused = false }
                }
                Section("Rate Details") {
                    LabeledContent("Source", value: source(catalog, currency: currency))
                        .contentShape(Rectangle()).onTapGesture { amountFocused = false }
                    let timestamp = catalog.rates[currencyID]?.manual != nil
                        ? catalog.rates[currencyID]?.manualUpdatedAt : catalog.rates[currencyID]?.fetchedAt
                    LabeledContent("Updated", value: timestamp.map(RatePresentation.time) ?? "Unavailable")
                        .contentShape(Rectangle()).onTapGesture { amountFocused = false }
                }
                if currency.id != anchor.id && catalog.fiatIDs.contains(currency.id) {
                    Section {
                        Button("Set Manual Rate") {
                            amountFocused = false
                            editing = ManualRateRequest(currency: currency, catalog: catalog)
                        }
                        if catalog.rates[currencyID]?.manual != nil {
                            Button("Use NBU Rate") { amountFocused = false; confirmsAutomatic = true }
                        }
                    } footer: {
                        Text("A manual rate remains active until you choose Use NBU Rate. Other currencies continue updating automatically.")
                            .contentShape(Rectangle()).onTapGesture { amountFocused = false }
                    }
                }
                Section {
                    Button("Refresh NBU Rates", systemImage: "arrow.clockwise") {
                        amountFocused = false
                        Task { await dependencies.rates.refresh(dependencies: dependencies, manual: true, extraID: currencyID); await load() }
                    }
                    if dependencies.rates.isRefreshing { ProgressView("Refreshing rates") }
                    if let error = dependencies.rates.error { Text(error).foregroundStyle(.red) }
                } footer: {
                    Text("Reference conversions are estimates. Saved transaction and transfer amounts are unchanged.")
                        .contentShape(Rectangle()).onTapGesture { amountFocused = false }
                }
            } else { ProgressView("Loading currency") }
        }
        .navigationTitle(catalog?.currencies.first(where: { $0.id == currencyID })?.code ?? "Currency")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { amountFocused = false }
            }
        }
        .sheet(item: $comparisonEditing) { selection in
            CurrencyComparisonPickerView(dependencies: dependencies, selection: selection)
        }
        .sheet(item: $editing) { request in ManualRateEditor(dependencies: dependencies, request: request) }
        .task(id: dependencies.session.currencyRevision) { await load() }
        .task {
            await load()
            if catalog?.needsRate(currencyID) == true {
                await dependencies.rates.refresh(dependencies: dependencies, extraID: currencyID)
                await load()
            }
        }
        .onChange(of: dependencies.session.snapshot?.generation) { _, value in if value != catalog?.generation { dismiss() } }
        .confirmationDialog("Use the NBU rate?", isPresented: $confirmsAutomatic, titleVisibility: .visible) {
            Button("Use NBU Rate") { Task { await useAutomatic() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let rate = catalog?.rates[currencyID], let value = rate.nbu {
                Text("Cached NBU rate: \(RatePresentation.number(value)) UAH, valid for \(rate.effectiveDate ?? "unknown date").")
            } else { Text("A usable NBU rate must be downloaded before removing your manual rate.") }
        }
        .alert("Currency", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private var parsedAmount: Decimal? { try? MoneyCodec.parseExactInput(amount) }
    private var amountError: String? {
        guard !amount.isEmpty else { return nil }
        do { _ = try MoneyCodec.parseExactInput(amount); return nil }
        catch { return (error as? LocalizedError)?.errorDescription ?? "Enter a valid amount." }
    }
    private func source(_ catalog: CurrencyCatalog, currency: CurrencyInfo) -> String {
        if currency.code.uppercased() == "UAH" { return "UAH reference" }
        if catalog.rates[currency.id]?.manual != nil { return "Manual" }
        if catalog.rates[currency.id]?.nbu != nil { return "NBU" }
        if RatePresentation.status(currency.id, catalog: catalog) == "Previous rate" { return "Previous rate" }
        return "Unavailable"
    }

    private func load() async {
        guard let generation = dependencies.session.snapshot?.generation else { return }
        do {
            let result = try await dependencies.database.currencies(expectedGeneration: generation)
            guard !Task.isCancelled, dependencies.session.snapshot?.generation == generation else { return }
            catalog = result
        } catch { if !Task.isCancelled { message = AppSession.message(for: error) } }
    }
    private func useAutomatic() async {
        guard let original = catalog, !isSaving else { return }
        isSaving = true; defer { isSaving = false }
        do {
            if original.rates[currencyID]?.nbu == nil {
                guard await dependencies.rates.refresh(dependencies: dependencies, manual: true, extraID: currencyID) else { throw CurrencyRateError.unavailable }
            }
            let commit = try await dependencies.database.saveManualRate(id: currencyID, value: nil, original: original.rates[currencyID], now: Date(), expectedGeneration: original.generation)
            dependencies.session.ratesDidCommit(commit)
            catalog = commit.catalog
        } catch { message = (error as? LocalizedError)?.errorDescription ?? "The rate could not be changed." }
    }
}

struct ManualRateRequest: Identifiable {
    let id = UUID()
    let currency: CurrencyInfo
    let catalog: CurrencyCatalog
}

struct ManualRateEditor: View {
    let dependencies: AppDependencies
    let request: ManualRateRequest
    @State private var value = ""
    @State private var initial = ""
    @State private var isSaving = false
    @State private var message: String?
    @State private var confirmsDiscard = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("1 \(request.currency.code) =")
                        TextField("Rate", text: $value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isFocused)
                        Text("UAH").foregroundStyle(.secondary)
                    }
                    if let preview { LabeledContent("In display currency", value: preview) }
                } footer: { Text("This replaces the reference coefficient for this currency. It will not be overwritten by automatic updates.") }
                if let message { Text(message).foregroundStyle(.red) }
            }
            .navigationTitle("Manual Rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if value != initial { confirmsDiscard = true } else { dismiss() } }.disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save") { Task { await save() } }.buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity).padding().disabled(isSaving || value.isEmpty)
                    .background(.bar)
            }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(isSaving || value != initial)
            .confirmationDialog("Discard changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Continue Editing", role: .cancel) {}
            }
            .task {
                let rate = request.catalog.rates[request.currency.id]?.effective
                value = rate.map(CurrencyConverter.text) ?? ""; initial = value
                isFocused = true
            }
            .onChange(of: dependencies.session.snapshot?.generation) { _, generation in if generation != request.catalog.generation { dismiss() } }
        }
    }
    private var preview: String? {
        guard let value = try? MoneyCodec.decodeRate(value.replacingOccurrences(of: ",", with: ".")),
              let anchor = request.catalog.currencies.first(where: { $0.code.uppercased() == "UAH" })?.id,
              let result = try? request.catalog.converter.convert(MonetaryAmount(value: value, currencyID: anchor), to: request.catalog.displayID),
              let code = request.catalog.currencies.first(where: { $0.id == request.catalog.displayID })?.code else { return nil }
        // An override of the display currency makes its own unit exactly one.
        return "\(request.currency.id == request.catalog.displayID ? "1" : RatePresentation.number(result)) \(code)"
    }
    private func save() async {
        guard !isSaving else { return }
        isSaving = true; defer { isSaving = false }
        do {
            let commit = try await dependencies.database.saveManualRate(id: request.currency.id, value: value,
                original: request.catalog.rates[request.currency.id], now: Date(), expectedGeneration: request.catalog.generation)
            dependencies.session.ratesDidCommit(commit)
            dismiss()
        } catch { message = (error as? LocalizedError)?.errorDescription ?? "The rate could not be saved." }
    }
}
