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
        let row = settings.cells.containing(.staticText, identifier: title).firstMatch
        let button = settings.buttons[title].firstMatch
        let viewport = settings.frame.insetBy(dx: 8, dy: 76)
        for _ in 0..<5 {
            for candidate in [row, button] where candidate.exists {
                let rect = candidate.frame
                if !rect.isEmpty, viewport.contains(CGPoint(x: rect.midX, y: rect.midY)) { return candidate }
            }
            settings.swipeUp()
        }
        return row
    }

    private func tapSwitch(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
    }

    private func copyInFixture(_ type: String) {
        XCTAssertTrue(fixture.wait(for: .runningForeground, timeout: 8))
        let button = fixture.buttons["Copy " + type]
        let expected = type.capitalized + " copied"
        button.tap()
        let status = fixture.staticTexts["copyStatus"]
        let written = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [written], timeout: 8), .completed, fixture.debugDescription)
    }

    func testEnabledKeyboardInHostTextField() {
        app.launch()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        settingsRow("General", in: settings).tap()
        XCTAssertTrue(settings.navigationBars["General"].waitForExistence(timeout: 8), settings.debugDescription)
        settingsRow("Keyboard", in: settings).tap()
        let installed = settings.cells["KEYBOARDS"]
        XCTAssertTrue(installed.waitForExistence(timeout: 5), settings.debugDescription)
        installed.tap()
        let items = settings.descendants(matching: .any)
        let clipboard = items.matching(NSPredicate(format: "label BEGINSWITH[c] 'Clipboard'")).firstMatch
        if !clipboard.exists {
            let add = items.matching(NSPredicate(format: "label BEGINSWITH[c] 'Add New Keyboard' OR identifier == 'AddNewKeyboard'")).firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 5), settings.debugDescription)
            add.tap()
            XCTAssertTrue(clipboard.waitForExistence(timeout: 8), settings.debugDescription)
            clipboard.tap()
        }
        XCTAssertTrue(clipboard.waitForExistence(timeout: 5))
        clipboard.tap()
        let fullAccess = settings.switches.firstMatch
        XCTAssertTrue(fullAccess.waitForExistence(timeout: 5), settings.debugDescription)
        if fullAccess.value as? String != "1" {
            tapSwitch(fullAccess)
            for owner in [settings, springboard] {
                let confirm = owner.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "允许"])).firstMatch
                if confirm.waitForExistence(timeout: 2) { confirm.tap(); break }
                let modal = owner.alerts.firstMatch.exists ? owner.alerts.firstMatch : owner.sheets.firstMatch
                let grant = modal.buttons.matching(NSPredicate(format: "label IN[c] %@", ["Allow Full Access", "允许完全访问"])).firstMatch
                if grant.exists { grant.tap(); break }
            }
        }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: fullAccess)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed, settings.debugDescription)
        fixture.launch()
        copyInFixture("text")
        fixture.textViews["input"].tap()
        let entry = fixture.buttons[text]
        if !waitFor(entry, seconds: 8) && fixture.keyboards.keys.count > 2 {
            let next = fixture.buttons.matching(NSPredicate(format: "label IN[c] %@ OR identifier IN %@",
                ["Next keyboard", "Show next keyboard", "Change Keyboard", "Switch Keyboard", "Emoji", "下一个键盘", "切换键盘"],
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
        app.buttons["openSettings"].tap()
        app.buttons["clearHistory"].tap()
        app.alerts.buttons["确认清空"].tap()
        app.buttons["closeSettings"].tap()
        fixture.launch()
        copyInFixture("text")
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
        copyInFixture("image")
        app.activate()
        let picture = app.buttons["historyImage"].firstMatch
        XCTAssertTrue(waitFor(picture), app.debugDescription)
        picture.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 1)
        XCTAssertTrue(app.navigationBars["图片预览"].waitForExistence(timeout: 6), app.debugDescription)
        app.buttons["closePreview"].tap()
        row.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertFalse(row.exists)
        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.switches["autoSwitch"].exists)
        let autoSwitch = app.switches["autoSwitch"]
        let previous = autoSwitch.value as? String
        tapSwitch(autoSwitch)
        XCTAssertNotEqual(autoSwitch.value as? String, previous)
        app.buttons["clearHistory"].tap()
        let cancel = app.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 4), app.debugDescription)
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
