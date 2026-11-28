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

    func testOpeningVersion104UsesThreeDaysAndPreservesHistorySwitchSettingAndLastCopy() async throws {
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
        XCTAssertEqual(state.settings.retention, 3)
        XCTAssertTrue(state.settings.autoSwitch)
        XCTAssertEqual(state.event, PasteEvent(stamp: stamp, key: clip.key))
        let body = try await store.body("original")
        XCTAssertEqual(body.text, text)
        try await store.delete("original")
        try await store.observe(clip, stamp: stamp, replacing: state.event)
        let rows = try await store.page()
        XCTAssertTrue(rows.isEmpty)
    }

    func testLegacyWindowIsAppliedOnceAndReadOnlyAccessSeesTheSameHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(), old = now.addingTimeInterval(-4 * 86_400)
        let image = PreparedClip(key: "old-image", preview: "图片", body: ClipBody(type: "public.png", data: Data([1, 2])),
                                 thumbnail: Data([3]))
        let expiredID: String
        do {
            let store = try HistoryStore(directory: directory)
            try await store.retention(90)
            let items: [PreparedClip] = [image, .text("置顶"), .text("已归类"), .text("今天")]
            for (index, clip) in items.enumerated() {
                let previous = try await store.state().event
                try await store.observe(clip, stamp: .init(boot: 1, count: index + 1), replacing: previous,
                                        now: index == 3 ? now : old)
            }
            let rows = try await store.page()
            expiredID = try XCTUnwrap(rows.first(where: \.isImage)).id
            let pin = try XCTUnwrap(rows.first { $0.preview == "置顶" })
            let filed = try XCTUnwrap(rows.first { $0.preview == "已归类" })
            try await store.organize(.pin(pin.id, true))
            try await store.organize(.move(filed.id, to: "work"))
            let db = try Database(url: directory.appendingPathComponent("History.sqlite3"), readOnly: false)
            try db.execute("PRAGMA user_version = 0")
        }
        let reader = try HistoryStore(directory: directory, readOnly: true)
        let readPage = try await reader.categoryPage(since: -1, category: "", limit: 60)
        XCTAssertEqual(readPage.0.settings.retention, 3)
        XCTAssertEqual(try XCTUnwrap(readPage.1).rows.map(\.preview), ["置顶", "今天"])
        let original = try await reader.body(expiredID)
        XCTAssertEqual(original.data, image.body.data)

        let writer = try HistoryStore(directory: directory)
        let remaining = try await writer.page()
        XCTAssertEqual(Set(remaining.map(\.preview)), ["置顶", "已归类", "今天"])
        XCTAssertEqual(remaining.first(where: \.isPinned)?.preview, "置顶")
        let work = try await writer.page(category: "work")
        XCTAssertEqual(work.map(\.preview), ["已归类"])
        let thumb = try await writer.thumbnail(expiredID)
        XCTAssertNil(thumb)
        do { _ = try await writer.body(expiredID); XCTFail("The expired original survived the migration") } catch HistoryError.missing {}
        try await writer.retention(15)
        let reopened = try HistoryStore(directory: directory)
        let saved = try await reopened.state().settings.retention
        let sharedChoice = try await reader.state().settings.retention
        XCTAssertEqual(saved, 15)
        XCTAssertEqual(sharedChoice, 15)
    }
}
