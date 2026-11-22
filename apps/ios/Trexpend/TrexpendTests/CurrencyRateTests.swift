import Foundation
import Testing
@testable import Trexpend

private struct RateCheckFailure: Error { let message: String }
private func rateCheck(_ condition: Bool, _ message: String) throws {
    guard condition else { throw RateCheckFailure(message: message) }
}
private func rateRejects(_ work: () throws -> Void) throws {
    do { try work() } catch { return }
    throw RateCheckFailure(message: "Invalid operation was accepted.")
}
private func rateDatabase() throws -> SQLiteConnection {
    let resources = try DatabaseResources.bundled()
    let db = try SQLiteConnection(url: nil, create: true)
    try db.execute(resources.schema); try db.execute(resources.defaults)
    try DatabaseMigrator.upgrade(db, resources: resources)
    return db
}
private func rateID(_ db: SQLiteConnection, _ code: String) throws -> Int64 {
    try db.rows("SELECT id FROM currencies WHERE code=?", parameters: [.text(code)])[0].integer("id")
}
private func rateJSON(_ value: String = "42.1234567890123456789012345", units: Int = 1, perUnit: String? = nil, day: String = "21.11.2026", code: String = "USD") -> Data {
    Data("[{\"cc\":\"\(code)\",\"exchangedate\":\"\(day)\",\"rate\":\(value),\"units\":\(units),\"rate_per_unit\":\(perUnit ?? value)}]".utf8)
}

@Suite("Currency rates")
struct CurrencyRateTests {
    @Test func decimalDecodingUnitsAndInvalidResponses() throws {
        let decoded = try NBUClient.decode(rateJSON(), day: "2026-11-21")
        try rateCheck(decoded.rates["USD"] == MoneyCodec.decodeRate("42.1234567890123456789012345"), "JSON decimal precision was lost.")
        let dong = try NBUClient.decode(rateJSON("1.7505", units: 1000, perUnit: "0.0017505", code: "VND"), day: "2026-11-21")
        try rateCheck(dong.rates["VND"] == Decimal(string: "0.0017505"), "VND was normalized twice.")
        for data in [Data("[]".utf8), Data("{}".utf8), rateJSON("0"), rateJSON("-1"), rateJSON(units: 0),
                     rateJSON("1", units: 1000), rateJSON(day: "22.11.2026"), rateJSON(day: "20.11.2026"), rateJSON(code: "UAH")] {
            try rateRejects { _ = try NBUClient.decode(data, day: "2026-11-21") }
        }
        let item = String(data: rateJSON("42"), encoding: .utf8)!
        try rateRejects { _ = try NBUClient.decode(Data((item.dropLast() + "," + item.dropFirst()).utf8), day: "2026-11-21") }
        try rateRejects { _ = try NBUClient.decode(Data(repeating: 32, count: NBUClient.maximumBytes + 1), day: "2026-11-21") }
    }

    @Test func canonicalConversionIgnoresOldPairsAndRoundsAtEnd() throws {
        let converter = try CurrencyConverter(legacy: [ExchangeRate(fromCurrencyID: 2, toCurrencyID: 3, value: 99)], anchorID: 1,
            coefficients: [2: 30, 3: 42, 4: Decimal(string: "0.0016")!], overrides: [:], canonical: true)
        try rateCheck(try converter.suggestedAmount(MonetaryAmount(value: 100, currencyID: 2), to: LedgerCurrency(id: 3, decimalPlaces: 2)) == Decimal(string: "71.43"), "Stale direct pair was used.")
        try rateCheck(try converter.convert(MonetaryAmount(value: 1000, currencyID: 1), to: 4) == 625000, "UAH to VND failed.")
        let amounts = [MonetaryAmount(value: Decimal(string: "0.01")!, currencyID: 1), MonetaryAmount(value: Decimal(string: "0.01")!, currencyID: 1)]
        let rounding = try CurrencyConverter(legacy: [], anchorID: 1, coefficients: [2: 3], overrides: [:], canonical: true)
        try rateCheck(try rounding.total(amounts, to: LedgerCurrency(id: 2, decimalPlaces: 2)) == Decimal(string: "0.01"), "Amounts were rounded before aggregation.")
        try rateCheck(try converter.convert(MonetaryAmount(value: 7, currencyID: 99), to: 99) == 7, "Identity required a quote.")
        try rateRejects { _ = try converter.convert(MonetaryAmount(value: 1, currencyID: 99), to: 2) }
    }

