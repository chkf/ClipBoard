import XCTest

final class KeyboardUpgradeTests: XCTestCase {
    func testReopeningTrialHistoryKeepsPinnedKeyboardEntries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = "已存入键盘的记录"
        let id: String
        do {
            let store = try HistoryStore(directory: directory)
            try await store.observe(.text(text), stamp: PasteStamp(boot: 1, count: 1), replacing: nil)
            let rows = try await store.page()
            id = try XCTUnwrap(rows.first).id
            try await store.pin(id, enabled: true)
            let old = try Database(url: directory.appendingPathComponent("History.sqlite3"), readOnly: false)
            try old.execute("CREATE TABLE capture_receipts (id TEXT PRIMARY KEY, received REAL NOT NULL)")
            try old.execute("INSERT INTO capture_receipts VALUES(?,?)", [.text(UUID().uuidString), .real(1)])
        }
        let updated = try HistoryStore(directory: directory)
        let rows = try await updated.page()
        XCTAssertEqual(rows.map(\.id), [id])
        XCTAssertTrue(try XCTUnwrap(rows.first).isPinned)
        let body = try await updated.body(id)
        XCTAssertEqual(body.text, text)
    }

    func testOpeningVersion104KeyboardDatabasePreservesHistorySettingsAndLastCopy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = "原有键盘历史"
        let clip = PreparedClip.text(text)
        let stamp = PasteStamp(boot: 100, count: 8)
        let date = Date().timeIntervalSince1970
        do {
            let old = try Database(url: directory.appendingPathComponent("History.sqlite3"), readOnly: false)
            try old.execute("CREATE TABLE clips(id TEXT PRIMARY KEY, content_key TEXT UNIQUE, preview TEXT, is_image INTEGER, created REAL, updated REAL)")
            try old.execute("CREATE TABLE bodies(id TEXT PRIMARY KEY REFERENCES clips(id) ON DELETE CASCADE, uti TEXT, body BLOB, thumb BLOB)")
            try old.execute("CREATE TABLE state(id INTEGER PRIMARY KEY,days INTEGER,auto_switch INTEGER,configured INTEGER,revision INTEGER,boot REAL,counter INTEGER,last_key TEXT)")
            try old.execute("CREATE TABLE replica(id INTEGER PRIMARY KEY,identity TEXT,cleared REAL,peer TEXT,seen INTEGER)")
            try old.execute("CREATE TABLE copy_events(content_key TEXT PRIMARY KEY,boot REAL,counter INTEGER,copied REAL)")
            try old.execute("CREATE TABLE removed(content_key TEXT PRIMARY KEY,deleted REAL)")
            try old.execute("INSERT INTO clips VALUES('original',?,?,0,?,?)", [.text(clip.key), .text(text), .real(date), .real(date)])
            try old.execute("INSERT INTO bodies VALUES('original',?,?,NULL)", [.text(clip.body.type), .blob(clip.body.data)])
            try old.execute("INSERT INTO state VALUES(1,15,1,1,9,100,8,?)", [.text(clip.key)])
        }
        let store = try HistoryStore(directory: directory)
        let state = try await store.state()
        XCTAssertEqual(state.settings.retention, 15)
        XCTAssertTrue(state.settings.autoSwitch)
        XCTAssertEqual(state.event, PasteEvent(stamp: stamp, key: clip.key))
        let body = try await store.body("original")
        XCTAssertEqual(body.text, text)
        try await store.delete("original")
        try await store.observe(clip, stamp: stamp, replacing: state.event)
        let rows = try await store.page()
        XCTAssertTrue(rows.isEmpty)
    }
}
