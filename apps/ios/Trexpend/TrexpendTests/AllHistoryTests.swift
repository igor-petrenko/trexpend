import Foundation
import Testing
import SwiftUI
@testable import Trexpend

private struct AllHistoryFixture {
    let root: URL
    let resources: DatabaseResources
    var url: URL { root.appendingPathComponent("ledger.sqlite") }
    var month: CalendarMonth { try! CalendarMonth(year: 2026, month: 10) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AllHistoryTest-" + UUID().uuidString)
        resources = try .bundled()
        let life = try DatabaseLifecycle(directory: root, resources: resources)
        _ = try life.open(); try life.close()
        let db = try SQLiteConnection(url: url)
        try db.run("INSERT INTO accounts(id,name,currency_id,initial_balance,status,account_type,created_at,updated_at) VALUES (1,'Synthetic source',1,'1000.00',1,2,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z'),(2,'Synthetic target',34,'500.00',1,3,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z'),(3,'Synthetic closed',1,'100.00',2,1,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')")
        try db.run("INSERT INTO exchange_rates(from_currency_id,to_currency_id,rate,updated_at) VALUES (1,34,'1.37','2026-01-01T00:00:00Z')")
        try db.close()
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
    func lifecycle() throws -> DatabaseLifecycle { try DatabaseLifecycle(directory: root, resources: resources) }
    func insert(_ db: SQLiteConnection, id: Int64, type: Int64 = 1, source: Int64 = 1,
                amount: String = "1.00", date: String = "2026-10-17T12:00:00",
                destination: Int64? = nil, received: String? = nil,
                fee: String = "0.00", charged: Int64? = nil) throws {
        let feeAccount = type == 3 ? (charged ?? source) : nil
        try db.run("INSERT INTO transactions(id,transaction_type,account_id,amount,date,category_id,to_account_id,to_amount,fee,fee_account_id,notes,created_at,updated_at) VALUES (?,?,?,?,?,10,?,?,?,?,?,'2026-10-24T16:00:00Z','2026-10-24T16:00:00Z')", parameters: [.integer(id),.integer(type),.integer(source),.text(amount),.text(date),destination.map(SQLValue.integer) ?? .null,received.map(SQLValue.text) ?? .null,.text(fee),feeAccount.map(SQLValue.integer) ?? .null,.text("Synthetic notes")])
    }
}

@Suite("All transactions history")
struct AllHistoryTests {
    @Test
    func globalPagesAndCompleteSummary() throws {
        let f = try AllHistoryFixture(); defer { f.remove() }
        let db = try SQLiteConnection(url: f.url)
        try db.transaction {
            for id in 1...121 { try f.insert(db, id: Int64(id)) }
            try f.insert(db, id: 122, type: 2, amount: "5.00", date: "2026-09-30T23:59:59")
            try f.insert(db, id: 123, type: 3, amount: "10.00", destination: 2, received: "13.00", fee: "2.00", charged: 1)
            try f.insert(db, id: 124, type: 2, source: 3, amount: "7.00", date: "2026-10-01T00:00:00")
            try f.insert(db, id: 125, amount: "100.00", date: "2026-11-01T00:00:00")
        }
        try db.close()
        let life = try f.lifecycle(); defer { try? life.close() }
        let current = try life.open()
        let result = try life.allHistory(expectedGeneration: current.generation, month: f.month)
        #expect(result.summary == (try life.home(expectedGeneration: current.generation, month: f.month)))
        #expect(result.summary.income == 7 && result.summary.expenses == 123)
        #expect(!result.summary.groups.flatMap(\.accounts).contains { $0.id == 3 })
        #expect(result.page.rows.count == 50 && result.page.rows.first?.id == 125)
        var rows = result.page.rows; var cursor = result.page.next
        while let next = cursor {
            let page = try life.allHistoryPage(expectedGeneration: current.generation, cursor: next)
            #expect(page.rows.count <= 50)
            rows += page.rows; cursor = page.next
        }
        #expect(rows.count == 125 && Set(rows.map(\.id)).count == 125)
        #expect(rows.filter { $0.transaction.type == .transfer }.count == 1)
        #expect(rows.first { $0.id == 124 }?.source.name == "Synthetic closed")
        #expect(rows.last?.id == 122)
        let sameTime = rows.filter { $0.transaction.date.storage == "2026-10-17T12:00:00" }.map(\.id)
        #expect(sameTime == sameTime.sorted(by: >))
        let replacement = try life.reset(expectedGeneration: current.generation)
        #expect(throws: DatabaseError.staleDataset) {
            try life.allHistoryPage(expectedGeneration: replacement.generation, cursor: result.page.next!)
        }
    }

