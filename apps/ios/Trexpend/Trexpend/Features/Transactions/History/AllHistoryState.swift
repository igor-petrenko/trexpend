import Foundation
import Observation

@MainActor
@Observable
final class AllHistoryState {
    private(set) var content: AllHistorySnapshot?
    private(set) var rows: [AllHistoryRow] = []
    private(set) var next: AllHistoryCursor?
    private(set) var isLoading = false
    private(set) var isLoadingPage = false
    private(set) var error: String?
    private(set) var pageError: String?
    private(set) var loadedRevision: UInt64 = 0
    private var requestID = UUID()

    var days: [AllHistoryDay] {
        var result: [AllHistoryDay] = []
        for row in rows {
            let day = row.transaction.date.calendarDay
            if result.last?.id == day { result[result.count - 1].rows.append(row) }
            else { result.append(AllHistoryDay(id: day, rows: [row])) }
        }
        return result
    }

    func ensureLoaded(database: DatabaseStore, session: AppSession, month: CalendarMonth) async {
        if let content, let snapshot = session.snapshot,
           content.summary.generation == snapshot.generation,
           content.summary.currency.id == snapshot.settings.displayCurrencyID, content.summary.month == month, loadedRevision == session.transactionRevision {
            return
        }
        await load(database: database, session: session, month: month, preservingRange: true)
    }

    func load(database: DatabaseStore, session: AppSession, month: CalendarMonth, preservingRange: Bool = false) async {
        let request = UUID(); requestID = request
        isLoadingPage = false; pageError = nil; error = nil
        guard let snapshot = session.snapshot else {
            content = nil; rows = []; next = nil; isLoading = false; return
        }
        if content?.summary.generation != snapshot.generation || content?.summary.currency.id != snapshot.settings.displayCurrencyID || content?.summary.month != month {
            content = nil; rows = []; next = nil
        }
        let revision = session.transactionRevision
        let through = preservingRange ? rows.last?.transaction.date.storage : nil
        let throughID = preservingRange ? rows.last?.id : nil
        isLoading = true
        defer { if requestID == request { isLoading = false } }
        do {
            let result = try await database.allHistory(expectedGeneration: snapshot.generation, month: month, retainingThrough: through, retainingID: throughID)
            guard !Task.isCancelled, requestID == request, revision == session.transactionRevision,
                  session.snapshot?.generation == result.summary.generation,
                  session.snapshot?.settings.displayCurrencyID == result.summary.currency.id else { return }
            content = result; rows = result.page.rows; next = result.page.next; loadedRevision = revision
        } catch {
            guard !Task.isCancelled, requestID == request, revision == session.transactionRevision, session.snapshot?.generation == snapshot.generation else { return }
            content = nil; rows = []; next = nil
            self.error = AppSession.message(for: error)
        }
    }

    func loadMore(database: DatabaseStore, session: AppSession) async {
        guard let cursor = next, let content, !isLoading, !isLoadingPage, loadedRevision == session.transactionRevision,
              session.snapshot?.generation == cursor.generation,
              session.snapshot?.settings.displayCurrencyID == content.summary.currency.id else { return }
        let request = requestID
        let revision = loadedRevision
        isLoadingPage = true; pageError = nil
        defer { if requestID == request { isLoadingPage = false } }
        do {
            let result = try await database.allHistoryPage(expectedGeneration: cursor.generation, cursor: cursor, expectedRevision: revision)
            guard !Task.isCancelled, request == requestID, revision == session.transactionRevision, next == cursor,
                  session.snapshot?.generation == cursor.generation,
                  session.snapshot?.settings.displayCurrencyID == content.summary.currency.id else { return }
            let existing = Set(rows.map(\.id))
            rows.append(contentsOf: result.rows.filter { !existing.contains($0.id) })
            next = result.next
        } catch {
            guard !Task.isCancelled, requestID == request, revision == session.transactionRevision, session.snapshot?.generation == cursor.generation else { return }
            pageError = AppSession.message(for: error)
        }
    }
}
