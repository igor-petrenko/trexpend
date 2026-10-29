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
           content.summary.currency.id == snapshot.settings.displayCurrencyID, content.summary.month == month {
            return
        }
        await load(database: database, session: session, month: month)
    }

    func load(database: DatabaseStore, session: AppSession, month: CalendarMonth) async {
        let request = UUID(); requestID = request
        isLoadingPage = false; pageError = nil; error = nil
        guard let snapshot = session.snapshot else {
            content = nil; rows = []; next = nil; isLoading = false; return
        }
        if content?.summary.generation != snapshot.generation || content?.summary.currency.id != snapshot.settings.displayCurrencyID || content?.summary.month != month {
            content = nil; rows = []; next = nil
        }
        isLoading = true
        defer { if requestID == request { isLoading = false } }
        do {
            let result = try await database.allHistory(expectedGeneration: snapshot.generation, month: month)
            guard !Task.isCancelled, requestID == request,
                  session.snapshot?.generation == result.summary.generation,
                  session.snapshot?.settings.displayCurrencyID == result.summary.currency.id else { return }
            content = result; rows = result.page.rows; next = result.page.next
        } catch {
            guard !Task.isCancelled, requestID == request, session.snapshot?.generation == snapshot.generation else { return }
            content = nil; rows = []; next = nil
            self.error = AppSession.message(for: error)
        }
    }

    func loadMore(database: DatabaseStore, session: AppSession) async {
        guard let cursor = next, let content, !isLoading, !isLoadingPage,
              session.snapshot?.generation == cursor.generation,
              session.snapshot?.settings.displayCurrencyID == content.summary.currency.id else { return }
        let request = requestID
        isLoadingPage = true; pageError = nil
        defer { if requestID == request { isLoadingPage = false } }
        do {
            let result = try await database.allHistoryPage(expectedGeneration: cursor.generation, cursor: cursor)
            guard !Task.isCancelled, request == requestID, next == cursor,
                  session.snapshot?.generation == cursor.generation,
                  session.snapshot?.settings.displayCurrencyID == content.summary.currency.id else { return }
            let existing = Set(rows.map(\.id))
            rows.append(contentsOf: result.rows.filter { !existing.contains($0.id) })
            next = result.next
        } catch {
            guard !Task.isCancelled, requestID == request, session.snapshot?.generation == cursor.generation else { return }
            pageError = AppSession.message(for: error)
        }
    }
}
