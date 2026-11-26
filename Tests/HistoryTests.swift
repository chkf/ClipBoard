import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest

final class HistoryTests: XCTestCase {
    private var directory: URL!
    private var store: HistoryStore!
    private let start = Date(timeIntervalSince1970: 1_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try HistoryStore(directory: directory)
    }
    override func tearDownWithError() throws {
        store = nil
        try FileManager.default.removeItem(at: directory)
    }

    private func capture(_ prepared: PreparedClip?, _ count: Int, boot: Double = 100, day: Int = 0) async throws {
        let previous = try await store.state().event
        try await store.observe(prepared, stamp: PasteStamp(boot: boot, count: count), replacing: previous,
                                now: start.addingTimeInterval(Double(day) * 86_400))
    }

    func testPinSearchAndRetentionSurviveReopening() async throws {
        let long = String(repeating: "字", count: 260) + "NeEdLe"
        try await capture(.text("短句"), 1)
        try await capture(.text(long), 2)
        let first = try await store.page(matching: "duanju")
        let pinned = try XCTUnwrap(first.first)
        try await store.pin(pinned.id, enabled: true, now: start)
        let reopened = try HistoryStore(directory: directory)
        let page = try await reopened.page(limit: 1)
        XCTAssertTrue(page[0].isPinned)
        let next = try await reopened.page(after: page[0], limit: 1)
        let found = try await reopened.page(matching: "needle")
        XCTAssertEqual(next.first?.id, found.first?.id)
        let initials = try await reopened.page(matching: "dj")
        XCTAssertEqual(initials.first?.id, pinned.id)
        try await reopened.prune(now: start.addingTimeInterval(120 * 86400))
        try await reopened.clearUnpinned()
        let remaining = try await reopened.page()
        XCTAssertEqual(remaining.map(\.id), [pinned.id])
        try await reopened.pin(pinned.id, enabled: false)
        try await reopened.clearUnpinned()
        let empty = try await reopened.page()
        XCTAssertTrue(empty.isEmpty)
    }