    @Test func legacyAndManualPrecedence() throws {
        let old = [ExchangeRate(fromCurrencyID: 2, toCurrencyID: 1, value: 30), ExchangeRate(fromCurrencyID: 3, toCurrencyID: 1, value: 42)]
        let legacy = try CurrencyConverter(legacy: old, anchorID: 1, coefficients: [:], overrides: [3: 45], canonical: false)
        try rateCheck(try legacy.convert(MonetaryAmount(value: 1, currencyID: 3), to: 2) == Decimal(string: "1.5"), "Manual USD was bypassed by a legacy pair.")
        try rateCheck(try legacy.convert(MonetaryAmount(value: 1, currencyID: 2), to: 1) == 30, "Unrelated legacy conversion changed.")
        let manualCAD = try CurrencyConverter(legacy: [], anchorID: 1, coefficients: [2: 30,3:42], overrides: [2: 35], canonical: true)
        try rateCheck(try manualCAD.convert(MonetaryAmount(value: 10, currencyID: 3), to: 2) == 12, "Display-currency override did not affect the denominator.")
    }

    @Test func migrationValidationAndRollback() throws {
        let resources = try DatabaseResources.bundled()
        let db = try SQLiteConnection(url: nil, create: true); defer { try? db.close() }
        try db.execute(resources.schema); try db.execute(resources.defaults)
        var old = resources; old.currencyMigration = ""
        try DatabaseMigrator.upgrade(db, resources: old)
        let currencies = try db.rows("SELECT * FROM currencies").map(\.values)
        var broken = resources; broken.currencyMigration += "\nSELECT missing FROM missing_table;"
        try rateRejects { try DatabaseMigrator.upgrade(db, resources: broken) }
        try rateCheck(try DatabaseMigrator.version(db) == 5, "Failed migration advanced the version.")
        try rateCheck(try db.rows("SELECT * FROM currencies").map(\.values) == currencies, "Failed migration modified the catalog.")
        try DatabaseMigrator.upgrade(db, resources: resources)
        _ = try DatabaseValidator(resources: resources).validate(db, generation: UUID())
        try rateCheck(try DatabaseMigrator.version(db) == 7, "Migration did not reach v7.")
        try rateCheck(try CurrencyRead.sync(db).canonical == false, "Migration discarded the legacy snapshot.")
        try db.run("UPDATE currency_sync_state SET last_attempt_at='invalid'")
        try rateRejects { _ = try DatabaseValidator(resources: resources).validate(db, generation: UUID()) }
    }

    @Test func manualBatchAtomicityAndRestoration() throws {
        let db = try rateDatabase(); defer { try? db.close() }
        let g = UUID(); let now = Date(); let day = RateDates.kyivDay(now)
        let usd = try rateID(db, "USD"); let cad = try rateID(db, "CAD")
        try db.transaction { try CurrencyWrite.manual(db, id: usd, value: "43.123456789", original: nil, now: now) }
        let original = try CurrencyRead.rates(db)[usd]
        try db.transaction { try CurrencyWrite.batch(db, batch: NBUBatch(day: day, rates: ["USD":42,"CAD":30]), extraIDs: [cad], generation: g, now: now) }
        let after = try CurrencyRead.rates(db)
        try rateCheck(after[usd]?.manual == original?.manual && after[usd]?.manualUpdatedAt == original?.manualUpdatedAt, "NBU overwrote the manual layer.")
        try rateCheck(after[usd]?.nbu == 42, "Inactive NBU value was not refreshed.")
        let beforeFailure = try db.rows("SELECT * FROM currency_rates").map(\.values)
        try rateRejects { try db.transaction { try CurrencyWrite.batch(db, batch: NBUBatch(day: day, rates: ["USD":44]), extraIDs: [cad], generation: g, now: now) } }
        try rateCheck(try db.rows("SELECT * FROM currency_rates").map(\.values) == beforeFailure, "Failed batch changed rates.")
        try db.transaction { try CurrencyWrite.manual(db, id: usd, value: nil, original: original, now: now) }
        try rateCheck(try CurrencyRead.rates(db)[usd]?.effective == 42, "Returning to NBU failed.")
        try rateRejects { try db.transaction { try CurrencyWrite.manual(db, id: usd, value: "44", original: original, now: now) } }
        let uah = try rateID(db, "UAH")
        try rateRejects { try CurrencyWrite.manual(db, id: uah, value: "2", original: nil, now: now) }
        for invalid in ["0", "-1", "NaN", "1e1000"] { try rateRejects { try CurrencyWrite.manual(db, id: usd, value: invalid, original: nil, now: now) } }
        _ = try DatabaseValidator(resources: .bundled()).validate(db, generation: g)
    }

