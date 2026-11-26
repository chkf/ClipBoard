import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

struct ClipRow: Identifiable, Equatable {
    let id: String
    let preview: String
    let isImage: Bool
    let updated: Double
}

struct ClipBody {
    let type: String
    let data: Data
    var text: String? {
        type == UTType.utf8PlainText.identifier ? String(data: data, encoding: .utf8) : nil
    }
}

struct PreparedClip {
    let key: String
    let preview: String
    let body: ClipBody
    let thumbnail: Data?

    static func text(_ text: String) -> Self {
        let data = Data(text.utf8)
        return Self(key: "t-" + SHA256.hash(data: data).hex,
                    preview: String(text.prefix(240)), body: ClipBody(type: UTType.utf8PlainText.identifier, data: data),
                    thumbnail: nil)
    }
}

extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

struct PasteStamp: Equatable {
    let boot: Double
    let count: Int

    static let systemBoot: Double = {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        var mib = [CTL_KERN, KERN_BOOTTIME]
        if sysctl(&mib, 2, &time, &size, nil, 0) == 0 { return Double(time.tv_sec) }
        return (Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime).rounded()
    }()

    func sameBoot(as other: Self) -> Bool { abs(boot - other.boot) <= 2 }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.count == rhs.count && lhs.sameBoot(as: rhs) }
}

struct PasteEvent: Equatable {
    let stamp: PasteStamp
    let key: String?
}

struct HistorySettings: Equatable {
    static let durations = [7, 15, 30, 90]
    var retention = 30
    var autoSwitch = false
    var keyboardConfigured = false
}

struct HistoryState {
    let settings: HistorySettings
    let revision: Int
    let event: PasteEvent?
}

