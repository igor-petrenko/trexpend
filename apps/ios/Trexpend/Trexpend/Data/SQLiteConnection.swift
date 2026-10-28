import Foundation
import SQLite3

nonisolated enum DatabaseError: Error, Equatable, LocalizedError {
    case sqlite
    case invalidDatabase
    case unsupportedVersion
    case invalidData
    case fileAccess
    case recoveryRequired
    case staleDataset
    case missingResource
    case cancelled
    case validationTimedOut

    var errorDescription: String? {
        switch self {
        case .sqlite: "The database operation could not be completed."
        case .invalidDatabase: "Select a valid standalone Trexpend database."
        case .unsupportedVersion: "This database version is not supported."
        case .invalidData: "The database contains unsupported or invalid data."
        case .fileAccess: "The database file could not be accessed."
        case .recoveryRequired: "Database recovery could not finish. Your files have been preserved."
        case .staleDataset: "The active database changed. Please try again."
        case .missingResource: "The application's database resources are unavailable."
        case .cancelled: "The operation was cancelled."
        case .validationTimedOut: "Database verification took too long. Please try again."
        }
    }
}

nonisolated enum SQLValue: Equatable, Sendable {
    case integer(Int64)
    case text(String)
    case null
}

nonisolated struct SQLRow: Sendable {
    let values: [String: SQLValue]
    func integer(_ column: String) throws -> Int64 {
        guard case .integer(let value) = values[column] else { throw DatabaseError.invalidData }
        return value
    }
    func text(_ column: String) throws -> String {
        guard case .text(let value) = values[column] else { throw DatabaseError.invalidData }
        return value
    }
    func optionalText(_ column: String) throws -> String? {
        if values[column] == .null { return nil }
        return try text(column)
    }
    func optionalInteger(_ column: String) throws -> Int64? {
        if values[column] == .null { return nil }
        return try integer(column)
    }
}

