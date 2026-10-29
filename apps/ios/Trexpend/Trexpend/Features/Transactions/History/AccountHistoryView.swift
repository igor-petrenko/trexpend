import SwiftUI

struct AccountHistoryView: View {
    let dependencies: AppDependencies
    let accountID: Int64
    @State private var state = HistoryState()
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase

    private var month: CalendarMonth? {
        guard let local = try? LocalDateTime(instant: now, timeZone: .current) else { return nil }
        return try? CalendarMonth(year: local.year, month: local.month)
    }
    private struct LoadKey: Equatable { let generation: UUID?; let currency: Int64?; let month: String }
    private var key: LoadKey { LoadKey(generation: dependencies.session.snapshot?.generation, currency: dependencies.session.snapshot?.settings.displayCurrencyID, month: month?.start.storage ?? "") }

    var body: some View {
        Group {
            if dependencies.session.snapshot == nil { DatabaseStatusView(session: dependencies.session) }
            else if let content = state.content {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        AccountSummaryView(content: content)
                        Text("Transactions").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        if state.rows.isEmpty { ContentUnavailableView("No transactions", systemImage: "list.bullet", description: Text("This account has no recorded transactions.")) }
                        ForEach(state.days) { day in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(MoneyPresentation.day(day.id)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
                                LazyVStack(spacing: 0) {
                                    ForEach(day.rows) { row in
                                        TransactionRowView(row: row)
                                        if row.id != day.rows.last?.id { Divider().padding(.leading, 66) }
                                    }
                                }.background(.background, in: RoundedRectangle(cornerRadius: 18))
                            }
                        }
                        if let error = state.pageError {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            Button("Retry loading more") { Task { await loadMore() } }
                        } else if let next = state.next, !state.isLoading {
                            ProgressView("Loading more")
                                .frame(maxWidth: .infinity).task(id: next.id) { await loadMore() }
                        }
                    }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 96)
                }.background(Color(.systemGroupedBackground)).refreshable { await refresh() }
            } else if let error = state.error {
                ContentUnavailableView {
                    Label("Could not load history", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: { Button("Retry") { Task { await refresh() } } }
            } else { ProgressView("Loading history") }
        }
        .navigationTitle(state.content?.account.name ?? "Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if let account = state.content?.account {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: account.favorite ? "star.fill" : "star")
                        .foregroundStyle(account.favorite ? Color.yellow : Color.secondary)
                        .accessibilityLabel(account.favorite ? "Favorite account" : "Not a favorite account")
                }
            }
        }
        .task(id: key) { await ensureLoaded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date(); Task { await ensureLoaded() } }
        }
        .task {
            while !Task.isCancelled {
                guard let interval = LocalDateTime.calendar(in: .current).dateInterval(of: .month, for: Date()) else { return }
                do { try await Task.sleep(for: .seconds(max(1, interval.end.timeIntervalSinceNow))) }
                catch { return }
                now = Date()
            }
        }
    }
    private func ensureLoaded() async {
        guard let month else { return }
        await state.ensureLoaded(accountID: accountID, database: dependencies.database, session: dependencies.session, month: month)
    }
    private func refresh() async {
        guard let month else { return }
        await state.load(accountID: accountID, database: dependencies.database, session: dependencies.session, month: month)
    }
    private func loadMore() async { await state.loadMore(database: dependencies.database, session: dependencies.session) }
}
