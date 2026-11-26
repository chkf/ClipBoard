import UIKit
import XCTest
@testable import Clipboard

@MainActor
final class SessionTests: XCTestCase {
    private func eventually(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(predicate())
    }

    func testAutomaticCaptureReopenOwnWritesAndKeyboardReuse() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try HistoryStore(directory: directory)
        let session = ClipboardSession(open: { _ in store })
        defer { session.stop(); try? FileManager.default.removeItem(at: directory) }
        let text = "  line one\nline two\nline three\n"
        UIPasteboard.general.string = text
        session.start(.app)
        try await eventually { session.rows.first?.preview == text }
        let initial = try XCTUnwrap(session.rows.first)
        session.stop()
        session.start(.keyboard(fullAccess: true))
        try await eventually { session.loaded && session.settings.keyboardConfigured }
        XCTAssertEqual(initial, session.rows.first)
        var inserted = "", switches = 0
        await session.selectInKeyboard(initial, insert: { inserted = $0 }, advance: { switches += 1 })
        XCTAssertEqual(inserted, text)
        XCTAssertEqual(switches, 0)
        let unchanged = try await store.page()
        XCTAssertEqual(unchanged.first, initial)
        try await store.autoSwitch(true)
        await session.selectInKeyboard(initial, insert: { inserted = $0 }, advance: { switches += 1 })
        XCTAssertEqual(switches, 1)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        }
        let png = try XCTUnwrap(image.pngData())
        UIPasteboard.general.setData(png, forPasteboardType: "public.png")
        try await eventually { session.rows.first?.isImage == true }
        let item = try XCTUnwrap(session.rows.first)
        UIPasteboard.general.string = "another copy"
        try await eventually { session.rows.first?.preview == "another copy" }
        await session.selectInKeyboard(item, insert: { _ in XCTFail("Image inserted as text") }, advance: { switches += 1 })
        XCTAssertEqual(UIPasteboard.general.data(forPasteboardType: "public.png"), png)
        XCTAssertEqual(switches, 1)
        let copied = try await store.page()
        XCTAssertEqual(copied.first?.id, item.id)
        XCTAssertGreaterThan(try XCTUnwrap(copied.first?.updated), item.updated)
        session.stop()
        session.start(.app)
        try await eventually { session.loaded }
        XCTAssertEqual(session.rows, copied)
        await session.edit { try await $0.delete() }
        session.stop()
        session.start(.app)
        try await eventually { session.loaded }
        XCTAssertTrue(session.rows.isEmpty)
        XCTAssertEqual(UIPasteboard.general.data(forPasteboardType: "public.png"), png)
        session.active = false
        UIPasteboard.general.string = "while inactive"
        try await Task.sleep(for: .milliseconds(1250))
        XCTAssertTrue(session.rows.isEmpty)
        session.start(.app)
        try await eventually { session.rows.first?.preview == "while inactive" }
        let lastCopy = try await store.state().event
        UIPasteboard.general.items = []
        try await Task.sleep(for: .milliseconds(1250))
        let afterEmptyProbe = try await store.state().event
        XCTAssertEqual(afterEmptyProbe, lastCopy)
    }

    func testKeyboardWithoutFullAccessOnlyInsertsExistingText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try HistoryStore(directory: directory)
        let text = "saved"
        try await store.observe(.text(text), stamp: PasteStamp(boot: 1, count: 1), replacing: nil)
        let reader = try HistoryStore(directory: directory, readOnly: true)
        var fullAccess = false
        let session = ClipboardSession(keyboardAccess: { fullAccess }, open: { readOnly in readOnly ? reader : store })
        defer { session.stop(); try? FileManager.default.removeItem(at: directory) }
        UIPasteboard.general.string = "must not capture"
        session.start(.keyboard(fullAccess: false))
        try await eventually { session.loaded }
        let row = try XCTUnwrap(session.rows.first)
        var inserted = ""
        await session.selectInKeyboard(row, insert: { inserted = $0 }, advance: { XCTFail() })
        XCTAssertEqual(inserted, text)
        let copied = await session.copy(row)
        XCTAssertFalse(copied)
        XCTAssertEqual(UIPasteboard.general.string, "must not capture")
        let rows = try await store.page()
        XCTAssertEqual(rows.map(\.preview), [text])
        fullAccess = true
        try await eventually { session.mode.mayWrite && session.rows.first?.preview == "must not capture" }
        fullAccess = false
        try await eventually { !session.mode.mayWrite && session.loaded }
        UIPasteboard.general.string = "after revocation"
        XCTAssertFalse(session.rows.contains { $0.preview == "after revocation" })
    }
}