    @Test
    func transferAmountsAndFeeOwnership() throws {
        let f = try AllHistoryFixture(); defer { f.remove() }
        let db = try SQLiteConnection(url: f.url)
        try db.run("INSERT INTO accounts(id,name,currency_id,initial_balance,status,account_type,created_at,updated_at) VALUES (4,'Synthetic same currency',1,'0.00',1,3,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')")
        try f.insert(db, id: 1, type: 3, amount: "10.00", destination: 4, received: "10.00")
        try f.insert(db, id: 2, type: 3, amount: "10.00", destination: 4, received: "9.00", fee: "1.00", charged: 4)
        try f.insert(db, id: 3, type: 3, amount: "10.00", destination: 2, received: "10.00", fee: "2.00", charged: 1)
        try f.insert(db, id: 4, type: 3, amount: "0.00", destination: 4, received: "0.00")
        try f.insert(db, id: 5, type: 3, amount: "0.00", destination: 2, received: "0.00")
        try db.close()
        let life = try f.lifecycle(); defer { try? life.close() }; let current = try life.open()
        let result = try life.allHistory(expectedGeneration: current.generation, month: f.month)
        let indexed = Dictionary(uniqueKeysWithValues: result.page.rows.map { ($0.id, $0) })
        #expect(result.page.rows.count == 5)
        #expect(indexed[1]?.transaction.amount == 10 && indexed[1]?.transaction.counterpartAmount == 10)
        #expect(indexed[2]?.transaction.amount == 10 && indexed[2]?.transaction.counterpartAmount == 9)
        #expect(indexed[3]?.transaction.amount == 10 && indexed[3]?.transaction.counterpartAmount == 10)
        #expect(indexed[4]?.transaction.amount == 0 && indexed[4]?.transaction.counterpartAmount == 0)
        #expect(indexed[5]?.transaction.amount == 0 && indexed[5]?.transaction.counterpartAmount == 0)
        #expect(indexed[2]?.transaction.feeAccountName == "Synthetic same currency")
        #expect(indexed[3]?.transaction.feeCurrency?.code == "USD")
        #expect(indexed[3]?.destination?.currency.code == "CAD")
        #expect(result.summary.income == 0 && result.summary.expenses == 3)
    }

    @Test
    func indexedBoundedReadAndMissingRates() throws {
        let f = try AllHistoryFixture(); defer { f.remove() }
        let db = try SQLiteConnection(url: f.url)
        try db.transaction { for id in 1...5000 { try f.insert(db, id: Int64(id), date: "2026-09-17T12:00:00") } }
        let plan = try db.rows("EXPLAIN QUERY PLAN " + AllHistoryRead.pageQuery(cursor: true), parameters: [.text("2026-10-17T12:00:00"), .integer(9999)]).map { try $0.text("detail") }.joined(separator: "\n")
        #expect(plan.contains("transactions_all_history_idx"))
        #expect(!plan.contains("SCAN transactions"))
        try db.run("DELETE FROM exchange_rates"); try db.close()
        let life = try f.lifecycle(); defer { try? life.close() }; let current = try life.open()
        let result = try life.allHistory(expectedGeneration: current.generation, month: f.month)
        #expect(result.page.rows.count == 50 && result.page.rows.first?.id == 5000)
        #expect(result.summary.totalBalance == nil && result.summary.income == 0 && result.summary.expenses == 0)
        #expect(result.page.rows.first?.transaction.amount == 1)
    }