actor HistoryStore {
    private let db: Database
    let readOnly: Bool

    static func shared(readOnly: Bool = false) async throws -> HistoryStore {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "ClipboardAppGroup") as? String,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { throw HistoryError.sharedContainer }
        return try HistoryStore(directory: root.appendingPathComponent("History", isDirectory: true), readOnly: readOnly)
    }

    init(directory: URL, readOnly: Bool = false) throws {
        self.readOnly = readOnly
        if !readOnly {
            var folder = directory
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
        }
        let url = directory.appendingPathComponent("History.sqlite3")
        db = try Database(url: url, readOnly: readOnly)
        guard !readOnly else { return }
        let database = db
        try database.transaction {
            try database.execute("""
                CREATE TABLE IF NOT EXISTS clips (
                    id TEXT PRIMARY KEY, content_key TEXT NOT NULL UNIQUE, preview TEXT NOT NULL,
                    is_image INTEGER NOT NULL, created REAL NOT NULL, updated REAL NOT NULL)
                """)
            try database.execute("CREATE INDEX IF NOT EXISTS recency ON clips(updated DESC, id DESC)")
            try database.execute("""
                CREATE TABLE IF NOT EXISTS bodies (
                    id TEXT PRIMARY KEY REFERENCES clips(id) ON DELETE CASCADE, uti TEXT NOT NULL,
                    body BLOB NOT NULL, thumb BLOB)
                """)
            try database.execute("""
                CREATE TABLE IF NOT EXISTS state (
                    id INTEGER PRIMARY KEY CHECK(id=1), days INTEGER NOT NULL DEFAULT 30,
                    auto_switch INTEGER NOT NULL DEFAULT 0, configured INTEGER NOT NULL DEFAULT 0,
                    revision INTEGER NOT NULL DEFAULT 0, boot REAL, counter INTEGER, last_key TEXT)
                """)
            try database.execute("INSERT OR IGNORE INTO state(id) VALUES(1)")
        }
    }

    func state() throws -> HistoryState {
        let result = try db.query("SELECT days,auto_switch,configured,revision,boot,counter,last_key FROM state WHERE id=1") { row in
            let settings = HistorySettings(retention: row.integer(0), autoSwitch: row.integer(1) != 0,
                                           keyboardConfigured: row.integer(2) != 0)
            let stamp = PasteStamp(boot: row.real(4), count: row.integer(5))
            let event = row.isNull(5) ? nil : PasteEvent(stamp: stamp, key: row.isNull(6) ? nil : row.text(6))
            return HistoryState(settings: settings, revision: row.integer(3), event: event)
        }
        guard let state = result.first else { throw HistoryError.database(11) }
        return state
    }

    func page(after cursor: ClipRow? = nil, limit: Int = 60) throws -> [ClipRow] {
        var sql = "SELECT id,preview,is_image,updated FROM clips "
        var values: [SQLValue] = []
        if let cursor {
            sql += "WHERE (updated,id) < (?,?) "
            values = [.real(cursor.updated), .text(cursor.id)]
        }
        sql += "ORDER BY updated DESC,id DESC LIMIT ?"
        return try db.query(sql, values + [.integer(limit)]) {
            ClipRow(id: $0.text(0), preview: $0.text(1), isImage: $0.integer(2) != 0, updated: $0.real(3))
        }
    }

    func body(_ id: String) throws -> ClipBody {
        guard let item = try db.query("SELECT uti,body FROM bodies WHERE id=?", [.text(id)], map: {
            ClipBody(type: $0.text(0), data: $0.data(1))
        }).first else { throw HistoryError.missing }
        return item
    }

    func thumbnail(_ id: String) throws -> Data? {
        try db.query("SELECT thumb FROM bodies WHERE id=? AND thumb IS NOT NULL", [.text(id)]) { $0.data(0) }.first
    }

    // The expected event is sampled before the asynchronous pasteboard read. A newer
    // observation in the other process wins; the active monitor will resample.
    func observe(_ clip: PreparedClip?, stamp: PasteStamp, replacing expected: PasteEvent?, now: Date = Date()) throws {
        try db.transaction {
            let previous = try state().event
            guard previous == expected, previous?.stamp != stamp else { return }
            let uncertain = previous.map { !stamp.sameBoot(as: $0.stamp) || stamp.count < $0.stamp.count } ?? false
            if let clip, !uncertain || previous?.key != clip.key {
                let timestamp = now.timeIntervalSince1970
                let id = UUID().uuidString
                if try db.execute("UPDATE clips SET updated=? WHERE content_key=?", [.real(timestamp), .text(clip.key)]) == 0 {
                    try db.execute("INSERT INTO clips VALUES(?,?,?,?,?,?)", [
                        .text(id), .text(clip.key), .text(clip.preview), .integer(clip.thumbnail == nil ? 0 : 1),
                        .real(timestamp), .real(timestamp)
                    ])
                    try db.execute("INSERT INTO bodies VALUES(?,?,?,?)", [
                        .text(id), .text(clip.body.type), .blob(clip.body.data), clip.thumbnail.map(SQLValue.blob) ?? .null
                    ])
                }
                try bumpRevision()
            }
            try remember(stamp, key: clip?.key)
        }
    }

    // Holding the same writer lock as capture and deletion prevents a delayed self-write
    // callback from promoting twice or bringing back an item deleted by the other process.
    func copy(_ id: String, now: Date = Date(), write: @Sendable (ClipBody) throws -> PasteStamp) throws {
        try db.transaction {
            let body = try body(id)
            guard let key = try db.query("SELECT content_key FROM clips WHERE id=?", [.text(id)], map: { $0.text(0) }).first
            else { throw HistoryError.missing }
            let stamp = try write(body)
            try db.execute("UPDATE clips SET updated=? WHERE id=?", [.real(now.timeIntervalSince1970), .text(id)])
            try remember(stamp, key: key)
            try bumpRevision()
        }
    }

    private func remember(_ stamp: PasteStamp, key: String?) throws {
        try db.execute("UPDATE state SET boot=?,counter=?,last_key=? WHERE id=1",
                       [.real(stamp.boot), .integer(stamp.count), key.map(SQLValue.text) ?? .null])
    }

    private func bumpRevision() throws {
        try db.execute("UPDATE state SET revision=revision+1 WHERE id=1")
    }

    func delete(_ id: String? = nil) throws {
        try db.transaction {
            if let id { try db.execute("DELETE FROM clips WHERE id=?", [.text(id)]) }
            else { try db.execute("DELETE FROM clips") }
            try bumpRevision()
        }
    }

    private func expire(days: Int, now: Date) throws {
        let cutoff = now.timeIntervalSince1970 - Double(days) * 86_400
        if try db.execute("DELETE FROM clips WHERE updated<=?", [.real(cutoff)]) > 0 { try bumpRevision() }
    }

    func prune(now: Date = Date()) throws {
        try db.transaction { try expire(days: state().settings.retention, now: now) }
    }

    func retention(_ days: Int, now: Date = Date()) throws {
        guard HistorySettings.durations.contains(days) else { return }
        try db.transaction {
            try db.execute("UPDATE state SET days=?,revision=revision+1 WHERE id=1", [.integer(days)])
            try expire(days: days, now: now)
        }
    }

    func autoSwitch(_ on: Bool) throws {
        try db.execute("UPDATE state SET auto_switch=?,revision=revision+1 WHERE id=1", [.integer(on ? 1 : 0)])
    }

    func keyboardConfigured() throws {
        try db.execute("UPDATE state SET configured=1,revision=revision+1 WHERE id=1 AND configured=0")
    }
}
