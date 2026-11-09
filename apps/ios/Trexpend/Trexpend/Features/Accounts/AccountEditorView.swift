import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AccountEditorView: View {
    let dependencies: AppDependencies
    let generation: UUID
    var accountID: Int64? = nil
    var onDelete: (() -> Void)? = nil
    @State private var state = AccountEditorState()
    @State private var showsDiscard = false
    @State private var showsDelete = false
    @State private var showsStatus = false
    @State private var showsFile = false
    @State private var photo: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss
    private var busy: Bool { state.isSaving || state.isImporting }

    var body: some View {
        NavigationStack {
            Group {
                if let context = state.context { form(context) }
                else if state.isLoading { ProgressView("Loading account") }
                else {
                    ContentUnavailableView {
                        Label("Could not load account", systemImage: "exclamationmark.triangle")
                    } description: { Text(state.error ?? "Try opening the account again.") }
                    actions: { Button("Retry") { Task { await load() } } }
                }
            }
            .navigationTitle(accountID == nil ? "New account" : "Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if state.isDirty { showsDiscard = true } else { dismiss() } }.disabled(busy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { if await state.save(dependencies: dependencies) { dismiss() } }
                } label: {
                    HStack { if state.isSaving { ProgressView().tint(.white) }; Text("Save").font(.headline) }
                        .frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.borderedProminent).padding(.horizontal, 20).padding(.vertical, 10)
                    .background(.bar).disabled(state.context == nil || busy || dependencies.session.isBusy)
            }
        }
        .interactiveDismissDisabled(state.isDirty || busy)
        .alert("Discard changes?", isPresented: $showsDiscard) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Continue editing", role: .cancel) {}
        }
        .alert("Delete account?", isPresented: $showsDelete) {
            Button("Delete account", role: .destructive) {
                Task {
                    if await state.save(dependencies: dependencies, deleting: true) { dismiss(); onDelete?() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This unused account will be permanently deleted.") }
        .alert(state.draft.isOpen ? "Close account?" : "Reopen account?", isPresented: $showsStatus) {
            Button(state.draft.isOpen ? "Close account" : "Reopen account") {
                state.draft.isOpen.toggle()
                state.draft.closeDate = state.draft.isOpen ? "" : ((try? LocalDateTime(instant: Date(), timeZone: .current).calendarDay) ?? "")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(state.draft.isOpen ? "History is preserved. Closing takes effect when you save. If this is the default account, that setting will be cleared." : "This account will become available again when you save.")
        }
        .alert("Could not complete action", isPresented: Binding(get: { state.error != nil && state.context != nil }, set: { if !$0 { state.error = nil } })) {
            Button("OK", role: .cancel) { state.error = nil }
        } message: { Text(state.error ?? "") }
        .fileImporter(isPresented: $showsFile, allowedContentTypes: [.image]) { result in importFile(result) }
        .onChange(of: photo) { _, item in
            guard let item, !busy else { return }
            state.isImporting = true
            Task {
                defer { state.isImporting = false; photo = nil }
                do {
                    guard let imported = try await item.loadTransferable(type: AccountPhotoImport.self) else { throw AccountError.image }
                    guard dependencies.session.snapshot?.generation == generation else { throw DatabaseError.staleDataset }
                    state.draft.newImage = imported.png; state.draft.appearance.imageID = nil; state.draft.appearance.customImageID = nil
                } catch { state.error = error.localizedDescription }
            }
        }
        .onChange(of: dependencies.session.snapshot?.generation) { _, current in if current != generation { dismiss() } }
        .task { await load() }
    }

    private func form(_ context: AccountEditorContext) -> some View {
        Form {
            Section("Account") {
                TextField("Name", text: $state.draft.name)
                Picker("Type", selection: $state.draft.type) {
                    ForEach(HomeAccountType.allCases) { Text($0.accountTitle).tag($0) }
                }
                if context.original == nil {
                    Picker("Currency", selection: $state.draft.currencyID) {
                        Text("Select currency").tag(nil as Int64?)
                        ForEach(context.catalog.currencies) { Text($0.code + " - " + $0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.navigationLink)
                } else { LabeledContent("Currency", value: state.currency?.code ?? "") }
                Picker("Bank", selection: $state.draft.bankID) {
                    Text("No bank").tag(nil as Int64?)
                    ForEach(context.catalog.banks) { bank in BankHeading(bank: bank).tag(Optional(bank.id)) }
                }.pickerStyle(.navigationLink)
                Toggle("Favorite", isOn: $state.draft.favorite)
            }
            Section {
                amount("Initial balance", text: $state.draft.initialBalance, signed: true)
                if let account = context.catalog.accounts.first(where: { $0.id == accountID }) {
                    LabeledContent("Current balance", value: MoneyPresentation.number(account.balance, places: account.currency.decimalPlaces) + " " + account.currency.code)
                }
                if state.draft.type == .creditCard || !state.draft.creditLimit.isEmpty {
                    amount("Credit limit", text: $state.draft.creditLimit, signed: false)
                }
            } header: { Text("Balances") } footer: {
                Text("The initial balance is the starting amount before recorded transactions. The current balance is calculated. Credit limits do not add funds.")
            }
            appearance
            Section("Details") {
                AccountDateField(title: "Opening date", value: $state.draft.openDate)
                AccountDateField(title: "Card expiry", value: $state.draft.expiryDate)
                TextField("Account or card number (optional)", text: $state.draft.accountNumber)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Notes (optional)", text: $state.draft.notes, axis: .vertical).lineLimit(3...6)
            }
            if accountID != nil {
                Section("Status") {
                    LabeledContent("Status", value: state.draft.isOpen ? "Open" : "Closed")
                    if !state.draft.isOpen { AccountDateField(title: "Closure date", value: $state.draft.closeDate) }
                    Button(state.draft.isOpen ? "Close account" : "Reopen account") { showsStatus = true }
                }
                Section {
                    if let accountID {
                        NavigationLink("View transactions") { AccountHistoryView(dependencies: dependencies, accountID: accountID) }
                    }
                    if !context.hasTransactions {
                        Button("Delete account", role: .destructive) { showsDelete = true }
                    } else { Text("This account has transactions. Close it to preserve its history.").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.disabled(busy).scrollDismissesKeyboard(.interactively)
    }

    private func amount(_ title: String, text: Binding<String>, signed: Bool) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            TextField("0", text: text).multilineTextAlignment(.trailing)
                .keyboardType(signed ? .numbersAndPunctuation : .decimalPad)
            Text(state.currency?.code ?? "").foregroundStyle(.secondary)
        }
    }

    private var appearance: some View {
        Section("Appearance") {
            HStack {
                Text("Account image")
                Spacer()
                AccountAvatar(type: state.draft.type, appearance: state.draft.appearance, database: dependencies.database,
                    generation: generation, preview: state.draft.newImage)
            }
            Picker("Built-in image", selection: Binding(get: { state.draft.appearance.imageID }, set: {
                state.draft.appearance.imageID = $0; state.draft.appearance.customImageID = nil; state.draft.newImage = nil
            })) {
                Text("Account type default").tag(nil as Int64?)
                ForEach(HomeAccountType.allCases) { type in Label(type.accountTitle, systemImage: type.symbol).tag(Optional(Int64(type.rawValue))) }
            }
            PhotosPicker(selection: $photo, matching: .images) { Label("Choose photo", systemImage: "photo") }
            Button("Choose image file", systemImage: "folder") { showsFile = true }
            if state.isImporting { ProgressView("Preparing image") }
            if state.draft.newImage != nil || state.draft.appearance.customImageID != nil || state.draft.appearance.imageID != nil {
                Button("Use account type image") {
                    state.draft.newImage = nil; state.draft.appearance.customImageID = nil; state.draft.appearance.imageID = nil
                }
            }
            Picker("Icon color", selection: $state.draft.appearance.color) {
                Text("Default").tag(nil as String?)
                if let color = state.draft.appearance.color, !Self.colors.contains(where: { $0.1 == color }) {
                    Text("Existing custom color").tag(Optional(color))
                }
                ForEach(Self.colors, id: \.1) { item in Text(item.0).tag(Optional(item.1)) }
            }
        }
    }
    private static let colors = [("Blue", "#007AFF"), ("Green", "#248A3D"), ("Orange", "#C66A00"), ("Purple", "#8944AB"), ("Red", "#D70015"), ("Gray", "#6C6C70")]

    private func load() async { await state.load(dependencies: dependencies, generation: generation, accountID: accountID) }
    private func importImage(_ data: Data) async throws {
        let normalized = try await Task.detached(priority: .userInitiated) { try AccountImageCodec.normalize(data) }.value
        guard dependencies.session.snapshot?.generation == generation else { throw DatabaseError.staleDataset }
        state.draft.newImage = normalized; state.draft.appearance.imageID = nil; state.draft.appearance.customImageID = nil
    }
    private func importFile(_ result: Result<URL, Error>) {
        guard !busy else { return }
        state.isImporting = true
        Task {
            defer { state.isImporting = false }
            do {
                let url = try result.get()
                let data = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                    guard let size, size <= AccountImageCodec.inputLimit else { throw AccountError.image }
                    return try Data(contentsOf: url)
                }.value
                try await importImage(data)
            } catch {
                if (error as NSError).code != NSUserCancelledError { state.error = error.localizedDescription }
            }
        }
    }
}

private struct AccountDateField: View {
    let title: String
    @Binding var value: String
    private var calendar: Calendar { LocalDateTime.calendar(in: .current) }
    var body: some View {
        if value.isEmpty {
            Button("Add " + title.lowercased()) { value = (try? LocalDateTime(instant: Date(), timeZone: .current).calendarDay) ?? "" }
        } else {
            HStack {
                DatePicker(title, selection: Binding(get: {
                    guard let local = try? LocalDateTime(storage: value + "T12:00:00") else { return Date() }
                    return calendar.date(from: local.components) ?? Date()
                }, set: { value = (try? LocalDateTime(instant: $0, timeZone: .current).calendarDay) ?? value }), displayedComponents: .date)
                    .environment(\.calendar, calendar)
                Button("Remove " + title.lowercased(), systemImage: "xmark.circle.fill") { value = "" }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
    }
}