// Instances and statements never leave DatabaseStore's serial worker operation.
nonisolated final class SQLiteConnection {
    private var handle: OpaquePointer?
    private var validationDeadline: TimeInterval?

    private final class Budget {
        let deadline: TimeInterval
        init(deadline: TimeInterval) { self.deadline = deadline }
    }

    func withValidationBudget<T>(seconds: TimeInterval = 30, _ body: () throws -> T) throws -> T {
        let budget = Budget(deadline: ProcessInfo.processInfo.systemUptime + seconds)
        validationDeadline = budget.deadline
        sqlite3_progress_handler(handle, 10_000, { context in
            guard let context else { return 1 }
            let budget = Unmanaged<Budget>.fromOpaque(context).takeUnretainedValue()
            return ProcessInfo.processInfo.systemUptime > budget.deadline ? 1 : 0
        }, Unmanaged.passUnretained(budget).toOpaque())
        defer {
            sqlite3_progress_handler(handle, 0, nil, nil)
            validationDeadline = nil
            withExtendedLifetime(budget) {}
        }
        return try body()
    }

    func checkBudget() throws {
        if let validationDeadline, ProcessInfo.processInfo.systemUptime > validationDeadline { throw DatabaseError.validationTimedOut }
    }

    init(url: URL?, readOnly: Bool = false, create: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0)
        guard sqlite3_open_v2(url?.path ?? ":memory:", &handle, flags | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close_v2(handle)
            handle = nil
            throw DatabaseError.sqlite
        }
        do {
            sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 16 * 1024 * 1024)
            sqlite3_limit(handle, SQLITE_LIMIT_SQL_LENGTH, 1024 * 1024)
            sqlite3_limit(handle, SQLITE_LIMIT_ATTACHED, 0)
            guard sqlite3_busy_timeout(handle, 3000) == SQLITE_OK else { throw DatabaseError.sqlite }
            try execute("PRAGMA trusted_schema = OFF; PRAGMA foreign_keys = ON;")
        } catch {
            sqlite3_close_v2(handle)
            handle = nil
            throw error
        }
    }

    deinit { sqlite3_close_v2(handle) }

    func close() throws {
        guard let handle else { return }
        guard sqlite3_close(handle) == SQLITE_OK else { throw DatabaseError.sqlite }
        self.handle = nil
    }

    func configureWorking() throws {
        try execute("PRAGMA journal_mode = DELETE; PRAGMA synchronous = FULL;")
        guard try rows("PRAGMA journal_mode").first?.text("journal_mode") == "delete",
              try rows("PRAGMA synchronous").first?.integer("synchronous") == 2,
              try rows("PRAGMA foreign_keys").first?.integer("foreign_keys") == 1 else { throw DatabaseError.sqlite }
    }

    // Only bundled, reviewed SQL and fixed internal statements may use execute.
    func execute(_ sql: String) throws {
        guard let handle, sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw DatabaseError.sqlite }
    }

    func run(_ sql: String, parameters: [SQLValue] = []) throws {
        try statement(sql, parameters: parameters) { statement in
            guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.sqlite }
        }
    }

    func rows(_ sql: String, parameters: [SQLValue] = []) throws -> [SQLRow] {
        var result: [SQLRow] = []
        try forEach(sql, parameters: parameters) { result.append($0) }
        return result
    }

    func forEach(_ sql: String, parameters: [SQLValue] = [], body: (SQLRow) throws -> Void) throws {
        try statement(sql, parameters: parameters) { statement in
            while true {
                try checkBudget()
                let step = sqlite3_step(statement)
                try checkBudget()
                if step == SQLITE_DONE { return }
                guard step == SQLITE_ROW else { throw DatabaseError.sqlite }
                var fields: [String: SQLValue] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    let name = String(cString: sqlite3_column_name(statement, index))
                    switch sqlite3_column_type(statement, index) {
                    case SQLITE_INTEGER: fields[name] = .integer(sqlite3_column_int64(statement, index))
                    case SQLITE_NULL: fields[name] = .null
                    case SQLITE_TEXT:
                        let count = Int(sqlite3_column_bytes(statement, index))
                        guard let bytes = sqlite3_column_text(statement, index),
                              let text = String(bytes: UnsafeBufferPointer(start: bytes, count: count), encoding: .utf8) else { throw DatabaseError.invalidData }
                        fields[name] = .text(text)
                    default: throw DatabaseError.invalidData
                    }
                }
                try body(SQLRow(values: fields))
            }
        }
    }

    func transaction<T>(readOnly: Bool = false, _ body: () throws -> T) throws -> T {
        try execute(readOnly ? "BEGIN DEFERRED" : "BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            // Report rollback failure as recovery-required instead of pretending
            // the connection is still a usable transaction boundary.
            do { try execute("ROLLBACK") } catch { throw DatabaseError.recoveryRequired }
            throw error
        }
    }

    func backup(to destination: SQLiteConnection) throws {
        guard let handle, let target = destination.handle,
              let backup = sqlite3_backup_init(target, "main", handle, "main") else { throw DatabaseError.sqlite }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var result = sqlite3_backup_step(backup, -1)
        while (result == SQLITE_BUSY || result == SQLITE_LOCKED) && ProcessInfo.processInfo.systemUptime < deadline {
            sqlite3_sleep(20)
            result = sqlite3_backup_step(backup, -1)
        }
        let finish = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finish == SQLITE_OK else { throw DatabaseError.sqlite }
    }

    private func statement<T>(_ sql: String, parameters: [SQLValue], body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard let handle else { throw DatabaseError.sqlite }
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        guard status == SQLITE_OK, let statement else { throw DatabaseError.sqlite }
        guard sqlite3_bind_parameter_count(statement) == parameters.count else { throw DatabaseError.sqlite }
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null: result = sqlite3_bind_null(statement, index)
            case .integer(let integer): result = sqlite3_bind_int64(statement, index, integer)
            case .text(let text):
                result = text.utf8CString.withUnsafeBufferPointer { bytes in
                    sqlite3_bind_text(statement, index, bytes.baseAddress, Int32(bytes.count - 1), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            }
            guard result == SQLITE_OK else { throw DatabaseError.sqlite }
        }
        return try body(statement)
    }
}
