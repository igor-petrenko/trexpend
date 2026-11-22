import SwiftUI

struct CurrenciesView: View {
    let dependencies: AppDependencies
    @State private var catalog: CurrencyCatalog?
    @State private var search = ""
    @State private var showsAll = false
    @State private var message: String?

    var body: some View {
        List {
            if let catalog {
                Section {
                    Toggle("Automatic daily updates", isOn: Binding(get: { catalog.sync.automatic }, set: { enabled in
                        Task { await setAutomatic(enabled) }
                    }))
                    if let date = catalog.sync.requestedDate { LabeledContent("NBU rates for", value: date) }
                    if let time = catalog.sync.lastSuccess { LabeledContent("Last downloaded", value: RatePresentation.time(time)) }
                    else { Text("Rates have not been downloaded yet.").foregroundStyle(.secondary) }
                    if dependencies.rates.isRefreshing { ProgressView("Refreshing rates") }
                    if let error = dependencies.rates.error { Text(error).foregroundStyle(.red) }
                } header: { Text("Synchronization") } footer: {
                    Text("Reference rates estimate your balances and reports. Actual bank conversion rates may differ.")
                }
                Section {
                    Picker("Currencies", selection: $showsAll) {
                        Text("Used").tag(false)
                        Text("All").tag(true)
                    }.pickerStyle(.segmented)
                    if visibleCurrencies.isEmpty { Text("No currencies found").foregroundStyle(.secondary) }
                    ForEach(visibleCurrencies) { currency in
                        NavigationLink {
                            CurrencyDetailView(dependencies: dependencies, currencyID: currency.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(currency.code).font(.headline)
                                    Spacer()
                                    Text(RatePresentation.quote(currency.id, to: catalog.displayID, catalog: catalog)).font(.subheadline).monospacedDigit()
                                }
                                Text(currency.name).font(.subheadline).foregroundStyle(.secondary)
                                Text(RatePresentation.status(currency.id, catalog: catalog)).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 3)
                        }
                    }
                }
            } else if dependencies.session.snapshot == nil {
                Text("Open or import a database in Settings.").foregroundStyle(.secondary)
            } else { ProgressView("Loading currencies") }
        }
        .navigationTitle("Currencies")
        .searchable(text: $search, prompt: "Currency code or name")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await dependencies.rates.refresh(dependencies: dependencies, manual: true); await load() }
                }.disabled(dependencies.rates.isRefreshing || dependencies.session.snapshot == nil)
            }
        }
        .task { await dependencies.rates.refresh(dependencies: dependencies) }
        .task(id: dependencies.session.currencyRevision) { await load() }
        .task(id: dependencies.session.snapshot?.generation) { await load() }
        .alert("Currencies", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private var visibleCurrencies: [CurrencyInfo] {
        guard let catalog else { return [] }
        return catalog.currencies.filter { currency in
            (showsAll || catalog.usedIDs.contains(currency.id)) &&
            (search.isEmpty || currency.code.localizedCaseInsensitiveContains(search) || currency.name.localizedCaseInsensitiveContains(search))
        }
    }

    private func load() async {
        guard let generation = dependencies.session.snapshot?.generation else { catalog = nil; return }
        do {
            let result = try await dependencies.database.currencies(expectedGeneration: generation)
            guard !Task.isCancelled, dependencies.session.snapshot?.generation == generation else { return }
            catalog = result
        } catch { if !Task.isCancelled { message = AppSession.message(for: error) } }
    }
    private func setAutomatic(_ enabled: Bool) async {
        guard let generation = dependencies.session.snapshot?.generation else { return }
        do {
            if !enabled { dependencies.rates.invalidate() }
            let result = try await dependencies.database.setAutomaticRates(enabled, expectedGeneration: generation)
            guard dependencies.session.snapshot?.generation == generation else { return }
            catalog = result
            dependencies.session.rateMetadataDidChange(generation: generation)
            if enabled { await dependencies.rates.refresh(dependencies: dependencies) }
        } catch { message = AppSession.message(for: error) }
    }
}

nonisolated enum RatePresentation {
    static func number(_ value: Decimal) -> String {
        var copy = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &copy, 8, .plain)
        if rounded == 0 && value != 0 { return CurrencyConverter.text(value) }
        return CurrencyConverter.text(rounded)
    }
    static func quote(_ id: Int64, to target: Int64, catalog: CurrencyCatalog) -> String {
        guard let code = catalog.currencies.first(where: { $0.id == target })?.code,
              let value = try? catalog.converter.convert(MonetaryAmount(value: 1, currencyID: id), to: target) else { return "Rate unavailable" }
        return "\(number(value)) \(code)"
    }
    static func status(_ id: Int64, catalog: CurrencyCatalog) -> String {
        if catalog.currencies.first(where: { $0.id == id })?.code.uppercased() == "UAH" { return "UAH reference" }
        if catalog.rates[id]?.manual != nil { return "Manual" }
        if let date = catalog.rates[id]?.effectiveDate { return "NBU - \(date)" }
        if !catalog.sync.canonical,
           let anchor = catalog.currencies.first(where: { $0.code.uppercased() == "UAH" })?.id,
           (try? catalog.converter.convert(MonetaryAmount(value: 1, currencyID: id), to: anchor)) != nil { return "Previous rate" }
        guard let code = catalog.currencies.first(where: { $0.id == id })?.code.uppercased(),
              NBUClient.supportedCodes.contains(code), catalog.fiatIDs.contains(id) else { return "No NBU rate available" }
        return "Not downloaded"
    }
    static func time(_ timestamp: String) -> String {
        guard let date = RateDates.instant(timestamp) else { return timestamp }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