    func testCompleteTextIdentityRecopyAndReopen() async throws {
        let prefix = String(repeating: "字", count: 260)
        let text = prefix + "\n  code\0\n"
        try await capture(.text(text), 1)
        let firstRows = try await store.page()
        let first = try XCTUnwrap(firstRows.first)
        let body = try await store.body(first.id)
        XCTAssertEqual(body.text, text)
        XCTAssertNotEqual(first.preview, text)
        try await capture(.text(prefix + "\n"), 2, day: 1)
        try await capture(.text(text), 3, day: 2)
        try await capture(.text(text), 3, day: 3)
        try await store.autoSwitch(true)
        try await store.retention(90, now: start)
        let reopened = try HistoryStore(directory: directory)
        let rows = try await reopened.page(), settings = try await reopened.state().settings
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.id, first.id)
        XCTAssertEqual(rows.first?.updated, start.addingTimeInterval(2 * 86_400).timeIntervalSince1970)
        XCTAssertTrue(settings.autoSwitch)
        XCTAssertEqual(settings.retention, 90)
        XCTAssertNotEqual(PreparedClip.text("é").key, PreparedClip.text("e\u{301}").key)
    }

    func testDeletionClearRebootAndNewCopy() async throws {
        let clip = PreparedClip.text("code 123456")
        try await capture(clip, 22)
        let previousRows = try await store.page()
        try await store.delete(try XCTUnwrap(previousRows.first).id)
        try await capture(clip, 22)
        try await capture(clip, 1, boot: 200)
        var rows = try await store.page()
        XCTAssertTrue(rows.isEmpty)
        try await capture(clip, 2, boot: 200)
        rows = try await store.page()
        XCTAssertEqual(rows.count, 1)
        try await store.delete()
        try await capture(clip, 2, boot: 200)
        rows = try await store.page()
        XCTAssertTrue(rows.isEmpty)
        try await capture(.text("after reboot"), 1, boot: 300)
        rows = try await store.page()
        XCTAssertEqual(rows.first?.preview, "after reboot")
        try await capture(.text("different contents in the same run-loop batch"), 1, boot: 300, day: 1)
        let batched = try await store.page()
        XCTAssertEqual(batched.first?.preview, "different contents in the same run-loop batch")
        try await capture(.text("different contents in the same run-loop batch"), 1, boot: 300, day: 2)
        let repeated = try await store.page()
        XCTAssertEqual(repeated, batched)
    }

    func testConcurrentConnectionsAndDelayedReads() async throws {
        let other = try HistoryStore(directory: directory)
        let stamp = PasteStamp(boot: 10, count: 10), clip = PreparedClip.text("shared")
        async let first: Void = store.observe(clip, stamp: stamp, replacing: nil, now: start)
        async let second: Void = other.observe(clip, stamp: stamp, replacing: nil, now: start.addingTimeInterval(1))
        _ = try await (first, second)
        let rows = try await store.page()
        XCTAssertEqual(rows.count, 1)
        let otherRows = try await other.page()
        XCTAssertEqual(rows, otherRows)
        try await other.observe(.text("stale"), stamp: PasteStamp(boot: 10, count: 9), replacing: nil)
        let after = try await store.page()
        XCTAssertEqual(rows, after)
        struct WriteFailure: Error {}
        do {
            try await other.copy(rows[0].id) { _ in throw WriteFailure() }
            XCTFail("Failed pasteboard writes must roll back")
        } catch is WriteFailure {}
        let finalRows = try await store.page()
        XCTAssertEqual(finalRows, after)
    }

    func testImagesPreserveOriginalAndExpireWithThumbnail() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 410, height: 280), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 410, height: 280))
        }
        let bytes = try XCTUnwrap(image.pngData())
        let picture = try ImageContent.prepare(bytes)
        let encodedAgain = try XCTUnwrap(UIImage(data: bytes)?.pngData())
        XCTAssertEqual(picture.key, try ImageContent.prepare(encodedAgain).key)
        XCTAssertThrowsError(try ImageContent.prepare(Data([0, 1, 2])))
        try await capture(picture, 1)
        let imageRows = try await store.page()
        let id = try XCTUnwrap(imageRows.first?.id)
        let body = try await store.body(id), thumb = try await store.thumbnail(id)
        XCTAssertEqual(body.data, bytes)
        XCTAssertEqual(UIImage(data: try XCTUnwrap(thumb))?.size.width, 256)
        try await capture(.text("still current"), 2, day: 8)
        let other = try HistoryStore(directory: directory)
        try await other.retention(7, now: start.addingTimeInterval(10 * 86_400))
        let rows = try await store.page(), removedThumbnail = try await store.thumbnail(id)
        XCTAssertEqual(rows.map(\.preview), ["still current"])
        XCTAssertNil(removedThumbnail)
        do { _ = try await store.body(id); XCTFail("Expired original remains") } catch HistoryError.missing {}
        try await other.retention(15, now: start)
        try await other.prune(now: start.addingTimeInterval(24 * 86_400))
        let remaining = try await store.page()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testPaginationAndReadOnlyKeyboard() async throws {
        for count in 1...75 { try await capture(.text("row \(count)"), count) }
        let reader = try HistoryStore(directory: directory, readOnly: true)
        let first = try await reader.page()
        let second = try await reader.page(after: first.last)
        XCTAssertEqual(first.count, 60)
        XCTAssertEqual(Set((first + second).map(\.id)).count, 75)
        do { try await reader.delete(); XCTFail("Read-only store accepted a mutation") } catch {}
        let rows = try await store.page(limit: 100)
        XCTAssertEqual(rows.count, 75)
    }

    func testFileRichTextAndURLRepresentations() async throws {
        let data = Data("{\\rtf1 text}".utf8)
        let rich = NSItemProvider(item: data as NSData, typeIdentifier: UTType.rtf.identifier)
        let file = NSItemProvider(object: NSURL(fileURLWithPath: "/example"))
        let unsupported = try await SystemPasteboard.read([rich, file])
        XCTAssertNil(unsupported)
        let provider = NSItemProvider(object: NSURL(string: "https://example.org/a")!)
        let url = try await SystemPasteboard.read([provider])
        XCTAssertEqual(url?.body.text, "https://example.org/a")
        let raw = "  code\n\t\n"
        let text = try await SystemPasteboard.read([NSItemProvider(object: raw as NSString)])
        XCTAssertEqual(text?.body.data, Data(raw.utf8))
    }

    func testFailedProviderDoesNotConsumeTheCopyEvent() async throws {
        try await capture(.text("previous"), 1)
        let stamp = PasteStamp(boot: 100, count: 2)
        let expected = try await store.state().event
        let denied = NSItemProvider()
        denied.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { complete in
            complete(nil, CocoaError(.fileReadNoPermission))
            return nil
        }
        do {
            let clip = try await SystemPasteboard.read([denied])
            try await store.observe(clip, stamp: stamp, replacing: expected)
            XCTFail("A denied representation must not consume the event")
        } catch HistoryError.unreadable {}
        let previous = try await store.state().event
        XCTAssertEqual(previous, expected)
        let rows = try await store.page()
        XCTAssertEqual(rows.map(\.preview), ["previous"])
        try await store.observe(.text("allowed"), stamp: stamp, replacing: expected)
        let allowed = try await store.page()
        XCTAssertEqual(allowed.first?.preview, "allowed")
    }
}