    @Test func missingNBUDoesNotRemoveManualAndUnsupportedDoesNotBlock() throws {
        let db = try rateDatabase(); defer { try? db.close() }
        let usd = try rateID(db, "USD"); let btc = try rateID(db, "BTC")
        let now = Date()
        try CurrencyWrite.manual(db, id: usd, value: "42", original: nil, now: now)
        let original = try CurrencyRead.rates(db)[usd]
        try rateRejects { try CurrencyWrite.manual(db, id: usd, value: nil, original: original, now: now) }
        try rateCheck(try CurrencyRead.rates(db)[usd]?.manual == 42, "Missing automatic quote destroyed the override.")
        try db.transaction { try CurrencyWrite.batch(db, batch: NBUBatch(day: RateDates.kyivDay(now), rates: ["USD": 41]), extraIDs: [btc], generation: UUID(), now: now) }
        try rateCheck(try CurrencyRead.sync(db).canonical, "Unsupported catalog entry blocked supported rates.")
    }

    @Test func dailySchedulingRetriesAndTimezones() throws {
        let now = RateDates.instant("2026-11-21T18:00:00Z")!
        let utc = TimeZone(secondsFromGMT: 0)!
        let good = CurrencySync(automatic: true, canonical: true, lastAttempt: "2026-11-21T17:59:59Z", lastSuccess: "2026-11-21T18:00:00Z", requestedDate: "2026-11-21")
        try rateCheck(!RateDates.due(good, missing: false, now: now, timeZone: utc), "Successful day refreshed twice.")
        try rateCheck(RateDates.due(good, missing: true, now: now, timeZone: utc), "New required quote was throttled after success.")
        let failed = CurrencySync(automatic: true, canonical: false, lastAttempt: "2026-11-21T17:59:00Z", lastSuccess: nil, requestedDate: nil)
        try rateCheck(!RateDates.due(failed, missing: true, now: now, timeZone: utc), "Failed attempt retried without cooldown.")
        try rateCheck(RateDates.due(failed, missing: true, now: now.addingTimeInterval(301), timeZone: utc), "Failure was treated as daily success.")
        let future = CurrencySync(automatic: true, canonical: true, lastAttempt: "2027-01-01T00:00:00Z", lastSuccess: "2027-01-01T00:00:00Z", requestedDate: "2027-01-01")
        try rateCheck(RateDates.due(future, missing: false, now: now, timeZone: utc), "Restored future date suppressed updates.")
        let off = CurrencySync(automatic: false, canonical: true, lastAttempt: nil, lastSuccess: nil, requestedDate: nil)
        try rateCheck(!RateDates.due(off, missing: true, now: now), "Disabled automatic update still ran.")
        try rateCheck(RateDates.due(good, missing: false, now: now.addingTimeInterval(86400), timeZone: utc), "Next day did not refresh.")
    }

