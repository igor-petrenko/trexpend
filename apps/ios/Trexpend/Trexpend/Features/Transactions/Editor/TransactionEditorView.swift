import SwiftUI

struct TransactionEditorView: View {
    let dependencies: AppDependencies
    let generation: UUID
    var transactionID: Int64? = nil
    var accountID: Int64? = nil
    @State private var state: TransactionEditorState
    @State private var detent: PresentationDetent = .height(510)
    @State private var didInitialFocus = false
    @State private var restingDetent: PresentationDetent = .height(510)
    @State private var showsDiscard = false
    @State private var pickerPath: [PickerRoute] = []
    @State private var isPicking = false
    @State private var deletion = TransactionDeletionState()
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    private enum PickerRoute: Hashable { case source, receiver, category }
    private enum Field: Hashable { case amount, received, fee, notes }
    private var isNew: Bool { transactionID == nil }

    init(dependencies: AppDependencies, generation: UUID, transactionID: Int64? = nil,
         accountID: Int64? = nil, state: TransactionEditorState? = nil) {
        self.dependencies = dependencies
        self.generation = generation
        self.transactionID = transactionID
        self.accountID = accountID
        // The optional seed supports isolated previews/tests; editor drafts are
        // intentionally owned once for this presentation, not parent-bound values.
        _state = State(initialValue: state ?? TransactionEditorState())
    }

