import SwiftUI

struct AllHistoryView: View {
    let dependencies: AppDependencies
    @State private var state = AllHistoryState()
    @State private var deletion = TransactionDeletionState()
    @State private var editing: EditorSelection?
    @State private var visibleTransaction: Int64?
    @State private var pendingAnchor: (id: Int64, date: String)?
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase

    private var month: CalendarMonth? {
        guard let local = try? LocalDateTime(instant: now, timeZone: .current) else { return nil }
        return try? CalendarMonth(year: local.year, month: local.month)
    }
    private struct LoadKey: Equatable { let generation: UUID?; let currency: Int64?; let revision: UInt64; let month: String }
    private var key: LoadKey { LoadKey(generation: dependencies.session.snapshot?.generation, currency: dependencies.session.snapshot?.settings.displayCurrencyID, revision: dependencies.session.transactionRevision, month: month?.start.storage ?? "") }

    var body: some View {
        Group {
            if dependencies.session.snapshot == nil { DatabaseStatusView(session: dependencies.session) }
            else if let content = state.content {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        HomeSummaryView(content: content.summary)
                        HStack {
                            Text("Transactions").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                            Spacer()
                        }
                        if state.rows.isEmpty { ContentUnavailableView("No transactions", systemImage: "list.bullet", description: Text("Your database has no recorded transactions.")) }
                        ForEach(state.days) { day in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(MoneyPresentation.day(day.id)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
                                LazyVStack(spacing: 0) {
                                    ForEach(day.rows) { row in
                                        Button { editing = EditorSelection(id: row.id) } label: {
                                            Group {
                                                if row.transaction.type == .transfer { AllTransferRowView(row: row) }
                                                else { TransactionRowView(row: row.transaction, accountName: row.source.name) }
                                            }.contentShape(Rectangle())
                                        }.buttonStyle(.plain).id(row.id)
                                            .disabled(deletion.isBusy)
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button("Delete", systemImage: "trash") {
                                                    Task { await deletion.request(transactionID: row.id, database: dependencies.database, session: dependencies.session) }
                                                }.tint(.red).disabled(deletion.isBusy)
                                            }
                                        if row.id != day.rows.last?.id { Divider().padding(.leading, 66) }
                                    }
                                }.scrollTargetLayout().background(.background, in: RoundedRectangle(cornerRadius: 18))
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
                }.swipeActionsContainer().scrollPosition(id: $visibleTransaction, anchor: .top).background(Color(.systemGroupedBackground)).refreshable { await refresh() }
            } else if let error = state.error {
                ContentUnavailableView {
                    Label("Could not load history", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: { Button("Retry") { Task { await refresh() } } }
            } else { ProgressView("Loading history") }
        }
        .toolbar(.hidden, for: .navigationBar)
        .transactionDeletion(state: deletion, dependencies: dependencies)
        .fullScreenCover(item: $editing) { selection in
            if let generation = dependencies.session.snapshot?.generation {
                TransactionEditorView(dependencies: dependencies, generation: generation, transactionID: selection.id)
            }
        }
        .transactionCreation(dependencies: dependencies, accountID: nil, enabled: !(state.content?.summary.groups.isEmpty ?? true))
        .onChange(of: dependencies.session.transactionRevision) { _, _ in
            if let id = visibleTransaction, let row = state.rows.first(where: { $0.id == id }) {
                pendingAnchor = (id, row.transaction.date.storage)
            }
        }
        .onChange(of: state.loadedRevision) { _, _ in
            if let anchor = pendingAnchor {
                visibleTransaction = state.rows.first(where: { $0.id == anchor.id })?.id
                    ?? state.rows.first(where: { $0.transaction.date.storage <= anchor.date })?.id
                    ?? state.rows.last?.id
                pendingAnchor = nil
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
        await state.ensureLoaded(database: dependencies.database, session: dependencies.session, month: month)
    }
    private func refresh() async {
        guard let month else { return }
        await state.load(database: dependencies.database, session: dependencies.session, month: month)
    }
    private func loadMore() async { await state.loadMore(database: dependencies.database, session: dependencies.session) }
}