    @Test func requestGuardsBackupImportAndFrozenEditor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CurrencyTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let life = try DatabaseLifecycle(directory: root, resources: .bundled())
        let first = try life.open(); let now = Date(); let token = UUID()
        let before = try life.editor(transactionID: nil, expectedGeneration: first.generation)
        try life.beginRateRefresh(token: token, automatic: true, now: now, expectedGeneration: first.generation)
        _ = try life.setAutomaticRates(false, expectedGeneration: first.generation)
        let batch = NBUBatch(day: RateDates.kyivDay(now), rates: ["USD":42,"CAD":30])
        try rateRejects { _ = try life.commitRates(batch, extraIDs: [], token: token, automatic: true, now: now, expectedGeneration: first.generation) }
        let usd = try life.currencies(expectedGeneration: first.generation).displayID
        _ = try life.saveManualRate(id: usd, value: "44", original: nil, now: now, expectedGeneration: first.generation)
        let a = UUID(); let b = UUID()
        try life.beginRateRefresh(token: a, automatic: false, now: now, expectedGeneration: first.generation)
        try life.beginRateRefresh(token: b, automatic: false, now: now, expectedGeneration: first.generation)
        try rateRejects { _ = try life.commitRates(batch, extraIDs: [], token: a, automatic: false, now: now, expectedGeneration: first.generation) }
        _ = try life.commitRates(batch, extraIDs: [], token: b, automatic: false, now: now, expectedGeneration: first.generation)
        let catalog = try life.currencies(expectedGeneration: first.generation)
        let uah = catalog.currencies.first { $0.code == "UAH" }!.id
        try rateRejects { _ = try before.converter.convert(MonetaryAmount(value: 1, currencyID: usd), to: uah) }
        try rateCheck(try catalog.converter.convert(MonetaryAmount(value: 1, currencyID: usd), to: uah) == 44, "Fresh converter did not see the manual quote.")
        let exported = try life.exportSnapshot(expectedGeneration: first.generation)
        let restored = try life.importDatabase(from: exported, expectedGeneration: first.generation)
        let restoredCatalog = try life.currencies(expectedGeneration: restored.generation)
        try rateCheck(restoredCatalog.rates[usd]?.manual == 44 && !restoredCatalog.sync.automatic, "Import lost rates or preferences.")
        try rateRejects { _ = try life.commitRates(batch, extraIDs: [], token: b, automatic: false, now: now, expectedGeneration: first.generation) }
        let reset = try life.reset(expectedGeneration: restored.generation)
        let clean = try life.currencies(expectedGeneration: reset.generation)
        try rateCheck(clean.rates.isEmpty && clean.sync.automatic && !clean.sync.canonical, "Reset retained old financial preferences.")
        try life.close()
    }
}