    var body: some View {
        NavigationStack(path: $pickerPath) {
            Group {
                if let context = state.context {
                    form(context)
                } else if state.isLoading { ProgressView("Loading transaction") }
                else {
                    ContentUnavailableView("Could not load transaction", systemImage: "exclamationmark.triangle", description: Text(state.error ?? "Try opening this transaction again."))
                }
            }
            .navigationDestination(for: PickerRoute.self) { route in
                if let context = state.context {
                    pickerDestination(route, context: context)
                        .onDisappear { pickerDidDisappear() }
                }
            }
            .navigationTitle(isNew ? "New transaction" : "Edit transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }.disabled(state.isSaving || deletion.isBusy)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 6) {
                    Button { save() } label: {
                        HStack {
                            if state.isSaving { ProgressView().tint(.white) }
                            Text("Save").font(.headline)
                        }.frame(maxWidth: .infinity).frame(minHeight: 48)
                    }.buttonStyle(.borderedProminent)
                        .alert("Round amounts to currency precision?", isPresented: Binding(get: { state.roundingMessage != nil }, set: { if !$0 { state.roundingMessage = nil } })) {
                            Button("Save rounded amounts") { save(confirmRounding: true) }
                            Button("Cancel", role: .cancel) { state.roundingMessage = nil }
                        } message: { Text(state.roundingMessage ?? "") }
                        .disabled(state.context == nil || state.isLoading || state.isSaving || dependencies.session.snapshot?.generation != generation)
                    if !isNew, state.context?.original != nil {
                        Button(role: .destructive) {
                            focus = nil
                            if let original = state.context?.original, let transactionID {
                                deletion.request(TransactionDeletionTarget(id: transactionID, generation: generation, original: original))
                            }
                        } label: {
                            Label("Delete transaction", systemImage: "trash")
                                .font(.callout).frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(.red)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
            }
            .disabled(state.isSaving || deletion.isBusy)
        }
        .presentationDetents(isNew ? [.height(510), .large] : [.large], selection: $detent)
        .presentationDragIndicator(isNew ? .visible : .hidden)
        .interactiveDismissDisabled(state.isDirty || state.isSaving || deletion.isBusy)
        .background(DiscardAttemptObserver(disabled: state.isDirty || state.isSaving || deletion.isBusy) {
            if !state.isSaving && !deletion.isBusy { showsDiscard = true }
        })
        .alert("Discard changes?", isPresented: $showsDiscard) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Continue editing", role: .cancel) {}
        }
        .transactionDeletion(state: deletion, dependencies: dependencies)
        .onChange(of: deletion.didDelete) { _, deleted in if deleted { dismiss() } }
        .task {
            await state.load(database: dependencies.database, generation: generation, transactionID: transactionID, accountID: accountID)
            if isNew, state.context != nil, !didInitialFocus { didInitialFocus = true; focus = .amount }
        }
        .onChange(of: focus) { old, new in
            guard isNew else { return }
            if old == nil, new != nil { restingDetent = detent; detent = .large }
            if new == nil, !isPicking { detent = state.isTransfer ? .large : restingDetent }
        }
        .onChange(of: detent) { _, value in
            if focus == nil, !isPicking { restingDetent = value }
        }
        .onChange(of: state.isTransfer) { _, transfer in
            if isNew, transfer { detent = .large }
        }
        .onChange(of: dependencies.session.snapshot?.generation) { _, value in
            if value != generation { focus = nil; dismiss() }
        }
    }

    private func form(_ context: TransactionEditorContext) -> some View {
        @Bindable var state = state
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Type", selection: Binding(get: { state.draft.type }, set: { value in
                        focus = nil
                        Task { await state.changeType(value, database: dependencies.database) }
                    })) {
                        Text("Expense").tag(LedgerTransactionType.expense)
                        Text("Income").tag(LedgerTransactionType.income)
                        Text("Transfer").tag(LedgerTransactionType.transfer)
                    }.pickerStyle(.segmented)
                    if !isNew || state.isTransfer { dateFields }
                    VStack(spacing: 0) {
                        Button { openPicker(.source) } label: { selectionRow(state.isTransfer ? "From" : "Account", state.source?.name ?? "Choose account", account: state.source) }
                        if state.isTransfer {
                            Divider()
                            categoryField(context)
                            Divider()
                            Button { openPicker(.receiver) } label: { selectionRow("To", state.receiver?.name ?? "Choose recipient", account: state.receiver) }
                        }
                    }.background(.background, in: RoundedRectangle(cornerRadius: 14))
                    if isNew && !state.isTransfer { dateFields }
                    amountField("Amount", text: Binding(get: { state.draft.amount }, set: { state.changeAmount($0) }), currency: state.source?.currency.code, field: .amount)
                    if !state.isTransfer {
                        categoryField(context)
                            .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if state.showsReceiverAmount {
                        amountField("Received amount", text: Binding(get: { state.draft.receiverAmount }, set: { state.draft.receiverAmount = $0; state.draft.receiverAmountIsManual = true }), currency: state.receiver?.currency.code, field: .received)
                    }
                    if state.isTransfer {
                        amountField("Fee", text: $state.draft.fee, currency: (state.draft.feeFromReceiver ? state.receiver : state.source)?.currency.code, field: .fee)
                        Picker("Fee charged to", selection: $state.draft.feeFromReceiver) {
                            Text("Sender").tag(false); Text("Recipient").tag(true)
                        }.pickerStyle(.segmented)
                        Text("Transfer amounts exclude the fee.").font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Notes (optional)", text: $state.draft.notes, axis: .vertical)
                        .lineLimit(2...5).focused($focus, equals: .notes).id(Field.notes)
                        .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 14))
                    if let error = state.error { Text(error).font(.callout).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently).id("validation") }
                    Color.clear.frame(height: 20).contentShape(Rectangle()).onTapGesture { focus = nil }
                }.padding(16)
            }.scrollDismissesKeyboard(.interactively)
                .background(Color(.systemGroupedBackground).onTapGesture { focus = nil })
                .onChange(of: focus) { _, value in
                    if let value { withAnimation { proxy.scrollTo(value, anchor: .center) } }
                }
                .onChange(of: state.error) { _, value in
                    if value != nil { withAnimation { proxy.scrollTo("validation", anchor: .bottom) } }
                }
        }
    }

    private var dateFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            if textSize.isAccessibilitySize {
                Text("Date")
                datePicker.labelsHidden().accessibilityLabel("Date")
                Text("Time")
                timePicker.labelsHidden().accessibilityLabel("Time")
            } else { datePicker; timePicker }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private var datePicker: some View {
        DatePicker("Date", selection: Binding(get: { state.pickerDate }, set: { state.dateChanged($0) }),
                   in: ...Date(), displayedComponents: .date)
            .simultaneousGesture(TapGesture().onEnded { focus = nil })
    }
    private var timePicker: some View {
        DatePicker("Time", selection: Binding(get: { state.pickerDate }, set: { state.timeChanged($0) }),
                   displayedComponents: .hourAndMinute)
            .simultaneousGesture(TapGesture().onEnded { focus = nil })
    }

    private func accountPicker(_ context: TransactionEditorContext, receiver: Bool) -> some View {
        let oldSource = try? context.original?.integer("account_id")
        let oldReceiver = try? context.original?.optionalInteger("to_account_id")
        return AccountPickerView(accounts: context.accounts.filter { $0.isOpen || $0.id == oldSource || $0.id == oldReceiver }, selected: receiver ? state.draft.receiverID : state.draft.accountID, database: dependencies.database, generation: generation) { id in
            if receiver { state.chooseReceiver(id) }
            else { Task { await state.changeSource(id, database: dependencies.database) } }
        }
    }
    private func eligibleCategories(_ context: TransactionEditorContext) -> [EditorCategory] {
        let original = try? context.original?.integer("category_id")
        return context.categories.filter { $0.active || $0.id == original }
    }
    private func categoryField(_ context: TransactionEditorContext) -> some View {
        Button { openPicker(.category) } label: {
            selectionRow("Category", context.categories.first { $0.id == state.draft.categoryID }?.name ?? "Choose category")
        }
    }

    private func openPicker(_ route: PickerRoute) {
        guard pickerPath.isEmpty, !isPicking else { return }
        // Establish the navigation guard before focus loss can resize the sheet.
        isPicking = true
        focus = nil
        pickerPath.append(route)
    }

    @ViewBuilder private func pickerDestination(_ route: PickerRoute, context: TransactionEditorContext) -> some View {
        switch route {
        case .source: accountPicker(context, receiver: false)
        case .receiver: accountPicker(context, receiver: true)
        case .category:
            CategoryPickerView(categories: context.categories, selectableIDs: Set(eligibleCategories(context).map(\.id)), selected: state.draft.categoryID) {
                state.draft.categoryID = $0
            }
        }
    }

    private func pickerDidDisappear() {
        // An empty path distinguishes a completed return from a cancelled pop.
        guard pickerPath.isEmpty else { return }
        isPicking = false
        if isNew { restingDetent = detent }
    }

    private func selectionRow(_ label: String, _ value: String, account: EditorAccount? = nil) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if let account, account.appearance.customImageID != nil {
                    AccountAvatar(type: account.type, appearance: account.appearance, database: dependencies.database,
                                  generation: generation, size: 32, showsFallback: false)
                }
                Text(value).multilineTextAlignment(.trailing).foregroundStyle(.primary)
            }
        }.padding(14).contentShape(Rectangle())
    }
    private func amountField(_ label: String, text: Binding<String>, currency: String?, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("0", text: text).keyboardType(.decimalPad).focused($focus, equals: field)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 28, weight: .semibold)).accessibilityLabel(label)
                Text(currency ?? "").foregroundStyle(.secondary)
            }
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle()).onTapGesture { focus = field }.id(field)
    }
    private func cancel() { if state.isDirty { showsDiscard = true } else { dismiss() } }
    private func save(confirmRounding: Bool = false) {
        Task { if await state.save(dependencies: dependencies, confirmRounding: confirmRounding) { dismiss() } }
    }
}
