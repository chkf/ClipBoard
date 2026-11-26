import Foundation
import SQLite3

enum HistoryError: LocalizedError {
    case sharedContainer, database(Int32), unreadable, missing

    var errorDescription: String? {
        switch self {
        case .sharedContainer: return "无法打开共享历史。请在重签时保留键盘扩展，并让主 App 和键盘的描述文件授权同一个 App Group。"
        case .database: return "暂时无法访问历史记录，请在设备解锁后重试。"
        case .unreadable: return "未能读取剪贴板。请在系统询问时允许粘贴，或在系统设置中检查粘贴权限。"
        case .missing: return "这条记录已被移除。"
        }
    }
}

enum SQLValue {
    case text(String), blob(Data), integer(Int), real(Double), null
}

struct SQLRow {
    let statement: OpaquePointer
    func integer(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
    func real(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }
    func data(_ column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
    func text(_ column: Int32) -> String { String(decoding: data(column), as: UTF8.self) }
}

final class Database {
    private let handle: OpaquePointer
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, readOnly: Bool) throws {
        var connection: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let code = sqlite3_open_v2(url.path, &connection, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            throw HistoryError.database(code)
        }
        handle = connection
        sqlite3_busy_timeout(connection, 3_000)
        try execute("PRAGMA foreign_keys = ON")
        if !readOnly {
            try execute("PRAGMA secure_delete = ON")
            // Set before creating the schema so deleting originals also returns their pages to iOS.
            try execute("PRAGMA auto_vacuum = FULL")
        }
    }

    deinit { sqlite3_close(handle) }

    func query<T>(_ sql: String, _ values: [SQLValue] = [], map: (SQLRow) -> T) throws -> [T] {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw HistoryError.database(code) }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let parameter = Int32(index + 1)
            let result: Int32
            switch value {
            case .text(let string):
                result = sqlite3_bind_text(statement, parameter, string, Int32(string.utf8.count), transient)
            case .blob(let data):
                result = data.withUnsafeBytes { bytes in
                    if bytes.isEmpty { return sqlite3_bind_zeroblob(statement, parameter, 0) }
                    return sqlite3_bind_blob64(statement, parameter, bytes.baseAddress, UInt64(bytes.count), transient)
                }
            case .integer(let number): result = sqlite3_bind_int64(statement, parameter, Int64(number))
            case .real(let number): result = sqlite3_bind_double(statement, parameter, number)
            case .null: result = sqlite3_bind_null(statement, parameter)
            }
            guard result == SQLITE_OK else { throw HistoryError.database(result) }
        }
        var rows: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: rows.append(map(SQLRow(statement: statement)))
            case SQLITE_DONE: return rows
            default: throw HistoryError.database(sqlite3_errcode(handle))
            }
        }
    }

    @discardableResult
    func execute(_ sql: String, _ values: [SQLValue] = []) throws -> Int {
        _ = try query(sql, values) { _ in () }
        return Int(sqlite3_changes(handle))
    }

    func transaction<T>(_ work: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try work()
            try execute("COMMIT")
            return value
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }
}