private actor RateGate {
    private var continuation: CheckedContinuation<NBUBatch, Error>?
    private(set) var calls = 0
    func fetch(_ day: String) async throws -> NBUBatch {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func wait() async throws {
        for _ in 0..<10000 {
            if continuation != nil { return }
            await Task.yield()
        }
        throw RateCheckFailure(message: "Mock refresh did not start.")
    }
    func finish(_ batch: NBUBatch) { continuation?.resume(returning: batch); continuation = nil }
}

extension CurrencyRateTests {
    @Test @MainActor func coalescedFetchPreservesConcurrentManualEdit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RateConcurrency-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = RateGate()
        let coordinator = CurrencyRefreshCoordinator(fetch: { try await gate.fetch($0) })
        let dependencies = AppDependencies(directory: root, rates: coordinator)
        await dependencies.session.start(store: dependencies.database, settings: dependencies.settings)
        let g = dependencies.session.snapshot!.generation
        let catalog = try await dependencies.database.currencies(expectedGeneration: g)
        let usd = catalog.displayID; let cad = catalog.currencies.first { $0.code == "CAD" }!.id
        let first = Task { await coordinator.refresh(dependencies: dependencies, manual: true) }
        try await gate.wait()
        let second = Task { await coordinator.refresh(dependencies: dependencies, manual: true, extraID: cad) }
        let manual = try await dependencies.database.saveManualRate(id: usd, value: "44", original: nil, now: Date(), expectedGeneration: g)
        dependencies.session.ratesDidCommit(manual)
        await Task.yield()
        await gate.finish(NBUBatch(day: RateDates.kyivDay(Date()), rates: ["USD":42,"CAD":30]))
        let firstResult = await first.value; let secondResult = await second.value
        try rateCheck(firstResult && secondResult, "Coalesced refresh failed.")
        let after = try await dependencies.database.currencies(expectedGeneration: g)
        try rateCheck(after.rates[usd]?.manual == 44 && after.rates[usd]?.nbu == 42, "Concurrent manual edit was overwritten.")
        let calls = await gate.calls
        try rateCheck(after.rates[cad]?.nbu == 30 && calls == 1, "Concurrent detail did not join the batch.")
        try await dependencies.database.close()
    }

    @Test @MainActor func refreshAfterDatasetReplacementCannotPublish() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RateReplacement-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = RateGate()
        let coordinator = CurrencyRefreshCoordinator(fetch: { try await gate.fetch($0) })
        let dependencies = AppDependencies(directory: root, rates: coordinator)
        await dependencies.session.start(store: dependencies.database, settings: dependencies.settings)
        let g = dependencies.session.snapshot!.generation
        let work = Task { await coordinator.refresh(dependencies: dependencies, manual: true) }
        try await gate.wait()
        let replacement = try await dependencies.database.reset(expectedGeneration: g)
        dependencies.session.publish(replacement, settings: dependencies.settings)
        await gate.finish(NBUBatch(day: RateDates.kyivDay(Date()), rates: ["USD":42]))
        try rateCheck(await work.value == false, "Old-dataset request reported success.")
        let fresh = try await dependencies.database.currencies(expectedGeneration: replacement.generation)
        try rateCheck(fresh.rates.isEmpty && !fresh.sync.canonical, "Old response contaminated the replacement.")
        try await dependencies.database.close()
    }

    @Test @MainActor func rateSummaryRefreshRetainsHistoryPagesAndDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RateHistory-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = try DatabaseResources.bundled()
        let seed = try DatabaseLifecycle(directory: root, resources: resources)
        _ = try seed.open(); try seed.close()
        let db = try SQLiteConnection(url: root.appendingPathComponent("ledger.sqlite"))
        let usd = try rateID(db,"USD"); let cad = try rateID(db,"CAD")
        try db.run("UPDATE app_settings SET display_currency_id=?", parameters: [.integer(cad)])
        try db.run("INSERT INTO accounts(id,name,currency_id,initial_balance,status,account_type,created_at,updated_at) VALUES(1,'Synthetic USD',?,'100.00',1,1,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')", parameters: [.integer(usd)])
        let category = try db.rows("SELECT id FROM categories LIMIT 1")[0].integer("id")
        for id in 1...125 {
            try db.run("INSERT INTO transactions(id,transaction_type,account_id,amount,date,category_id,fee,created_at,updated_at) VALUES(?,1,1,'0.10','2026-10-01T12:00:00',?,'0.00','2026-10-01T12:00:00Z','2026-10-01T12:00:00Z')", parameters: [.integer(Int64(id)),.integer(category)])
        }
        try db.run("INSERT INTO exchange_rates(from_currency_id,to_currency_id,rate,updated_at) VALUES(?,?,'1.5','2026-01-01T00:00:00Z')",parameters: [.integer(usd),.integer(cad)])
        let nativeBefore = try db.rows("SELECT * FROM transactions ORDER BY id").map(\.values)
        try db.close()
        let dependencies = AppDependencies(directory: root)
        await dependencies.session.start(store: dependencies.database, settings: dependencies.settings)
        let g = dependencies.session.snapshot!.generation
        let month = try CalendarMonth(year: 2026,month: 10)
        let all = AllHistoryState(); let account = HistoryState()
        await all.ensureLoaded(database: dependencies.database, session: dependencies.session, month: month)
        await account.ensureLoaded(accountID: 1, database: dependencies.database, session: dependencies.session, month: month)
        await all.loadMore(database: dependencies.database, session: dependencies.session)
        await account.loadMore(database: dependencies.database, session: dependencies.session)
        let allRows = all.rows; let accountRows = account.rows; let allCursor = all.next; let accountCursor = account.next
        let draft = try await dependencies.database.editor(transactionID: nil, expectedGeneration: g)
        let now = Date(); let token = UUID()
        try await dependencies.database.beginRateRefresh(token: token, automatic: false, now: now, expectedGeneration: g)
        let commit = try await dependencies.database.commitRates(NBUBatch(day: RateDates.kyivDay(now),rates: ["USD":42,"CAD":30]), extraIDs: [],token: token,automatic: false,now: now,expectedGeneration: g)
        dependencies.session.ratesDidCommit(commit)
        await all.ensureLoaded(database: dependencies.database,session: dependencies.session,month: month)
        await account.ensureLoaded(accountID: 1,database: dependencies.database,session: dependencies.session,month: month)
        try rateCheck(all.rows == allRows && all.next == allCursor && account.rows == accountRows && account.next == accountCursor, "Rate refresh reset retained history pages.")
        try rateCheck(all.rows.count == 100 && account.rows.count == 100, "History fixture did not retain multiple pages.")
        try rateCheck(all.content?.summary.totalBalance == Decimal(string:"122.50") && account.content?.convertedBalance == Decimal(string:"122.50"), "Summary did not use new rates.")
        try rateCheck(try draft.converter.convert(MonetaryAmount(value:1,currencyID:usd),to:cad) == Decimal(string:"1.5"), "Open editor converter changed.")
        let audit = try SQLiteConnection(url: root.appendingPathComponent("ledger.sqlite"))
        try rateCheck(try audit.rows("SELECT * FROM transactions ORDER BY id").map(\.values) == nativeBefore, "Rate refresh rewrote transactions.")
        try audit.close(); try await dependencies.database.close()
    }
}

