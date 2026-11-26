import XCTest
@testable import Clipboard

final class HistoryExchangeTests: XCTestCase {
    private var root: URL!
    private var app: HistoryStore!
    private var keyboard: HistoryStore!
    private let start = Date()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        app = try HistoryStore(directory: root.appendingPathComponent("app"), privateStorage: true)
        keyboard = try HistoryStore(directory: root.appendingPathComponent("keyboard"), privateStorage: true)
    }

    override func tearDownWithError() throws {
        app = nil
        keyboard = nil
        try FileManager.default.removeItem(at: root)
    }

    private func capture(_ clip: PreparedClip, in store: HistoryStore, at seconds: Int) async throws {
        let event = try await store.state().event
        try await store.observe(clip, stamp: PasteStamp(boot: 100, count: seconds), replacing: event,
                                now: start.addingTimeInterval(Double(seconds)))
    }

    private func exchange(from sender: HistoryStore, to receiver: HistoryStore, fromMain: Bool) async throws {
        let file = root.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let version = try await sender.receipt().local
        try await sender.exportHistory(to: file)
        try await receiver.mergeHistory(from: file, expectedID: version.id, fromMainApp: fromMain, now: start)
    }

    func testTwoWayMergePreservesFullBodiesSettingsAndPasteEvents() async throws {
        let long = String(repeating: "多行文字\n", count: 130)
        let image = PreparedClip(key: "i-fixture", preview: "图片", body: ClipBody(type: "public.png",
                                 data: Data(repeating: 124, count: 200_000)), thumbnail: Data([1, 2]))
        try await capture(.text(long), in: app, at: 1)
        try await capture(.text(long), in: keyboard, at: 5)
        try await capture(image, in: keyboard, at: 6)
        try await app.retention(7, now: start)
        try await app.autoSwitch(true)
        let original = try await app.page(), keyEvent = try await keyboard.state().event
        try await exchange(from: keyboard, to: app, fromMain: false)
        let rows = try await app.page()
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].id, original[0].id)
        XCTAssertEqual(rows[1].updated, start.addingTimeInterval(5).timeIntervalSince1970, accuracy: 0.0001)
        let picture = try await app.body(rows[0].id), thumb = try await app.thumbnail(rows[0].id)
        let body = try await app.body(rows[1].id)
        XCTAssertEqual(picture.data, image.body.data)
        XCTAssertEqual(thumb, image.thumbnail)
        XCTAssertEqual(body.text, long)
        let revision = try await app.state().revision
        try await exchange(from: keyboard, to: app, fromMain: false)
        let repeated = try await app.state()
        XCTAssertEqual(repeated.revision, revision)
        XCTAssertEqual(repeated.event?.stamp.count, 1)
        try await exchange(from: app, to: keyboard, fromMain: true)
        let result = try await keyboard.state(), appSettings = try await app.state().settings
        XCTAssertEqual(result.event, keyEvent)
        XCTAssertEqual(result.settings.retention, 7)
        XCTAssertTrue(result.settings.autoSwitch)
        XCTAssertTrue(appSettings.keyboardConfigured)
    }

    func testDeleteClearAndGenuineRecopyAcrossIndependentStores() async throws {
        try await capture(.text("first"), in: keyboard, at: 1)
        try await exchange(from: keyboard, to: app, fromMain: false)
        let rows = try await app.page()
        try await app.delete(rows[0].id, now: start.addingTimeInterval(2))
        try await capture(.text("other"), in: keyboard, at: 3)
        try await exchange(from: keyboard, to: app, fromMain: false)
        try await exchange(from: app, to: keyboard, fromMain: true)
        let afterDelete = try await keyboard.page()
        XCTAssertEqual(afterDelete.map(\.preview), ["other"])
        try await capture(.text("first"), in: keyboard, at: 4)
        try await exchange(from: keyboard, to: app, fromMain: false)
        let afterRecopy = try await app.page()
        XCTAssertEqual(afterRecopy.map(\.preview), ["first", "other"])
        try await app.delete(now: start.addingTimeInterval(5))
        try await capture(.text("new"), in: keyboard, at: 6)
        try await exchange(from: keyboard, to: app, fromMain: false)
        try await exchange(from: app, to: keyboard, fromMain: true)
        let a = try await app.page(), b = try await keyboard.page()
        XCTAssertEqual(a.map(\.preview), ["new"])
        XCTAssertEqual(b.map(\.preview), ["new"])
    }

    func testRejectedSnapshotLeavesStateReadyForRetry() async throws {
        try await capture(.text("private"), in: keyboard, at: 1)
        let file = root.appendingPathComponent("received.sqlite3")
        try await keyboard.exportHistory(to: file)
        do {
            try await app.mergeHistory(from: file, expectedID: "wrong store", fromMainApp: false)
            XCTFail("A mismatched snapshot was accepted")
        } catch HistoryError.unreadable {}
        let before = try await app.receipt(), rows = try await app.page()
        XCTAssertNil(before.received)
        XCTAssertTrue(rows.isEmpty)
        try await exchange(from: keyboard, to: app, fromMain: false)
        let after = try await app.receipt(), expected = try await keyboard.receipt().local
        XCTAssertEqual(after.received, expected)
    }
}
