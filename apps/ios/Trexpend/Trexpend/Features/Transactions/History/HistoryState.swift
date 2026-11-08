import Foundation
import Observation

@MainActor
@Observable
final class HistoryState {
    private(set) var content: AccountHistorySnapshot?
    private(set) var rows: [HistoryRow] = []
    private(set) var next: HistoryCursor?
    private(set) var isLoading = false
    private(set) var isLoadingPage = false
    private(set) var error: String?
    private(set) var pageError: String?
    private(set) var loadedRevision: UInt64 = 0
    private(set) var loadedAccountRevision: UInt64 = 0
    private(set) var isSavingFavorite = false
    var favoriteError: String?
    private var requestID = UUID()

    var days: [HistoryDay] {
        var result: [HistoryDay] = []
        for row in rows {
            let day = row.date.calendarDay
            if result.last?.id == day { result[result.count - 1].rows.append(row) }
            else { result.append(HistoryDay(id: day, rows: [row])) }
        }
        return result
    }

    func ensureLoaded(accountID: Int64, database: DatabaseStore, session: AppSession, month: CalendarMonth) async {
        if let content, let snapshot = session.snapshot,
           content.generation == snapshot.generation, content.account.id == accountID,
           content.displayCurrency.id == snapshot.settings.displayCurrencyID, content.month == month, loadedRevision == session.transactionRevision, loadedAccountRevision == session.accountRevision {
            return
        }
        await load(accountID: accountID, database: database, session: session, month: month, preservingRange: true)
    }

    func load(accountID: Int64, database: DatabaseStore, session: AppSession, month: CalendarMonth, preservingRange: Bool = false) async {
        let request = UUID(); requestID = request
        isLoadingPage = false; pageError = nil; error = nil
        guard let snapshot = session.snapshot else {
            content = nil; rows = []; next = nil; isLoading = false; return
        }
        if content?.generation != snapshot.generation || content?.account.id != accountID || content?.displayCurrency.id != snapshot.settings.displayCurrencyID || content?.month != month {
            content = nil; rows = []; next = nil
        }
        let revision = session.transactionRevision
        let accountRevision = session.accountRevision
        let through = preservingRange ? rows.last?.date.storage : nil
        let throughID = preservingRange ? rows.last?.id : nil
        isLoading = true
        defer { if requestID == request { isLoading = false } }
        do {
            let result = try await database.history(accountID: accountID, expectedGeneration: snapshot.generation, month: month, retainingThrough: through, retainingID: throughID)
            guard !Task.isCancelled, requestID == request, revision == session.transactionRevision, accountRevision == session.accountRevision,
                  session.snapshot?.generation == result.generation,
                  session.snapshot?.settings.displayCurrencyID == result.displayCurrency.id else { return }
            content = result; rows = result.page.rows; next = result.page.next; loadedRevision = revision; loadedAccountRevision = accountRevision
        } catch {
            guard !Task.isCancelled, requestID == request, revision == session.transactionRevision, accountRevision == session.accountRevision, session.snapshot?.generation == snapshot.generation else { return }
            content = nil; rows = []; next = nil
            self.error = AppSession.message(for: error)
        }
    }

    func toggleFavorite(database: DatabaseStore, session: AppSession, settings: SettingsStore) async {
        guard !isSavingFavorite, let content, let snapshot = session.snapshot,
              content.generation == snapshot.generation else { return }
        let favorite = !content.account.favorite
        isSavingFavorite = true; favoriteError = nil
        defer { isSavingFavorite = false }
        do {
            let saved = try await database.setAccountFavorite(favorite, accountID: content.account.id, expectedGeneration: snapshot.generation)
            guard session.snapshot?.generation == saved.generation else { return }
            self.content?.account.favorite = favorite
            session.accountDidChange(saved, settings: settings)
            // Metadata alone does not invalidate transaction pages or their cursor.
            loadedAccountRevision = session.accountRevision
        } catch {
            guard session.snapshot?.generation == snapshot.generation else { return }
            favoriteError = (error as? LocalizedError)?.errorDescription ?? "The favorite could not be saved. Try again."
        }
    }

    func loadMore(database: DatabaseStore, session: AppSession) async {
        guard let cursor = next, let content, !isLoading, !isLoadingPage, loadedRevision == session.transactionRevision,
              session.snapshot?.generation == cursor.generation,
              session.snapshot?.settings.displayCurrencyID == content.displayCurrency.id else { return }
        let request = requestID
        let revision = loadedRevision
        let accountRevision = session.accountRevision
        isLoadingPage = true; pageError = nil
        defer { if requestID == request { isLoadingPage = false } }
        do {
            let result = try await database.historyPage(accountID: cursor.accountID, expectedGeneration: cursor.generation, cursor: cursor, expectedRevision: revision)
            guard !Task.isCancelled, request == requestID, revision == session.transactionRevision, next == cursor,
                  session.snapshot?.generation == cursor.generation,
                  session.snapshot?.settings.displayCurrencyID == content.displayCurrency.id else { return }
            let existing = Set(rows.map(\.id))
            rows.append(contentsOf: result.rows.filter { !existing.contains($0.id) })
            next = result.next
        } catch {
            guard !Task.isCancelled, requestID == request, revision == session.transactionRevision, accountRevision == session.accountRevision, session.snapshot?.generation == cursor.generation else { return }
            pageError = AppSession.message(for: error)
        }
    }
}