private actor FailingRateFeed {
    private(set) var calls = 0
    func fetch(_ day: String) throws -> NBUBatch {
        calls += 1
        throw URLError(.notConnectedToInternet)
    }
}

extension CurrencyRateTests {
    @Test @MainActor func failedRefreshPreservesRatesAndManualRetryBypassesCooldown() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RateFailure-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let feed = FailingRateFeed()
        let coordinator = CurrencyRefreshCoordinator(fetch: { try await feed.fetch($0) })
        let dependencies = AppDependencies(directory: root, rates: coordinator)
        await dependencies.session.start(store: dependencies.database, settings: dependencies.settings)
        let g = dependencies.session.snapshot!.generation
        let before = try await dependencies.database.currencies(expectedGeneration: g)
        let result = await coordinator.refresh(dependencies: dependencies)
        try rateCheck(!result && coordinator.error != nil, "Failed download was not reported.")
        let failed = try await dependencies.database.currencies(expectedGeneration: g)
        try rateCheck(failed.rates == before.rates && failed.sync.lastSuccess == nil && failed.sync.lastAttempt != nil, "Failure changed cached rates or marked daily success.")
        _ = await coordinator.refresh(dependencies: dependencies)
        let automaticCalls = await feed.calls
        try rateCheck(automaticCalls == 1, "Foreground retry ignored the failure cooldown.")
        _ = await coordinator.refresh(dependencies: dependencies, manual: true)
        let manualCalls = await feed.calls
        try rateCheck(manualCalls == 2, "Manual retry did not bypass cooldown.")
        try await dependencies.database.close()
    }

    @Test @MainActor func disablingAutomaticDuringFetchDiscardsResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RateDisable-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = RateGate()
        let coordinator = CurrencyRefreshCoordinator(fetch: { try await gate.fetch($0) })
        let dependencies = AppDependencies(directory: root, rates: coordinator)
        await dependencies.session.start(store: dependencies.database, settings: dependencies.settings)
        let g = dependencies.session.snapshot!.generation
        let work = Task { await coordinator.refresh(dependencies: dependencies) }
        try await gate.wait()
        coordinator.invalidate()
        _ = try await dependencies.database.setAutomaticRates(false, expectedGeneration: g)
        await gate.finish(NBUBatch(day: RateDates.kyivDay(Date()), rates: ["USD":42]))
        let result = await work.value
        let after = try await dependencies.database.currencies(expectedGeneration: g)
        try rateCheck(!result && after.rates.isEmpty && !after.sync.automatic, "Disabling automatic updates did not invalidate the pending response.")
        try rateCheck(coordinator.error == nil && !coordinator.isRefreshing, "Cancellation produced a refresh error.")
        try await dependencies.database.close()
    }

    @Test func metadataOnlyRefreshDoesNotInvalidateValuation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RateMetadata-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let life = try DatabaseLifecycle(directory: root, resources: .bundled())
        let g = try life.open().generation
        let now = Date(); let batch = NBUBatch(day: RateDates.kyivDay(now), rates: ["USD":42])
        let first = UUID()
        try life.beginRateRefresh(token: first, automatic: false, now: now, expectedGeneration: g)
        let initial = try life.commitRates(batch, extraIDs: [], token: first, automatic: false, now: now, expectedGeneration: g)
        try rateCheck(initial.changed, "First activation did not invalidate valuations.")
        let next = UUID()
        try life.beginRateRefresh(token: next, automatic: false, now: now, expectedGeneration: g)
        let repeated = try life.commitRates(batch, extraIDs: [], token: next, automatic: false, now: now, expectedGeneration: g)
        try rateCheck(!repeated.changed && repeated.catalog.sync.lastSuccess != nil, "Metadata-only refresh invalidated histories.")
        try life.close()
    }
}

