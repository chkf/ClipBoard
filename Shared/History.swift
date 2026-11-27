import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

struct ClipRow: Identifiable, Equatable {
    let id: String
    let preview: String
    let isImage: Bool
    let updated: Double
    var pinnedAt: Double = 0
    var isPinned: Bool { pinnedAt > 0 }
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
}

struct HistoryState {
    let settings: HistorySettings
    let revision: Int
    let event: PasteEvent?
}

actor HistoryStore {
    let db: Database
    private let supportsPins: Bool
    let supportsCategories: Bool
    let writable: Bool

    static func shared(readOnly: Bool = false) async throws -> HistoryStore {
        do {
            let root = try HistoryContainer.url()
            return try HistoryStore(directory: root.appendingPathComponent("History", isDirectory: true), readOnly: readOnly)
        } catch HistoryError.sharedContainer {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: !readOnly)
            return try HistoryStore(directory: root.appendingPathComponent("ClipboardHistory", isDirectory: true),
                                    readOnly: readOnly)
        }
    }

    init(directory: URL, readOnly: Bool = false) throws {
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
        writable = !readOnly
        if readOnly {
            supportsPins = try !db.query("SELECT 1 FROM sqlite_master WHERE type='table' AND name='pins'") { $0.integer(0) }.isEmpty
            supportsCategories = try !db.query("SELECT 1 FROM sqlite_master WHERE type='table' AND name='categories'") { $0.integer(0) }.isEmpty
            return
        }
        supportsPins = true
        supportsCategories = true
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        let database = db
        try database.transaction {
            try database.execute("""
                CREATE TABLE IF NOT EXISTS clips (
                    id TEXT PRIMARY KEY, content_key TEXT NOT NULL UNIQUE, preview TEXT NOT NULL,
                    is_image INTEGER NOT NULL, created REAL NOT NULL, updated REAL NOT NULL)
                """)
            try database.execute("CREATE INDEX IF NOT EXISTS recency ON clips(updated DESC, id DESC)")
            try database.execute("CREATE TABLE IF NOT EXISTS pins (id TEXT PRIMARY KEY REFERENCES clips(id) ON DELETE CASCADE, pinned REAL NOT NULL)")
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
            let firstCategories = try database.query("SELECT 1 FROM sqlite_master WHERE type='table' AND name='categories'") { $0.integer(0) }.isEmpty
            try database.execute("CREATE TABLE IF NOT EXISTS categories(id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE)")
            if firstCategories { try database.execute("INSERT INTO categories(id,name) VALUES('work','工作'),('frequent','常用')") }
            try database.execute("CREATE TABLE IF NOT EXISTS filing(id TEXT PRIMARY KEY REFERENCES clips(id) ON DELETE CASCADE, category TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE)")
            try database.execute("CREATE INDEX IF NOT EXISTS filing_category ON filing(category,id)")
        }
        try database.execute("""
            CREATE TEMP TABLE undo_rows(step INTEGER, kind TEXT NOT NULL, id TEXT NOT NULL, category TEXT, pinned REAL,
                content_key TEXT, preview TEXT, is_image INTEGER, created REAL, updated REAL, uti TEXT, body BLOB, thumb BLOB,
                PRIMARY KEY(step,id)) WITHOUT ROWID
            """)
    }

    func state() throws -> HistoryState {
        let result = try db.query("SELECT days,auto_switch,revision,boot,counter,last_key FROM state WHERE id=1") { row in
            let settings = HistorySettings(retention: row.integer(0), autoSwitch: row.integer(1) != 0)
            let stamp = PasteStamp(boot: row.real(3), count: row.integer(4))
            let event = row.isNull(4) ? nil : PasteEvent(stamp: stamp, key: row.isNull(5) ? nil : row.text(5))
            return HistoryState(settings: settings, revision: row.integer(2), event: event)
        }
        guard let state = result.first else { throw HistoryError.database(11) }
        return state
    }

    func page(after cursor: ClipRow? = nil, limit: Int = 60, matching query: String = "", category: String? = nil) throws -> [ClipRow] {
        let rank = supportsPins ? "COALESCE(p.pinned,0)" : "0.0"
        var sql = "SELECT c.id,c.preview,c.is_image,c.updated," + rank + " FROM clips c "
        if supportsPins { sql += "LEFT JOIN pins p ON p.id=c.id " }
        var conditions: [String] = []
        var values: [SQLValue] = []
        if let category {
            if supportsCategories {
                if category == ClipCategory.ordinary.id { conditions.append("NOT EXISTS(SELECT 1 FROM filing f WHERE f.id=c.id)") }
                else { conditions.append("c.id IN (SELECT id FROM filing WHERE category=?)"); values.append(.text(category)) }
            } else if category != ClipCategory.ordinary.id { return [] }
        }
        if !query.isEmpty {
            sql += "JOIN bodies b ON b.id=c.id "
            conditions.append("(CASE WHEN c.is_image=1 THEN instr('图片 image',lower(?))>0 ELSE instr(lower(CAST(b.body AS TEXT)),lower(?))>0 OR clipboard_pinyin(c.preview,?) END)")
            values += [.text(query), .text(query), .text(query)]
        }
        if let cursor {
            conditions.append("(" + rank + ",c.updated,c.id) < (?,?,?)")
            values += [.real(cursor.pinnedAt), .real(cursor.updated), .text(cursor.id)]
        }
        if !conditions.isEmpty { sql += "WHERE " + conditions.joined(separator: " AND ") + " " }
        sql += "ORDER BY 5 DESC,c.updated DESC,c.id DESC LIMIT ?"
        return try db.query(sql, values + [.integer(limit)]) {
            ClipRow(id: $0.text(0), preview: $0.text(1), isImage: $0.integer(2) != 0, updated: $0.real(3), pinnedAt: $0.real(4))
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

    private func save(_ clip: PreparedClip, timestamp: Double) throws {
        if try db.execute("UPDATE clips SET updated=MAX(updated,?) WHERE content_key=?", [.real(timestamp), .text(clip.key)]) == 0 {
            let id = UUID().uuidString
            try db.execute("INSERT INTO clips(id,content_key,preview,is_image,created,updated) VALUES(?,?,?,?,?,?)", [
                .text(id), .text(clip.key), .text(clip.preview), .integer(clip.thumbnail == nil ? 0 : 1),
                .real(timestamp), .real(timestamp)
            ])
            try db.execute("INSERT INTO bodies VALUES(?,?,?,?)", [
                .text(id), .text(clip.body.type), .blob(clip.body.data), clip.thumbnail.map(SQLValue.blob) ?? .null
            ])
        }
    }

    // The expected event is sampled before the asynchronous pasteboard read. A newer
    // observation in the other process wins; the active monitor will resample.
    func observe(_ clip: PreparedClip?, stamp: PasteStamp, replacing expected: PasteEvent?, now: Date = Date()) throws {
        try db.transaction {
            let previous = try state().event
            guard previous == expected else { return }
            if previous?.stamp == stamp, previous?.key == clip?.key { return }
            let uncertain = previous.map { !stamp.sameBoot(as: $0.stamp) || stamp.count < $0.stamp.count } ?? false
            if let clip, !uncertain || previous?.key != clip.key {
                try save(clip, timestamp: now.timeIntervalSince1970)
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

    func bumpRevision() throws {
        try db.execute("UPDATE state SET revision=revision+1 WHERE id=1")
    }

    func delete(_ id: String? = nil) throws {
        try db.transaction {
            if let id { try db.execute("DELETE FROM clips WHERE id=?", [.text(id)]) }
            else { try db.execute("DELETE FROM clips") }
            try bumpRevision()
        }
    }

    func pin(_ id: String, enabled: Bool, now: Date = Date()) throws {
        try db.transaction {
            if enabled {
                try db.execute("INSERT OR IGNORE INTO pins SELECT id,? FROM clips WHERE id=?", [.real(now.timeIntervalSince1970), .text(id)])
            } else {
                try db.execute("DELETE FROM pins WHERE id=?", [.text(id)])
            }
            try bumpRevision()
        }
    }

    func clearUnpinned() throws {
        try db.transaction {
            if try db.execute("DELETE FROM clips WHERE id NOT IN (SELECT id FROM pins) AND id NOT IN (SELECT id FROM filing)") > 0 { try bumpRevision() }
        }
    }

    private func expire(days: Int, now: Date) throws {
        let cutoff = now.timeIntervalSince1970 - Double(days) * 86_400
        if try db.execute("DELETE FROM clips WHERE updated<=? AND id NOT IN (SELECT id FROM pins) AND id NOT IN (SELECT id FROM filing)", [.real(cutoff)]) > 0 { try bumpRevision() }
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

}
