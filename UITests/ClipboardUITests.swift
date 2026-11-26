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
            let allow = host.buttons.matching(NSPredicate(format: "label IN %@", ["Allow Paste", "允许粘贴"])).firstMatch
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
        application.descendants(matching: .any).matching(NSPredicate(format: "label == %@", value)).firstMatch
    }

    private func settingsRow(_ title: String, in settings: XCUIApplication) -> XCUIElement {
        let row = settings.staticTexts[title].firstMatch
        for _ in 0..<5 {
            if row.exists && row.isHittable { return row }
            settings.swipeUp()
        }
        return row
    }

    func testEnabledKeyboardInHostTextField() {
        app.launch()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        settingsRow("General", in: settings).tap()
        settingsRow("Keyboard", in: settings).tap()
        settingsRow("Keyboards", in: settings).tap()
        let clipboard = settings.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'Clipboard'")).firstMatch
        if !clipboard.exists {
            settings.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Add New Keyboard'")).firstMatch.tap()
            XCTAssertTrue(clipboard.waitForExistence(timeout: 8), settings.debugDescription)
            clipboard.tap()
        }
        XCTAssertTrue(clipboard.waitForExistence(timeout: 5))
        clipboard.tap()
        let fullAccess = settings.switches.firstMatch
        XCTAssertTrue(fullAccess.waitForExistence(timeout: 5), settings.debugDescription)
        if fullAccess.value as? String != "1" {
            fullAccess.tap()
            let allow = settings.buttons["Allow"]
            if allow.waitForExistence(timeout: 3) { allow.tap() }
        }
        fixture.launch()
        fixture.buttons["Copy text"].tap()
        fixture.textViews["input"].tap()
        let entry = label(text, in: fixture)
        if !entry.exists {
            let next = fixture.buttons.matching(NSPredicate(format: "label IN[c] %@ OR identifier IN %@",
                ["Next keyboard", "Show next keyboard", "Change Keyboard", "Switch Keyboard", "Emoji"],
                ["NextKeyboard", "InputModeSwitchKey"])).firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 5), fixture.debugDescription)
            next.press(forDuration: 1.0)
            let menuItem = fixture.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] 'Clipboard'")).firstMatch
            if menuItem.waitForExistence(timeout: 2) { menuItem.tap() }
            else { next.tap() }
        }
        XCTAssertTrue(waitFor(entry), fixture.debugDescription)
        entry.tap()
        XCTAssertEqual(fixture.textViews["input"].value as? String, text)
        app.activate()
        XCTAssertTrue(waitFor(label(text, in: app)), app.debugDescription)
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
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
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