extension CurrencyRateTests {
    @Test func batchStoresUnusedCatalogCurrenciesAndPreservesManualOverrides() throws {
        let db = try rateDatabase(); defer { try? db.close() }
        let generation = UUID(); let now = Date(); let day = RateDates.kyivDay(now)
        let cad = try rateID(db, "CAD"); let gbp = try rateID(db, "GBP"); let vnd = try rateID(db, "VND")
        let before = try CurrencyRead.catalog(db, generation: generation)
        try rateCheck(!before.usedIDs.contains(cad) && !before.usedIDs.contains(gbp) && !before.usedIDs.contains(vnd), "Fixture currencies are already used.")
        let rates: [String: Decimal] = ["USD":42, "CAD":30, "GBP":54, "VND":Decimal(string:"0.0016")!, "ZZZ":5]
        try db.transaction { try CurrencyWrite.batch(db, batch: NBUBatch(day: day, rates: rates), extraIDs: [], generation: generation, now: now) }
        let first = try CurrencyRead.catalog(db, generation: generation)
        try rateCheck(first.rates[cad]?.nbu == 30 && first.rates[gbp]?.nbu == 54 && first.rates[vnd]?.nbu == Decimal(string:"0.0016"), "Unused provider quotes were not saved.")
        try rateCheck(!first.usedIDs.contains(cad) && !first.usedIDs.contains(gbp) && !first.usedIDs.contains(vnd), "Caching rates changed the Used filter.")
        try rateCheck(first.currencies == before.currencies, "Provider quotes created or changed catalog entries.")
        try db.transaction { try CurrencyWrite.manual(db, id: gbp, value: "55", original: first.rates[gbp], now: now) }
        var updated = rates; updated["CAD"] = 31; updated["GBP"] = 56
        try db.transaction { try CurrencyWrite.batch(db, batch: NBUBatch(day: day, rates: updated), extraIDs: [], generation: generation, now: now) }
        let second = try CurrencyRead.catalog(db, generation: generation)
        try rateCheck(second.rates[cad]?.nbu == 31 && second.rates[gbp]?.nbu == 56 && second.rates[gbp]?.manual == 55, "Full refresh failed to update quotes or overwrote an override.")
        _ = try DatabaseValidator(resources: .bundled()).validate(db, generation: generation)
    }
}

extension CurrencyRateTests {
    @Test func comparisonMigrationDefaultsPreservesRatesAndRollsBackFailure() throws {
        let resources = try DatabaseResources.bundled()
        let db = try SQLiteConnection(url: nil, create: true); defer { try? db.close() }
        try db.execute(resources.schema); try db.execute(resources.defaults)
        var old = resources; old.comparisonMigration = ""
        try DatabaseMigrator.upgrade(db, resources: old)
        try rateCheck(try DatabaseMigrator.version(db) == 6, "Fixture is not v6.")
        let usd = try rateID(db,"USD")
        try db.transaction { try CurrencyWrite.manual(db, id: usd, value: "42.1234567", original: nil, now: Date()) }
        let rates = try db.rows("SELECT * FROM currency_rates").map(\.values)
        let preferences = try db.rows("SELECT * FROM currency_sync_state").map(\.values)
        var broken = resources; broken.comparisonMigration += "\nSELECT invalid_column FROM invalid_table;"
        try rateRejects { try DatabaseMigrator.upgrade(db, resources: broken) }
        try rateCheck(try DatabaseMigrator.version(db) == 6, "Failed comparison migration advanced version.")
        try rateCheck(try db.rows("SELECT name FROM sqlite_schema WHERE name='currency_comparison_currencies'").isEmpty, "Failed migration left a partial table.")
        try DatabaseMigrator.upgrade(db, resources: resources)
        let catalog = try CurrencyRead.catalog(db, generation: UUID())
        try rateCheck(catalog.comparisons(excluding: -1).map(\.code) == ["UAH","CAD","USD","EUR"], "Comparison defaults have the wrong order.")
        try rateCheck(try db.rows("SELECT * FROM currency_rates").map(\.values) == rates && db.rows("SELECT * FROM currency_sync_state").map(\.values) == preferences, "Comparison migration changed rate data.")
        _ = try DatabaseValidator(resources: resources).validate(db, generation: UUID())
    }

    @Test func comparisonSelectionOrderEmptyAndConflictChecks() throws {
        let db = try rateDatabase(); defer { try? db.close() }
        let g = UUID(); let first = try CurrencyRead.catalog(db, generation: g)
        let gbp = try rateID(db,"GBP"); let jpy = try rateID(db,"JPY")
        try db.transaction { try CurrencyComparisonWrite.save(db, ids: [jpy,gbp], original: first.comparisonIDs) }
        let saved = try CurrencyRead.catalog(db, generation: g)
        try rateCheck(saved.comparisonIDs == [jpy,gbp], "Selection order was not saved.")
        try rateCheck(saved.comparisons(excluding: jpy).map(\.id) == [gbp] && saved.comparisonIDs == [jpy,gbp], "Hiding the opened currency changed global selection.")
        try rateRejects { try db.transaction { try CurrencyComparisonWrite.save(db, ids: [gbp], original: first.comparisonIDs) } }
        for invalid in [[gbp,gbp], [-1], [Int64.max]] {
            try rateRejects { try db.transaction { try CurrencyComparisonWrite.save(db, ids: invalid, original: saved.comparisonIDs) } }
            try rateCheck(try CurrencyComparisonRead.ids(db) == saved.comparisonIDs, "Invalid save changed selection.")
        }
        try db.transaction { try CurrencyComparisonWrite.save(db, ids: [], original: saved.comparisonIDs) }
        try rateCheck(try CurrencyRead.catalog(db, generation: g).comparisonIDs.isEmpty && CurrencyComparisonRead.ids(db).isEmpty, "Empty selection was silently reseeded.")
        _ = try DatabaseValidator(resources: .bundled()).validate(db, generation: g)
    }

