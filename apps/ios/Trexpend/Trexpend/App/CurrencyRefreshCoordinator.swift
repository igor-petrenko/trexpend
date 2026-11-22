import Foundation
import Observation

@MainActor
@Observable
final class CurrencyRefreshCoordinator {
    private(set) var isRefreshing = false
    private(set) var error: String?
    private var task: Task<Bool, Never>?
    private var generation: UUID?
    private var extraIDs: Set<Int64> = []
    private var requestID = UUID()
    private let fetch: @Sendable (String) async throws -> NBUBatch

    init(fetch: @escaping @Sendable (String) async throws -> NBUBatch = { try await NBUClient().fetch(day: $0) }) { self.fetch = fetch }

    func invalidate() {
        requestID = UUID()
        task?.cancel(); task = nil
        isRefreshing = false; error = nil; extraIDs = []
    }

    @discardableResult
    func refresh(dependencies: AppDependencies, manual: Bool = false, extraID: Int64? = nil) async -> Bool {
        guard let snapshot = dependencies.session.snapshot else { return false }
        if generation != snapshot.generation { invalidate(); generation = snapshot.generation }
        if let extraID { extraIDs.insert(extraID) }
        if let task {
            let result = await task.value
            if result, let extraID, dependencies.session.snapshot?.generation == snapshot.generation,
               let current = try? await dependencies.database.currencies(expectedGeneration: snapshot.generation), current.needsRate(extraID) {
                return await refresh(dependencies: dependencies, manual: manual, extraID: extraID)
            }
            return result
        }
        let token = UUID(); requestID = token
        let work = Task { [self] in
            defer {
                if requestID == token { task = nil; isRefreshing = false; extraIDs = [] }
            }
            do {
                let catalog = try await dependencies.database.currencies(expectedGeneration: snapshot.generation)
                guard requestID == token, !Task.isCancelled else { return false }
                let now = Date()
                let missing = catalog.managedIDs.union(extraIDs).contains { catalog.needsRate($0) }
                guard manual || RateDates.due(catalog.sync, missing: missing, now: now) else { return true }
                isRefreshing = true; error = nil
                try await dependencies.database.beginRateRefresh(token: token, automatic: !manual, now: now, expectedGeneration: snapshot.generation)
                let batch = try await fetch(RateDates.kyivDay(now))
                try Task.checkCancellation()
                guard requestID == token, dependencies.session.snapshot?.generation == snapshot.generation else { return false }
                let result = try await dependencies.database.commitRates(batch, extraIDs: extraIDs, token: token, automatic: !manual, now: Date(), expectedGeneration: snapshot.generation)
                guard requestID == token, dependencies.session.snapshot?.generation == snapshot.generation else { return false }
                dependencies.session.ratesDidCommit(result)
                return true
            } catch {
                guard requestID == token, dependencies.session.snapshot?.generation == snapshot.generation else { return false }
                if !(error is CancellationError), (error as? CurrencyRateError) != .cancelled,
                   (error as? DatabaseError) != .staleDataset, !Task.isCancelled {
                    self.error = (error as? CurrencyRateError)?.errorDescription ?? "Rates could not be refreshed. Saved rates were kept. Try again."
                    dependencies.session.rateMetadataDidChange(generation: snapshot.generation)
                }
                return false
            }
        }
        task = work
        return await work.value
    }
}
