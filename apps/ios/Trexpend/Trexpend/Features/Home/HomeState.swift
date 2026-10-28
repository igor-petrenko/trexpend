import Foundation
import Observation

@MainActor
@Observable
final class HomeState {
    private(set) var content: HomeSnapshot?
    private(set) var isLoading = false
    private(set) var error: String?
    private var requestID = UUID()

    init(content: HomeSnapshot? = nil) { self.content = content }

    func load(database: DatabaseStore, session: AppSession, month: CalendarMonth) async {
        guard let snapshot = session.snapshot else { content = nil; return }
        let request = UUID()
        requestID = request
        if content?.generation != snapshot.generation || content?.currency.id != snapshot.settings.displayCurrencyID || content?.month != month { content = nil }
        isLoading = content == nil
        error = nil
        defer { if requestID == request { isLoading = false } }
        do {
            let result = try await database.home(expectedGeneration: snapshot.generation, month: month)
            guard !Task.isCancelled, requestID == request,
                  session.snapshot?.generation == result.generation,
                  session.snapshot?.settings.displayCurrencyID == result.currency.id else { return }
            content = result
        } catch {
            guard !Task.isCancelled, requestID == request,
                  session.snapshot?.generation == snapshot.generation else { return }
            content = nil
            self.error = AppSession.message(for: error)
        }
    }
}
