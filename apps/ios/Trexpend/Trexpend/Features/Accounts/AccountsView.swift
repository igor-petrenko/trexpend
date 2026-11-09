import SwiftUI

struct AccountsView: View {
    let dependencies: AppDependencies
    @State private var catalog: AccountCatalog?
    @State private var error: String?
    @State private var filter = Filter.open
    @State private var selection: Selection?
    private enum Filter: String, CaseIterable { case open = "Open", closed = "Closed", all = "All" }
    private struct Selection: Identifiable { let id = UUID(); let accountID: Int64? }
    private struct Key: Equatable { let generation: UUID?; let accounts: UInt64; let transactions: UInt64 }
    private var key: Key { Key(generation: dependencies.session.snapshot?.generation, accounts: dependencies.session.accountRevision, transactions: dependencies.session.transactionRevision) }
    private var visible: [ManagedAccount] {
        (catalog?.accounts ?? []).filter { filter == .all || $0.isOpen == (filter == .open) }
    }

    var body: some View {
        Group {
            if dependencies.session.snapshot == nil { DatabaseStatusView(session: dependencies.session) }
            else if let catalog {
                List {
                    Section {
                        Picker("Accounts", selection: $filter) {
                            ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    if visible.isEmpty {
                        ContentUnavailableView {
                            Label("No accounts", systemImage: "wallet.bifold")
                        } description: { Text("Create an account to start recording transactions.") }
                        actions: { Button("Add account") { selection = Selection(accountID: nil) } }
                    }
                    ForEach(catalog.banks) { bank in
                        group(visible.filter { $0.bankID == bank.id }, bank: bank, generation: catalog.generation)
                    }
                    group(visible.filter { $0.bankID == nil }, bank: nil, generation: catalog.generation)
                }.refreshable { await load() }
            } else if let error {
                ContentUnavailableView {
                    Label("Could not load accounts", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: { Button("Retry") { Task { await load() } } }
            } else { ProgressView("Loading accounts") }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add account", systemImage: "plus") { selection = Selection(accountID: nil) }
                    .disabled(dependencies.session.snapshot == nil || dependencies.session.isBusy)
            }
        }
        .fullScreenCover(item: $selection) { item in
            if let generation = dependencies.session.snapshot?.generation {
                AccountEditorView(dependencies: dependencies, generation: generation, accountID: item.accountID)
            }
        }
        .task(id: key) { await load() }
    }

    @ViewBuilder private func group(_ accounts: [ManagedAccount], bank: BankInfo?, generation: UUID) -> some View {
        if !accounts.isEmpty {
            Section {
                ForEach(accounts) { account in
                    Button { selection = Selection(accountID: account.id) } label: {
                        ManagedAccountRow(account: account, database: dependencies.database, generation: generation)
                    }.buttonStyle(.plain)
                }
            } header: { BankHeading(bank: bank) }
        }
    }

    private func load() async {
        let requested = key
        guard let generation = requested.generation else { catalog = nil; return }
        do {
            let result = try await dependencies.database.managedAccounts(expectedGeneration: generation)
            guard !Task.isCancelled, key == requested else { return }
            catalog = result; error = nil
        } catch {
            guard !Task.isCancelled, key == requested else { return }
            catalog = nil; self.error = error.localizedDescription
        }
    }
}


private struct ManagedAccountRow: View {
    let account: ManagedAccount
    let database: DatabaseStore
    let generation: UUID
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        Group {
            if textSize.isAccessibilitySize { stacked }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        icon; identity.frame(minWidth: 80)
                        Spacer(minLength: 4)
                        balance
                    }
                    stacked
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).contentShape(Rectangle())
    }
    private var icon: some View {
        AccountAvatar(type: account.type, appearance: account.appearance, database: database, generation: generation)
    }
    private var identity: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(account.name.isEmpty ? "Unnamed account" : account.name).foregroundStyle(.primary)
                if account.favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).accessibilityLabel("Favorite") }
            }
            Text(account.type.accountTitle + " - " + account.currency.code).font(.caption).foregroundStyle(.secondary)
            if !account.isOpen { Text("Closed").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var balance: some View {
        Text(MoneyPresentation.number(account.balance, places: account.currency.decimalPlaces))
            .font(.callout.weight(.medium)).monospacedDigit().foregroundStyle(.primary)
            .fixedSize(horizontal: true, vertical: false)
    }
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) { icon; identity }
            Text(MoneyPresentation.number(account.balance, places: account.currency.decimalPlaces))
                .font(.callout.weight(.medium)).monospacedDigit().foregroundStyle(.primary)
        }
    }
}
