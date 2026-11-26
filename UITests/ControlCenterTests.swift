import XCTest

@MainActor
final class ControlCenterTests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let controls = XCUIApplication(bundleIdentifier: "com.apple.ControlCenter")
    private let fixture = XCUIApplication(bundleIdentifier: "net.chkf.ClipboardTestHost")

    override func setUp() { continueAfterFailure = false }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private var owners: [XCUIApplication] {
        controls.state == .notRunning ? [springboard] : [springboard, controls]
    }

    private func visible(_ predicate: NSPredicate, timeout: TimeInterval = 2) -> XCUIElement? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            for owner in owners {
                let query = owner.descendants(matching: .any).matching(predicate)
                if let match = query.allElementsBoundByIndex.first(where: { $0.isHittable && !$0.frame.isEmpty }) {
                    return match
                }
            }
        } while Date() < end
        return nil
    }

    private func labels(_ names: [String]) -> NSPredicate {
        NSPredicate(format: "label IN[c] %@ OR identifier IN[c] %@", names, names)
    }

    private var hierarchy: String {
        owners.map { String($0.debugDescription.prefix(18000)) }.joined(separator: "\n")
    }

    private func openCenter() {
        let start = springboard.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.004))
        let end = springboard.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.60))
        start.press(forDuration: 0.06, thenDragTo: end)
        if let next = visible(labels(["Continue", "继续"]), timeout: 1) { next.tap() }
    }

    private var tile: NSPredicate {
        NSPredicate(format: "label CONTAINS %@ OR identifier == %@", "连续复制", "net.chkf.Clipboard.collect")
    }

    private func installControl() throws {
        if visible(tile, timeout: 2) != nil { return }
        let add = labels(["Add a Control", "添加控制", "添加控制项"])
        if let edit = visible(labels(["Add Controls", "Edit Controls", "添加控制", "编辑控制", "AddButton"])) { edit.tap() }
        else { springboard.coordinate(withNormalizedOffset: .init(dx: 0.078, dy: 0.067)).tap() }
        if let button = visible(add) { button.tap() }
        else { springboard.coordinate(withNormalizedOffset: .init(dx: 0.50, dy: 0.943)).tap() }
        snapshot("ControlCenterGallery")
        let fields = NSPredicate(format: "elementType IN %@",
                                 [XCUIElement.ElementType.searchField.rawValue, XCUIElement.ElementType.textField.rawValue])
        if let search = visible(fields, timeout: 5) {
            search.tap()
            search.typeText("Clipboard")
        } else if let search = visible(NSPredicate(format: "label CONTAINS[c] 'Search Controls' OR label CONTAINS '搜索控制'")) {
            search.tap()
            if let field = visible(fields) { field.typeText("Clipboard") }
        }
        if visible(tile, timeout: 3) == nil, let group = visible(labels(["Clipboard", "Clipboard 连拷"])) { group.tap() }
        let entry = try XCTUnwrap(visible(tile, timeout: 8), hierarchy)
        snapshot("ClipboardControlInGallery")
        entry.tap()
        if let addControl = visible(labels(["Add Control", "添加", "添加控件"]), timeout: 1) { addControl.tap() }
        // Leave the editor and reopen the installed surface as a user would.
        XCUIDevice.shared.press(.home)
        openCenter()
    }

    private func assertStarted() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "Clipboard did not open")
        XCTAssertTrue(app.buttons["captureToggle"].waitForExistence(timeout: 12), app.debugDescription)
        let reached = NSPredicate { _, _ in
            self.app.buttons["captureToggle"].label == "停止连拷" || self.app.staticTexts["captureStatus"].exists
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: reached, object: nil)], timeout: 15), .completed, app.debugDescription)
        if app.staticTexts["captureStatus"].exists {
            XCTAssertEqual(app.staticTexts["captureStatus"].label, "这台设备当前不支持画中画。")
        }
    }

    func testInstalledControlOpensClipboardAndStartsCollection() throws {
        app.launch()
        XCTAssertTrue(app.buttons["openCollection"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        openCenter()
        try installControl()
        let installed = try XCTUnwrap(visible(tile, timeout: 8), hierarchy)
        snapshot("ClipboardControlInstalled")
        installed.tap()
        assertStarted()
        snapshot("ClipboardStartedFromControlCenter")
    }

    func testShortcutURLOpensClipboardAndStartsCollection() {
        app.terminate()
        fixture.launchArguments = ["-LaunchCollectionURL"]
        fixture.launch()
        fixture.buttons["Toggle Clipboard via URL"].tap()
        for owner in [springboard, fixture] {
            let open = owner.alerts.buttons.matching(labels(["Open", "打开"])).firstMatch
            if open.waitForExistence(timeout: 1) { open.tap(); break }
        }
        assertStarted()
    }
}
