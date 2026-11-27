import XCTest

final class OrganizationTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func capture(_ text: String, _ count: Int, into store: HistoryStore) async throws -> ClipRow {
        let previous = try await store.state().event
        try await store.observe(.text(text), stamp: .init(boot: 100,count: count), replacing: previous)
        let page = try await store.page()
        return try XCTUnwrap(page.first { $0.preview == text })
    }

    func testUndoMoveThenDeleteThenDismissKeyboard() async throws {
        let store = try HistoryStore(directory: directory)
        let row = try await capture("周三见",1,into: store)
        let group = try await store.saveCategory(name: "项目")
        try await store.organize(.move(row.id,to: group.id))
        try await store.organize(.remove(row.id))
        try await store.undoOrganization()
        let recovered = try await store.page(category: group.id)
        XCTAssertEqual(recovered,[row])
        try await store.undoOrganization()
        let ordinary = try await store.page(category: ClipCategory.ordinary.id)
        XCTAssertEqual(ordinary,[row])
        try await store.organize(.move(row.id,to: group.id))
        let reopened = try HistoryStore(directory: directory)
        let reopenedDepth = try await reopened.undoDepth()
        let filed = try await reopened.page(category: group.id)
        XCTAssertEqual(reopenedDepth,0)
        XCTAssertEqual(filed,[row])
        try await store.discardUndo()
        let clearedDepth = try await store.undoDepth()
        XCTAssertEqual(clearedDepth,0)
    }

    func testBulkClearProtectsFiledAndPinnedAndDoesNotDuplicateNewCopy() async throws {
        let store = try HistoryStore(directory: directory)
        let a = try await capture("A",1,into: store)
        let b = try await capture("B",2,into: store)
        let c = try await capture("C",3,into: store)
        let d = try await capture("D",4,into: store)
        try await store.organize(.move(a.id,to: "work"))
        try await store.organize(.pin(b.id,true))
        try await store.organize(.clearOrdinary)
        let left = try await store.page()
        XCTAssertEqual(Set(left.map(\.id)),[a.id,b.id])
        let newer = try await capture("C",5,into: store)
        XCTAssertNotEqual(c.id,newer.id)
        try await store.undoOrganization()
        let restored = try await store.page()
        XCTAssertEqual(Set(restored.map(\.id)),[a.id,b.id,d.id,newer.id])
        try await store.undoOrganization()
        let unpinned = try await store.page()
        XCTAssertFalse(unpinned.contains(where: \.isPinned))
        try await store.deleteCategory("work")
        let ordinary = try await store.page(category: "")
        XCTAssertEqual(ordinary.count,4)
    }
}