    @Test
    @MainActor
    func stateRefreshRetryCurrencyAndReplacement() async throws {
        let f = try AllHistoryFixture(); defer { f.remove() }
        let db = try SQLiteConnection(url: f.url)
        try db.transaction { for id in 1...65 { try f.insert(db, id: Int64(id)) } }; try db.close()
        let dependencies = AppDependencies(directory: f.root); await dependencies.start()
        let state = AllHistoryState()
        await state.load(database: dependencies.database, session: dependencies.session, month: f.month)
        #expect(state.rows.count == 50 && state.days.count == 1)
        try await dependencies.database.close()
        await state.loadMore(database: dependencies.database, session: dependencies.session)
        #expect(state.pageError != nil && state.rows.count == 50 && state.next != nil)
        _ = try await dependencies.database.open()
        await state.loadMore(database: dependencies.database, session: dependencies.session)
        #expect(state.rows.count == 65 && state.days.count == 1 && state.next == nil)
        let retainedRows = state.rows
        let retainedContent = state.content
        try await dependencies.database.close()
        await state.ensureLoaded(database: dependencies.database, session: dependencies.session, month: f.month)
        #expect(state.rows == retainedRows && state.content == retainedContent && state.next == nil && state.error == nil)
        _ = try await dependencies.database.open()
        await state.load(database: dependencies.database, session: dependencies.session, month: f.month)
        #expect(state.rows.count == 50 && state.next != nil)
        let settings = SettingsState(dependencies: dependencies)
        #expect(await settings.setDisplayCurrency(34))
        await state.ensureLoaded(database: dependencies.database, session: dependencies.session, month: f.month)
        #expect(state.content?.summary.currency.code == "CAD" && state.rows.count == 50)
        let cancelled = Task { @MainActor in await state.load(database: dependencies.database, session: dependencies.session, month: f.month) }
        cancelled.cancel(); await cancelled.value
        #expect(state.rows.count == 50 && !state.isLoading)
        let generation = dependencies.session.snapshot!.generation
        async let oldRead = try? dependencies.database.allHistory(expectedGeneration: generation, month: f.month)
        let replacement = try await dependencies.database.reset(expectedGeneration: generation)
        let oldResult = await oldRead
        #expect(oldResult == nil || oldResult?.summary.generation == generation)
        dependencies.session.publish(replacement, settings: dependencies.settings)
        await state.ensureLoaded(database: dependencies.database, session: dependencies.session, month: f.month)
        #expect(state.content?.summary.accountCount == 0 && state.rows.isEmpty && state.next == nil)
        try await dependencies.database.close()
        await state.load(database: dependencies.database, session: dependencies.session, month: f.month)
        #expect(state.content == nil && state.error != nil)
        _ = try await dependencies.database.open()
        await state.load(database: dependencies.database, session: dependencies.session, month: f.month)
        #expect(state.content != nil && state.error == nil && state.rows.isEmpty)
        let unavailable = AppSession()
        await state.ensureLoaded(database: dependencies.database, session: unavailable, month: f.month)
        #expect(state.content == nil && state.rows.isEmpty && state.next == nil)
        try await dependencies.database.close()
    }
    @Test
    @MainActor
    func renderSyntheticLayoutProof() throws {
        let usd = CurrencyInfo(id: 1, code: "USD", name: "US Dollar", decimalPlaces: 2)
        let cad = CurrencyInfo(id: 34, code: "CAD", name: "Canadian Dollar", decimalPlaces: 2)
        let date = try LocalDateTime(storage: "2026-10-17T12:34:56")
        let transaction = HistoryRow(id: 1, type: .transfer, date: date,
            category: "Very long synthetic transfer category for layout verification", symbol: nil,
            notes: "A long synthetic note that must remain inside the middle column without wrapping",
            incoming: false, amount: Decimal(string: "123456789.12")!, currency: usd,
            counterparty: "Synthetic receiving account with a long name",
            counterpartAmount: Decimal(string: "168135801.09")!, counterpartCurrency: cad,
            fee: Decimal(string: "120.50")!, feeCurrency: usd, feeAccountName: "Synthetic source account")
        let row = AllHistoryRow(transaction: transaction,
            source: HistoryAccountContext(id: 1, name: "Synthetic source account with a very long name", currency: usd),
            destination: HistoryAccountContext(id: 2, name: "Synthetic receiving account with a long name", currency: cad))
        let ordinary = HistoryRow(id: 2, type: .income, date: date,
            category: "Very long synthetic reimbursement category", symbol: "banknote",
            notes: transaction.notes, incoming: true, amount: transaction.amount, currency: usd,
            counterparty: nil, counterpartAmount: nil, counterpartCurrency: nil,
            fee: 0, feeCurrency: nil, feeAccountName: nil)
        let summary = HomeSnapshot(generation: UUID(), month: try CalendarMonth(year: 2026, month: 10),
            currency: usd, totalBalance: 987654, income: Decimal(string: "123456.78")!,
            expenses: Decimal(string: "100000.12")!, difference: Decimal(string: "23456.66")!,
            groups: [], accountCount: 0)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AllHistoryVisualProof", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func render<V: View>(_ view: V, name: String, size: DynamicTypeSize = .large) throws {
            let renderer = ImageRenderer(content: view.environment(\.dynamicTypeSize, size)
                .frame(width: 370).background(Color(.systemGroupedBackground)))
            renderer.scale = 2
            let data = try #require(renderer.uiImage?.pngData())
            try data.write(to: folder.appendingPathComponent(name + ".png"))
        }
        try render(VStack(spacing: 12) {
            HomeSummaryView(content: summary)
            TransactionRowView(row: ordinary, accountName: row.source.name)
            AllTransferRowView(row: row)
        }, name: "normal-long-values")
        try render(AllTransferRowView(row: row), name: "accessibility-transfer", size: .accessibility5)
        try render(TransactionRowView(row: ordinary, accountName: row.source.name), name: "accessibility-ordinary", size: .accessibility5)
        try render(VStack {
            HomeSummaryView(content: HomeSnapshot(generation: summary.generation, month: summary.month,
                currency: usd, totalBalance: 0, income: 0, expenses: 0, difference: 0, groups: [], accountCount: 0))
            ContentUnavailableView("No transactions", systemImage: "list.bullet",
                description: Text("Your database has no recorded transactions."))
        }, name: "empty-state")
        try render(HomeSummaryView(content: HomeSnapshot(generation: summary.generation, month: summary.month,
            currency: usd, totalBalance: nil, income: 0, expenses: nil, difference: nil, groups: [], accountCount: 1)),
            name: "missing-rate")
    }

}
