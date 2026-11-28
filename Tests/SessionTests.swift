import UIKit
import XCTest

@MainActor
final class SessionTests: XCTestCase {
    private func eventually(file: StaticString = #filePath, line: UInt = #line,
                            _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(predicate(), file: file, line: line)
    }

    func testSwitchKeepsOrdinaryPreviewAndFirstTapWhileNewConnectionOpens() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let seed = try HistoryStore(directory: directory)
        try await seed.observe(.text("第一条"), stamp: .init(boot: 1, count: 1), replacing: nil)
        var hold: AsyncStream<Void>?
        let session = ClipboardSession(open: { readOnly in
            if let hold { for await _ in hold {} }
            return try HistoryStore(directory: directory, readOnly: readOnly)
        })
        defer { session.stop(); try? FileManager.default.removeItem(at: directory) }
        session.start(fullAccess: true, captureEnabled: false)
        try await eventually { session.loaded }
        let row = try XCTUnwrap(session.rows.first)
        session.perform(.pin(row.id, true))
        try await eventually { session.undoAvailable && session.rows.first?.isPinned == true }
        let displayed = session.rows, categories = session.categories
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        hold = gate.stream

        session.suspendForSwitch()
        XCTAssertEqual(session.rows, displayed)
        XCTAssertNil(session.store)
        session.finishDisappearance()
        session.start(fullAccess: true, captureEnabled: false)
        XCTAssertFalse(session.loaded)
        XCTAssertEqual(session.entryPhase, .history)
        XCTAssertEqual(session.rows, displayed)
        XCTAssertEqual(session.categories, categories)
        XCTAssertFalse(session.undoAvailable)
        var text = ""
        let tap = Task { await session.selectInKeyboard(row, insert: { text += $0 }, advance: { XCTFail() }) }
        await Task.yield()
        gate.continuation.finish()
        await tap.value
        XCTAssertEqual(text, "第一条")
        XCTAssertFalse(session.undoAvailable)

        let secondGate = AsyncStream<Void>.makeStream()
        defer { secondGate.continuation.finish() }
        hold = secondGate.stream
        session.suspendForSwitch()
        session.start(fullAccess: true, captureEnabled: false)
        let abandoned = Task { await session.selectInKeyboard(row, insert: { _ in XCTFail("Inserted after dismissal") }, advance: { XCTFail() }) }
        await Task.yield()
        session.stop()
        secondGate.continuation.finish()
        await abandoned.value
        XCTAssertTrue(session.rows.isEmpty)
    }

    func testSwitchDropsFiledOrRevokedPreviewAndKeepsInputAvailableDuringSlowRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let seed = try HistoryStore(directory: directory)
        try await seed.observe(.text("只在工作分类"), stamp: .init(boot: 1, count: 1), replacing: nil)
        let page = try await seed.page()
        let row = try XCTUnwrap(page.first)
        try await seed.organize(.move(row.id, to: "work"))
        let gate = AsyncStream<Void>.makeStream()
        let session = ClipboardSession(open: { readOnly in
            if readOnly {
                for await _ in gate.stream {}
                throw HistoryError.sharedContainer
            }
            return try HistoryStore(directory: directory)
        })
        defer { gate.continuation.finish(); session.stop(); try? FileManager.default.removeItem(at: directory) }
        session.start(fullAccess: true, captureEnabled: false)
        try await eventually { session.loaded }
        session.selectCategory("work")
        try await eventually { session.rows.first == row }
        session.suspendForSwitch()
        XCTAssertEqual(session.rows, [row])
        session.finishDisappearance()
        XCTAssertTrue(session.rows.isEmpty)
        session.start(fullAccess: true, captureEnabled: false)
        try await eventually { session.loaded }
        XCTAssertEqual(session.category, ClipCategory.ordinary.id)
        XCTAssertTrue(session.rows.isEmpty)
        let previous = try await seed.state().event
        try await seed.observe(.text("普通记录"), stamp: .init(boot: 1, count: 2), replacing: previous)
        try await eventually { !session.rows.isEmpty }
        session.suspendForSwitch()
        session.start(fullAccess: false, captureEnabled: false)
        XCTAssertEqual(session.entryPhase, .preparing)
        XCTAssertTrue(session.rows.isEmpty)
        try await eventually { session.entryPhase == .inputOnly }
        XCTAssertNil(session.message)
        gate.continuation.finish()
        try await eventually { session.entryPhase == .unavailable }
        XCTAssertTrue(session.rows.isEmpty)
    }

    func testAutomaticCaptureReopenOwnWritesAndKeyboardReuse() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try HistoryStore(directory: directory)
        let session = ClipboardSession(open: { _ in store })
        defer { session.stop(); try? FileManager.default.removeItem(at: directory) }
        let text = "  line one\nline two\nline three\n"
        let board = UIPasteboard.general
        let before = board.changeCount
        board.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
        try await eventually { board.changeCount != before && board.string == text }
        session.start(fullAccess: true)
        try await eventually { session.rows.first?.preview == text }
        let initial = try XCTUnwrap(session.rows.first)
        session.stop()
        session.start(fullAccess: true)
        try await eventually { session.loaded }
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
        session.start(fullAccess: true)
        try await eventually { session.loaded }
        XCTAssertEqual(session.rows, copied)
        await session.edit { try await $0.delete() }
        session.stop()
        session.start(fullAccess: true)
        try await eventually { session.loaded }
        XCTAssertTrue(session.rows.isEmpty)
        XCTAssertEqual(UIPasteboard.general.data(forPasteboardType: "public.png"), png)
        session.active = false
        UIPasteboard.general.string = "while inactive"
        try await Task.sleep(for: .milliseconds(1250))
        XCTAssertTrue(session.rows.isEmpty)
        session.start(fullAccess: true)
        try await eventually { session.rows.first?.preview == "while inactive" }
        let lastCopy = try await store.state().event
        UIPasteboard.general.items = []
        try await Task.sleep(for: .milliseconds(1250))
        let afterEmptyProbe = try await store.state().event
        XCTAssertEqual(afterEmptyProbe, lastCopy)
    }

    func testResumingRechecksTheContentsOfAnAlreadySeenPasteCount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try HistoryStore(directory: directory)
        let session = ClipboardSession(open: { _ in store })
        defer { session.stop(); try? FileManager.default.removeItem(at: directory) }
        let text = "Current clipboard content"
        let board = UIPasteboard.general
        let before = board.changeCount
        board.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
        try await eventually { board.changeCount != before && board.string == text }
        session.start(fullAccess: true)
        try await eventually { session.rows.first?.preview == text }

        let state = try await store.state()
        let event = try XCTUnwrap(state.event)
        let earlier = "Earlier representation"
        try await store.observe(.text(earlier), stamp: event.stamp, replacing: event)
        try await eventually { session.rows.first?.preview == earlier }
        session.active = false
        session.start(fullAccess: true)
        try await eventually { session.rows.first?.preview == text }
        XCTAssertEqual(board.changeCount, event.stamp.count)
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
        session.start(fullAccess: false)
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
        try await eventually { session.fullAccess && session.rows.first?.preview == "must not capture" }
        fullAccess = false
        try await eventually { !session.fullAccess && session.loaded }
        UIPasteboard.general.string = "after revocation"
        XCTAssertFalse(session.rows.contains { $0.preview == "after revocation" })
    }
}
