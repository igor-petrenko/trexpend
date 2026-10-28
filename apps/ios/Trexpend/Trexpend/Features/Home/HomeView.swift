import SwiftUI

struct HomeView: View {
    let dependencies: AppDependencies
    private let loadsDatabase: Bool
    @State private var state: HomeState
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase

    init(dependencies: AppDependencies, preview: HomeSnapshot? = nil) {
        self.dependencies = dependencies
        loadsDatabase = preview == nil
        _state = State(initialValue: HomeState(content: preview))
    }

    private struct LoadKey: Equatable {
        let generation: UUID?
        let currencyID: Int64?
        let month: String
    }
    private var month: CalendarMonth? {
        guard let local = try? LocalDateTime(instant: now, timeZone: .current) else { return nil }
        return try? CalendarMonth(year: local.year, month: local.month)
    }
    private var loadKey: LoadKey {
        LoadKey(generation: dependencies.session.snapshot?.generation, currencyID: dependencies.session.snapshot?.settings.displayCurrencyID, month: month?.start.storage ?? "")
    }

    var body: some View {
        Group {
            if loadsDatabase && dependencies.session.snapshot == nil {
                DatabaseStatusView(session: dependencies.session)
            } else if let content = state.content {
                dashboard(content)
            } else if let error = state.error {
                ContentUnavailableView {
                    Label("Could not load overview", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("Retry") { Task { await refresh() } }
                }
            } else {
                ProgressView("Loading overview")
            }
        }
        .navigationTitle("Home")
        .toolbar(.hidden, for: .navigationBar)
        .task(id: loadKey) { if loadsDatabase { await refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, loadsDatabase {
                now = Date()
                Task { await refresh() }
            }
        }
        .task {
            guard loadsDatabase else { return }
            // Wake at the next local month boundary even if the app stays open.
            while !Task.isCancelled {
                let calendar = LocalDateTime.calendar(in: .current)
                guard let interval = calendar.dateInterval(of: .month, for: Date()) else { return }
                do { try await Task.sleep(for: .seconds(max(1, interval.end.timeIntervalSinceNow))) }
                catch { return }
                now = Date()
            }
        }
    }

    private func dashboard(_ content: HomeSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HomeSummaryView(content: content)
                if content.accountCount == 0 {
                    ContentUnavailableView("No accounts", systemImage: "wallet.bifold", description: Text("Import a database in Settings."))
                } else if content.groups.isEmpty {
                    ContentUnavailableView("No open accounts", systemImage: "wallet.bifold", description: Text("Closed-account activity is included in this month's totals."))
                }
                ForEach(content.groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.type.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(group.accounts) { account in
                                NavigationLink {
                                    AccountHistoryView(dependencies: dependencies, accountID: account.id)
                                } label: { HomeAccountView(account: account) }
                                .buttonStyle(.plain)
                                if account.id != group.accounts.last?.id { Divider().padding(.leading, 68) }
                            }
                        }
                        .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            // Reserved for the future 64-point create action; the last row can
            // scroll fully clear of both that action and the native tab bar.
            .padding(.bottom, 96)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { if loadsDatabase { await refresh() } }
    }

    private func refresh() async {
        guard let month else { return }
        await state.load(database: dependencies.database, session: dependencies.session, month: month)
    }
}
