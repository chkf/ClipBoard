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
        XCTAssertTrue(button.waitForExistence(timeout: 8), fixture.debugDescription)
        button.tap()
        let status = fixture.staticTexts["copyStatus"]
        let written = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [written], timeout: 8), .completed, fixture.debugDescription)
    }

    private func enableKeyboard() {
        app.launch()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        for _ in 0..<5 where !settings.navigationBars["Settings"].exists {
            let back = settings.navigationBars.firstMatch.buttons.firstMatch
            guard back.exists else { break }
            back.tap()
        }
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
    }

    @discardableResult
    private func selectClipboard(in owner: XCUIApplication, expecting entry: XCUIElement) -> Bool {
        if waitFor(entry, seconds: 10) { return true }
        let globeLabels = ["Next keyboard", "Show next keyboard", "Change Keyboard", "Switch Keyboard", "下一个键盘", "切换键盘"]
        let globe = owner.buttons.matching(NSPredicate(format: "label IN[c] %@ OR identifier IN %@",
            globeLabels, ["NextKeyboard", "InputModeSwitchKey"])).firstMatch
        let direct = owner.buttons.matching(NSPredicate(format: "label IN[c] %@ AND value BEGINSWITH[c] 'Clipboard'", globeLabels)).firstMatch
        if direct.exists { direct.tap() }
        else {
            XCTAssertTrue(globe.waitForExistence(timeout: 5), owner.debugDescription)
            globe.press(forDuration: 1.0)
            let menu = owner.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] 'Clipboard' AND elementType != %d",
                XCUIElement.ElementType.navigationBar.rawValue)).allElementsBoundByIndex
            if let choice = menu.last(where: { $0.isHittable }) { choice.tap() }
            else { globe.tap() }
        }
        XCTAssertTrue(waitFor(entry), owner.debugDescription)
        return false
    }

    private func screenshot(_ title: String, in owner: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: owner.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func historyKey(_ label: String, in owner: XCUIApplication, editing: Bool = false) -> XCUIElement {
        owner.buttons.matching(identifier: editing ? "deleteHistoryKey" : "historyKey")
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func tapTrailingEdge(_ key: XCUIElement, in owner: XCUIApplication) {
        XCTAssertGreaterThan(key.frame.width, owner.frame.width * 0.88, owner.debugDescription)
        key.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
    }

    private var visibleAppKeyboard: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "elementType == %d OR identifier IN %@",
            XCUIElement.ElementType.keyboard.rawValue, ["keyboardSpace", "autoSwitch"]
        )).firstMatch
    }

    func testSetupStaysQuietUntilTrialIsRequested() {
        app.launch()
        XCTAssertTrue(app.buttons["tryKeyboard"].waitForExistence(timeout: 8))
        XCTAssertFalse(visibleAppKeyboard.waitForExistence(timeout: 1.5))
        screenshot("ClipboardSetup", in: app)
        app.buttons["tryKeyboard"].tap()
        XCTAssertTrue(app.textViews["trialInput"].waitForExistence(timeout: 8))
        XCTAssertTrue(visibleAppKeyboard.waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["finishTrial"].tap()
        XCTAssertTrue(app.buttons["tryKeyboard"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.textViews["trialInput"].exists)
    }

    func testSystemKeyboardSwitchKeepsFrameSteady() {
        enableKeyboard()
        fixture.launch()
        copyInFixture("second")
        fixture.textViews["input"].tap()
        let short = historyKey("短句", in: fixture)
        selectClipboard(in: fixture, expecting: short)
        fixture.terminate()
        fixture.launchArguments = ["-MeasureKeyboardSwitch"]
        fixture.launch()
        fixture.textViews["input"].tap()
        let englishKey = fixture.keyboards.keys.matching(NSPredicate(format: "label ==[c] 'q'")).firstMatch
        XCTAssertTrue(englishKey.waitForExistence(timeout: 8), fixture.debugDescription)
        fixture.buttons["Track keyboard"].tap()
        selectClipboard(in: fixture, expecting: short)
        let probe = fixture.descendants(matching: .any).matching(identifier: "keyboardTravel").firstMatch
        let samples = (probe.value as? String ?? "").split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(samples.count, 4)
        guard samples.count == 4 else { return }
        XCTAssertGreaterThan(samples[0], 2)
        XCTAssertGreaterThan(samples[1], Double(fixture.frame.height) * 0.4)
        XCTAssertLessThan(samples[1], Double(fixture.frame.height) * 0.92)
        let extraTravel = samples[3] - abs(samples[2] - samples[1])
        XCTContext.runActivity(named: "System to Clipboard: top \(samples[1]) → \(samples[2]) pt; reverse travel \(extraTravel) pt; path \(probe.label)") { _ in }
        XCTAssertGreaterThan(samples[2], Double(fixture.frame.height) * 0.4)
        XCTAssertLessThan(samples[2], Double(fixture.frame.height) * 0.92)
        XCTAssertLessThanOrEqual(extraTravel, 8, "Keyboard layout guide reversed direction during the switch")
    }

    func testKeyboardKeysManagementAndHistoryAcrossHosts() {
        enableKeyboard()
        fixture.launch()
        copyInFixture("second")
        let input = fixture.textViews["input"]
        input.tap()
        let short = historyKey("短句", in: fixture)
        selectClipboard(in: fixture, expecting: short)
        let commandY = fixture.buttons["keyboardSpace"].frame.midY
        let firstKeyY = short.frame.minY
        screenshot("ClipboardShortKey", in: fixture)
        XCTAssertLessThanOrEqual(short.frame.maxY, fixture.buttons["keyboardSpace"].frame.minY, fixture.debugDescription)
        tapTrailingEdge(short, in: fixture)
        XCTAssertEqual(input.value as? String, "短句", fixture.debugDescription)
        fixture.buttons["keyboardSpace"].tap()
        tapTrailingEdge(short, in: fixture)
        fixture.buttons["keyboardBackspace"].tap()
        fixture.buttons["keyboardReturn"].tap()
        XCTAssertEqual(input.value as? String, "短句 短\n", fixture.debugDescription)
        XCTAssertEqual(short.frame.minY, firstKeyY, accuracy: 1)
        XCTAssertEqual(fixture.buttons["keyboardSpace"].frame.midY, commandY, accuracy: 1)
        XCTAssertFalse(fixture.buttons["keyboardSettings"].exists)
        XCTAssertFalse(fixture.switches["autoSwitch"].exists)

        copyInFixture("text")
        XCTAssertTrue(waitFor(historyKey(text, in: fixture)), fixture.debugDescription)
        copyInFixture("image")
        let picture = historyKey("图片", in: fixture)
        XCTAssertTrue(waitFor(picture), fixture.debugDescription)
        screenshot("ClipboardKeyboard", in: fixture)
        tapTrailingEdge(picture, in: fixture)
        fixture.buttons["Check clipboard image"].tap()
        XCTAssertEqual(fixture.staticTexts["copyStatus"].label, "Image still on clipboard")

        app.activate()
        XCTAssertTrue(app.buttons["tryKeyboard"].waitForExistence(timeout: 8))
        XCTAssertFalse(visibleAppKeyboard.waitForExistence(timeout: 1.5))
        app.buttons["tryKeyboard"].tap()
        let trialKey = historyKey("短句", in: app)
        selectClipboard(in: app, expecting: trialKey)
        tapTrailingEdge(trialKey, in: app)
        XCTAssertEqual(app.textViews["trialInput"].value as? String, "短句")
        app.buttons["editHistory"].tap()
        let toDelete = historyKey("短句", in: app, editing: true)
        tapTrailingEdge(toDelete, in: app)
        XCTAssertTrue(toDelete.waitForNonExistence(timeout: 5))
        app.buttons["closeKeyboardPanel"].tap()
        app.buttons["finishTrial"].tap()

        fixture.launchArguments = []
        fixture.launch()
        fixture.textViews["input"].tap()
        selectClipboard(in: fixture, expecting: historyKey("图片", in: fixture))
        XCTAssertFalse(short.exists)
        fixture.buttons["editHistory"].tap()
        fixture.buttons["clearHistory"].tap()
        fixture.buttons["cancelClear"].tap()
        fixture.buttons["closeKeyboardPanel"].tap()
        XCTAssertTrue(picture.exists)
        fixture.buttons["editHistory"].tap()
        fixture.buttons["clearHistory"].tap()
        fixture.buttons["confirmClear"].tap()
        XCTAssertTrue(waitFor(label("暂无历史记录", in: fixture)), fixture.debugDescription)
        XCTAssertFalse(picture.exists)
    }

    func testSettingsFromAppPersistInKeyboard() {
        enableKeyboard()
        app.activate()
        app.buttons["openKeyboardSettings"].tap()
        let toggle = app.switches["autoSwitch"]
        selectClipboard(in: app, expecting: toggle)
        let before = toggle.value as? String
        tapSwitch(toggle)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before ?? ""), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        let after = toggle.value as? String
        XCTAssertNotEqual(before, after)
        app.buttons["7 天"].tap()
        screenshot("ClipboardKeyboardSettings", in: app)
        app.buttons["finishTrial"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tryKeyboard"].waitForExistence(timeout: 6))
        XCTAssertFalse(visibleAppKeyboard.waitForExistence(timeout: 1.5))
        app.buttons["openKeyboardSettings"].tap()
        selectClipboard(in: app, expecting: toggle)
        XCTAssertEqual(toggle.value as? String, after)
        XCTAssertTrue(app.buttons["7 天"].isSelected)
        app.buttons["finishTrial"].tap()
    }
}
