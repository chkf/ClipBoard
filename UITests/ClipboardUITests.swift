import XCTest

@MainActor
final class ClipboardUITests: XCTestCase {
    private let app = XCUIApplication()
    private let fixture = XCUIApplication(bundleIdentifier: "net.chkf.ClipboardTestHost")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let text = "Clipboard UI fixture\nsecond line\nthird line"

    override func setUp() { continueAfterFailure = false }

    private func allowPasteIfRequested() {
        for host in [springboard, app, fixture] {
            let allow = host.buttons.matching(NSPredicate(format: "label IN %@", ["Allow Paste", "允许粘贴"])).first
            if allow.exists { allow.tap(); return }
        }
    }

    private func waitFor(_ element: XCUIElement, seconds: Double = 15) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            allowPasteIfRequested()
            if element.waitForExistence(timeout: 0.5) { return true }
        } while Date() < end
        return false
    }

    private func label(_ value: String, in application: XCUIApplication) -> XCUIElement {
        application.descendants(matching: .any).matching(NSPredicate(format: "label == %@", value)).first
    }

    func testManagementWithAnotherAppsPasteboard() {
        app.launch()
        fixture.launch()
        fixture.buttons["Copy text"].tap()
        app.activate()
        let row = label(text, in: app)
        XCTAssertTrue(waitFor(row), app.debugDescription)
        row.press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["closePreview"].waitForExistence(timeout: 4))
        XCTAssertTrue(label(text, in: app).exists)
        app.buttons["closePreview"].tap()
        row.tap()
        XCTAssertTrue(app.staticTexts["已复制"].waitForExistence(timeout: 3) || label("已复制", in: app).exists)
        fixture.activate()
        fixture.buttons["Copy image"].tap()
        app.activate()
        let picture = label("图片", in: app)
        XCTAssertTrue(waitFor(picture), app.debugDescription)
        picture.press(forDuration: 0.9)
        XCTAssertTrue(app.navigationBars["图片预览"].waitForExistence(timeout: 4))
        app.buttons["closePreview"].tap()
        row.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertFalse(row.exists)
        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.switches["autoSwitch"].exists)
        app.switches["autoSwitch"].tap()
        app.buttons["clearHistory"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).first
        cancel.tap()
        app.buttons["closeSettings"].tap()
        XCTAssertTrue(picture.exists)
        app.buttons["openSettings"].tap()
        app.buttons["clearHistory"].tap()
        app.buttons["确认清空"].tap()
        app.buttons["closeSettings"].tap()
        XCTAssertTrue(label("暂无历史记录", in: app).waitForExistence(timeout: 4))
        app.terminate()
        app.launch()
        XCTAssertTrue(label("暂无历史记录", in: app).waitForExistence(timeout: 6))
        XCTAssertFalse(picture.exists)
    }
}