    @Test func comparisonAmountsAreExactAndApplyInBothDirections() throws {
        let text = "100.12345678901234567890123"
        try rateCheck(try MoneyCodec.parseExactInput(text) == MoneyCodec.decodeRate(text), "Comparison amount was rounded to a monetary scale.")
        try rateCheck(try MoneyCodec.parseExactInput(" 12,345 ") == Decimal(string:"12.345"), "Comma input was not parsed.")
        try rateCheck(try MoneyCodec.parseExactInput("0.000") == 0, "Zero comparison amount was rejected.")
        for invalid in ["", "-1", "NaN", "1e1000", "1.2.3"] { try rateRejects { _ = try MoneyCodec.parseExactInput(invalid) } }
        let converter = try CurrencyConverter(legacy: [], anchorID: 1, coefficients: [2:Decimal(string:"1.5")!,3:30], overrides: [:], canonical: true)
        let amount = try MoneyCodec.parseExactInput("100")
        try rateCheck(CurrencyComparison.value(amount: amount, from: 2, to: 3, converter: converter) == .value(5), "Forward comparison did not use the amount.")
        try rateCheck(CurrencyComparison.value(amount: amount, from: 3, to: 2, converter: converter) == .value(2000), "Reverse comparison used a unit quote instead of the amount.")
        try rateCheck(CurrencyComparison.value(amount: 0, from: 2, to: 3, converter: converter) == .value(0), "Zero conversion failed.")
        try rateCheck(CurrencyComparison.value(amount: 100, from: 2, to: 99, converter: converter) == .unavailable, "Missing quote was treated as parity.")
        try rateCheck(CurrencyComparison.value(amount: -1, from: 2, to: 3, converter: converter) == .invalid, "Negative comparison was accepted.")
    }

    @Test @MainActor func comparisonSettingsSurviveBackupAndDoNotInvalidateRates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ComparisonBackup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let dependencies = AppDependencies(directory: root)
        await dependencies.session.start(store: dependencies.database, settings: dependencies.settings)
        let g = dependencies.session.snapshot!.generation
        let catalog = try await dependencies.database.currencies(expectedGeneration: g)
        let chosen = Array(catalog.comparisonIDs.reversed())
        _ = try await dependencies.database.saveComparisonCurrencies(chosen, original: catalog.comparisonIDs, expectedGeneration: g)
        dependencies.session.rateMetadataDidChange(generation: g)
        try rateCheck(dependencies.session.currencyRevision == 1 && dependencies.session.rateRevision == 0 && dependencies.session.transactionRevision == 0, "Comparison preferences invalidated financial summaries.")
        let exported = try await dependencies.database.exportSnapshot(expectedGeneration: g)
        let replaced = try await dependencies.database.importDatabase(from: exported, expectedGeneration: g)
        let restored = try await dependencies.database.currencies(expectedGeneration: replaced.generation)
        try rateCheck(restored.comparisonIDs == chosen, "Backup/import lost comparison order.")
        do {
            _ = try await dependencies.database.saveComparisonCurrencies([], original: chosen, expectedGeneration: g)
            throw RateCheckFailure(message: "Old dataset accepted a comparison save.")
        } catch DatabaseError.staleDataset {}
        let reset = try await dependencies.database.reset(expectedGeneration: replaced.generation)
        let fresh = try await dependencies.database.currencies(expectedGeneration: reset.generation)
        try rateCheck(fresh.comparisons(excluding: -1).map(\.code) == ["UAH","CAD","USD","EUR"], "Reset did not restore comparison defaults.")
        try await dependencies.database.close()
    }
}
