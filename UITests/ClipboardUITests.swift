import XCTest

@MainActor
final class ClipboardUITests: XCTestCase {
    private static var configuredKeyboard = false
    private let app = XCUIApplication()
    private let fixture = XCUIApplication(bundleIdentifier: "net.chkf.ClipboardTestHost")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let text = "Clipboard UI fixture\nsecond line\nthird line"

    override func setUp() {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Allow inter-app paste") { alert in
            let permission = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Allow Paste", "允许粘贴"])).firstMatch
            guard permission.exists else { return false }
            permission.tap()
            return true
        }
    }

    private func allowPasteIfRequested() -> Bool {
        let label = NSPredicate(format: "label IN %@", ["Allow Paste", "允许粘贴"])
        for owner in [springboard, fixture, app] where owner == springboard || owner.state == .runningForeground {
            let allow = owner.alerts.buttons.matching(label).firstMatch
            if allow.exists { allow.tap(); return true }
        }
        return false
    }

    private func waitFor(_ element: XCUIElement, seconds: Double = 15) -> Bool {
        waitForAny([element], seconds: seconds)
    }

    private func waitForAny(_ elements: [XCUIElement], seconds: Double) -> Bool {
        var end = Date().addingTimeInterval(seconds)
        var granted = false
        repeat {
            if allowPasteIfRequested(), !granted {
                end = Date().addingTimeInterval(seconds)
                granted = true
            }
            if elements.contains(where: { $0.exists }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
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

    private func confirmFullAccess(in settings: XCUIApplication) -> Bool {
        let allow = NSPredicate(format: "label IN[c] %@", ["Allow", "允许"])
        let fullAccess = NSPredicate(format: "label IN[c] %@", ["Allow Full Access", "允许完全访问"])
        for owner in [settings, springboard] {
            let button = owner.buttons.matching(allow).firstMatch
            if button.exists && button.isHittable { button.tap(); return true }
            let dialog = owner.alerts.firstMatch.exists ? owner.alerts.firstMatch : owner.sheets.firstMatch
            let grant = dialog.buttons.matching(fullAccess).firstMatch
            if grant.exists && grant.isHittable { grant.tap(); return true }
        }
        return false
    }

    private func copyInFixture(_ type: String) {
        XCTAssertTrue(fixture.wait(for: .runningForeground, timeout: 8))
        let button = fixture.buttons["Copy " + type]
        let expected = type.capitalized + " copied"
        XCTAssertTrue(button.waitForExistence(timeout: 8), fixture.debugDescription)
        button.tap()
        let status = fixture.staticTexts.matching(identifier: "copyStatus").matching(NSPredicate(format: "label == %@", expected)).firstMatch
        XCTAssertTrue(waitFor(status, seconds: 12), fixture.debugDescription)
    }

    private func enableKeyboard() {
        app.launch()
        if Self.configuredKeyboard { return }
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
        for _ in 0..<3 where fullAccess.value as? String != "1" {
            if !confirmFullAccess(in: settings) {
                let control = fullAccess.switches.firstMatch
                if control.exists && control.isHittable { control.tap() }
                else { tapSwitch(fullAccess) }
            }
            let deadline = Date().addingTimeInterval(10)
            repeat {
                if confirmFullAccess(in: settings) { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            } while Date() < deadline
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: fullAccess)
            if XCTWaiter.wait(for: [enabled], timeout: 5) == .completed { break }
        }
        XCTAssertEqual(fullAccess.value as? String, "1", settings.debugDescription)
        Self.configuredKeyboard = true
    }

    private func systemSwitchKey(in owner: XCUIApplication) -> XCUIElement {
        let globeLabels = ["Next keyboard", "Show next keyboard", "Change Keyboard", "Switch Keyboard", "下一个键盘", "切换键盘"]
        return owner.buttons.matching(NSPredicate(format: "label IN[c] %@ OR identifier IN %@",
            globeLabels, ["NextKeyboard", "InputModeSwitchKey"])).firstMatch
    }

    @discardableResult
    private func selectClipboard(in owner: XCUIApplication, expecting entry: XCUIElement) -> Bool {
        if waitFor(entry, seconds: 3) { return true }
        let globe = systemSwitchKey(in: owner)
        let surface = owner.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["expandCategories", "autoSwitch"])).firstMatch
        let controls = [surface, globe]
        func focusFixtureField() {
            let search = fixture.descendants(matching: .any).matching(identifier: "searchInput").firstMatch
            let field = search.exists ? search : fixture.textViews["input"]
            if waitFor(field, seconds: 8) { field.tap() }
        }
        if owner == fixture, !waitForAny(controls, seconds: 3) { focusFixtureField() }
        var reopened = false
        for attempt in 0..<2 where !surface.exists && !entry.exists {
            if !waitForAny(controls, seconds: 8) {
                // iOS can dismiss the editing session during the first globe handoff or paste alert.
                guard owner == fixture, !reopened, !fixture.launchArguments.contains("-MeasureKeyboardSwitch") else { break }
                reopened = true
                fixture.launch()
                focusFixtureField()
                guard waitForAny(controls, seconds: 10) else { break }
            }
            if surface.exists || entry.exists { break }
            guard globe.waitForExistence(timeout: 2) else { continue }
            if attempt == 0 {
                globe.tap()
            } else {
                globe.press(forDuration: 1.1)
                let option = NSPredicate(format: "label CONTAINS[c] 'Clipboard' AND NOT (identifier IN %@)",
                                         ["NextKeyboard", "InputModeSwitchKey"])
                for host in [owner, springboard] {
                    let choices = host.descendants(matching: .any).matching(option).allElementsBoundByIndex
                    if let choice = choices.first(where: { $0.isHittable && $0.frame.midY > owner.frame.midY && $0.frame.height < 100 }) {
                        choice.tap()
                        break
                    }
                }
            }
            if waitFor(surface, seconds: 10) || entry.exists { break }
        }
        let found = waitFor(entry)
        XCTAssertTrue(found, owner.debugDescription)
        return found
    }

    @discardableResult
    private func screenshot(_ title: String, in owner: XCUIApplication) -> XCUIScreenshot {
        // The paste alert lives in SpringBoard and dims the keyboard before the host's
        // accessibility hierarchy reports any change. Check on both sides of the capture.
        let deadline = Date().addingTimeInterval(15)
        var clearSince = Date()
        var shot: XCUIScreenshot?
        repeat {
            if allowPasteIfRequested() {
                clearSince = Date()
            } else if Date().timeIntervalSince(clearSince) >= 1.2 {
                let candidate = owner.screenshot()
                if !allowPasteIfRequested() { shot = candidate; break }
                clearSince = Date()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        XCTAssertNotNil(shot, "The paste permission alert kept covering the keyboard")
        let frame = shot ?? owner.screenshot()
        let attachment = XCTAttachment(screenshot: frame)
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
        return frame
    }

    private func historyKey(_ label: String, in owner: XCUIApplication, editing: Bool = false) -> XCUIElement {
        owner.buttons.matching(identifier: editing ? "deleteHistoryKey" : "historyKey")
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func tapTrailingEdge(_ key: XCUIElement, in owner: XCUIApplication) {
        XCTAssertGreaterThan(key.frame.width, owner.frame.width * 0.77, owner.debugDescription)
        key.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
    }

    private func nativeTop(for control: XCUIElement, in owner: XCUIApplication) -> CGFloat? {
        guard control.frame.midY < owner.frame.midY else { return nil }
        let target = control.identifier.isEmpty ? control.label : control.identifier
        let containers = owner.otherElements.containing(.button, identifier: target).allElementsBoundByIndex
        let screen: CGRect = owner.frame
        var panel: CGRect?
        for container in containers {
            let frame: CGRect = container.frame
            guard frame.minY > screen.midY, abs(frame.width - screen.width) < 3,
                  frame.maxY < screen.maxY - 10, frame.height > 140 else { continue }
            if frame.height < (panel?.height ?? CGFloat.greatestFiniteMagnitude) { panel = frame }
        }
        return panel?.minY
    }

    private func keyboardCoordinate(for control: XCUIElement, in owner: XCUIApplication) -> XCUICoordinate? {
        guard control.waitForExistence(timeout: 6) else { XCTFail(owner.debugDescription); return nil }
        var box = control.frame
        if box.midY < owner.frame.midY {
            guard let top = nativeTop(for: control, in: owner) else { XCTFail(owner.debugDescription); return nil }
            box.origin.y += top
        }
        return owner.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: box.midX - owner.frame.minX, dy: box.midY - owner.frame.minY))
    }

    private func tapKeyboard(_ control: XCUIElement, in owner: XCUIApplication) {
        keyboardCoordinate(for: control, in: owner)?.tap()
    }

    private func attachGeometry(_ name: String, in owner: XCUIApplication, fields: [String: CGRect], panelTop: CGFloat? = nil) {
        let origin = owner.frame.origin
        func numbers(_ r: CGRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
        var values = ["screen": numbers(owner.frame)]
        for (key, frame) in fields {
            var rect = frame.offsetBy(dx: -origin.x, dy: -origin.y)
            if let panelTop, rect.midY < owner.frame.height / 2 { rect.origin.y += panelTop }
            values[key] = numbers(rect)
        }
        let data = try! JSONEncoder().encode(values)
        let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openActions(in owner: XCUIApplication, category: String = "ordinary") {
        let tab = owner.buttons["tab-" + category]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), owner.debugDescription)
        // The remote input view may report extension-local coordinates after a host change.
        keyboardCoordinate(for: tab, in: owner)?.press(forDuration: 0.75)
        XCTAssertTrue(owner.buttons["cancelActions"].waitForExistence(timeout: 5), owner.debugDescription)
    }

    private var visibleAppKeyboard: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "elementType == %d OR identifier IN %@",
            XCUIElement.ElementType.keyboard.rawValue, ["expandCategories", "autoSwitch"]
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

    func testSystemKeyboardSwitchKeepsFrameSteady() async throws {
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
        XCTAssertEqual(samples[1], samples[2], accuracy: 8, "The settled keyboard changed the host's input area")
        try await Task.sleep(for: .seconds(1))
        screenshot("ClipboardMotionReference", in: fixture)
        attachGeometry("ClipboardMotionGeometry", in: fixture, fields: [
            "category": fixture.buttons["tab-ordinary"].frame, "arrow": fixture.buttons["expandCategories"].frame,
            "row": short.frame
        ], panelTop: CGFloat(samples[2]))
        fixture.buttons["Finish measurement"].tap()
    }

    func testHistoryManagementAndFullWidthRowsAcrossHosts() throws {
        enableKeyboard()
        fixture.launch()
        let input = fixture.textViews["input"]
        input.tap()
        selectClipboard(in: fixture, expecting: fixture.buttons["expandCategories"])
        copyInFixture("second")
        let short = historyKey("短句", in: fixture)
        XCTAssertTrue(waitFor(short), fixture.debugDescription)
        let arrowFrame = fixture.buttons["expandCategories"].frame
        let firstKeyY = short.frame.minY
        screenshot("ClipboardShortKey", in: fixture)
        XCTAssertGreaterThan(short.frame.width, fixture.frame.width * 0.94)
        tapTrailingEdge(short, in: fixture)
        tapTrailingEdge(short, in: fixture)
        XCTAssertEqual(input.value as? String, "短句短句", fixture.debugDescription)
        XCTAssertEqual(short.frame.minY, firstKeyY, accuracy: 1)
        XCTAssertEqual(fixture.buttons["expandCategories"].frame, arrowFrame)
        for id in ["keyboardSpace","keyboardReturn","keyboardBackspace","clearHistory","undoHistory","nextKeyboard"] {
            XCTAssertFalse(fixture.buttons[id].exists, id)
        }
        XCTAssertFalse(fixture.buttons["keyboardSettings"].exists)
        XCTAssertFalse(fixture.switches["autoSwitch"].exists)

        copyInFixture("text")
        XCTAssertTrue(waitFor(historyKey(text, in: fixture)), fixture.debugDescription)
        copyInFixture("image")
        let picture = historyKey("图片", in: fixture)
        XCTAssertTrue(waitFor(picture, seconds: 30), fixture.debugDescription)
        screenshot("ClipboardKeyboard", in: fixture)
        for row in [picture, historyKey(text, in: fixture), short] {
            XCTAssertGreaterThan(row.frame.width, fixture.frame.width * 0.94)
            XCTAssertGreaterThanOrEqual(row.frame.height, 43)
        }
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
        if trialKey.value as? String == "已置顶" {
            trialKey.swipeRight()
            if app.buttons["取消置顶"].waitForExistence(timeout: 1) { tapKeyboard(app.buttons["取消置顶"], in: app) }
            let unpinned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "已置顶"), object: trialKey)
            XCTAssertEqual(XCTWaiter.wait(for: [unpinned], timeout: 5), .completed)
        }
        trialKey.swipeRight()
        if app.buttons["置顶"].waitForExistence(timeout: 1) { tapKeyboard(app.buttons["置顶"], in: app) }
        let pinned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "已置顶"), object: trialKey)
        XCTAssertEqual(XCTWaiter.wait(for: [pinned], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["nextKeyboard"].exists)
        XCTAssertFalse(app.buttons["showNumbers"].exists)
        XCTAssertFalse(app.buttons["showEmoji"].exists)
        let expand = app.buttons["expandCategories"]
        let arrow = expand.frame
        tapKeyboard(expand, in: app)
        XCTAssertTrue(app.buttons["folder-work"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(expand.frame, arrow)
        XCTAssertFalse(app.buttons["tab-work"].exists)
        screenshot("ClipboardExpandedCategories", in: app)
        tapKeyboard(app.buttons["folder-ordinary"], in: app)
        XCTAssertTrue(trialKey.waitForExistence(timeout: 5))
        trialKey.swipeLeft()
        tapKeyboard(app.buttons["归类"], in: app)
        tapKeyboard(app.buttons["folder-work"], in: app)
        XCTAssertTrue(trialKey.waitForNonExistence(timeout: 5))
        tapKeyboard(app.buttons["tab-work"], in: app)
        XCTAssertTrue(trialKey.waitForExistence(timeout: 5))
        trialKey.swipeLeft()
        tapKeyboard(app.buttons["删除"], in: app)
        XCTAssertTrue(trialKey.waitForNonExistence(timeout: 5))
        openActions(in: app, category: "work")
        tapKeyboard(app.buttons["undoHistory"], in: app)
        XCTAssertTrue(trialKey.waitForExistence(timeout: 5))
        openActions(in: app, category: "work")
        tapKeyboard(app.buttons["undoHistory"], in: app)
        tapKeyboard(app.buttons["tab-ordinary"], in: app)
        XCTAssertTrue(trialKey.waitForExistence(timeout: 5))
        trialKey.swipeLeft()
        tapKeyboard(app.buttons["删除"], in: app)
        XCTAssertTrue(trialKey.waitForNonExistence(timeout: 5))
        app.buttons["finishTrial"].tap()

        fixture.launchArguments = []
        fixture.launch()
        fixture.textViews["input"].tap()
        selectClipboard(in: fixture, expecting: historyKey("图片", in: fixture))
        openActions(in: fixture)
        XCTAssertFalse(fixture.buttons["undoHistory"].isEnabled)
        tapKeyboard(fixture.buttons["cancelActions"], in: fixture)
        XCTAssertFalse(short.exists)
        tapTrailingEdge(historyKey(text, in: fixture), in: fixture)
        let typed = try XCTUnwrap(input.value as? String)
        XCTAssertTrue(typed.hasSuffix(text))
        openActions(in: fixture)
        tapKeyboard(fixture.buttons["clearHistory"], in: fixture)
        tapKeyboard(fixture.buttons["cancelClear"], in: fixture)
        XCTAssertTrue(picture.exists)
        openActions(in: fixture)
        tapKeyboard(fixture.buttons["clearHistory"], in: fixture)
        tapKeyboard(fixture.buttons["confirmClear"], in: fixture)
        XCTAssertTrue(picture.waitForNonExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, typed)
        openActions(in: fixture)
        tapKeyboard(fixture.buttons["undoHistory"], in: fixture)
        XCTAssertTrue(picture.waitForExistence(timeout: 5))
        XCTAssertTrue(historyKey(text, in: fixture).exists)
        openActions(in: fixture)
        XCTAssertFalse(fixture.buttons["undoHistory"].isEnabled)
        tapKeyboard(fixture.buttons["clearHistory"], in: fixture)
        tapKeyboard(fixture.buttons["confirmClear"], in: fixture)
        XCTAssertTrue(waitFor(label("暂无历史记录", in: fixture)), fixture.debugDescription)
        XCTAssertFalse(picture.exists)
    }

    func testSettingsFromAppPersistInKeyboard() {
        enableKeyboard()
        app.activate()
        app.buttons["openKeyboardSettings"].tap()
        let toggle = app.switches["autoSwitch"]
        selectClipboard(in: app, expecting: toggle)
        XCTAssertTrue(toggle.wait(for: \.isEnabled, toEqual: true, timeout: 10))
        let before = toggle.value as? String
        tapSwitch(toggle)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before ?? ""), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        let after = toggle.value as? String
        XCTAssertNotEqual(before, after)
        let haptics = app.switches["keyboardHaptics"]
        let originalHaptics = haptics.value as? String
        tapSwitch(haptics)
        let hapticsChanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", originalHaptics ?? ""), object: haptics)
        XCTAssertEqual(XCTWaiter.wait(for: [hapticsChanged], timeout: 5), .completed)
        let savedHaptics = haptics.value as? String
        app.buttons["7 天"].tap()
        XCTAssertTrue(app.buttons["7 天"].wait(for: \.isSelected, toEqual: true, timeout: 5))
        app.buttons["3 天"].tap()
        screenshot("ClipboardKeyboardSettings", in: app)
        app.buttons["finishTrial"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tryKeyboard"].waitForExistence(timeout: 6))
        XCTAssertFalse(visibleAppKeyboard.waitForExistence(timeout: 1.5))
        app.buttons["openKeyboardSettings"].tap()
        selectClipboard(in: app, expecting: toggle)
        XCTAssertEqual(toggle.value as? String, after)
        XCTAssertEqual(haptics.value as? String, savedHaptics)
        tapSwitch(haptics)
        XCTAssertTrue(app.buttons["3 天"].isSelected)
        app.buttons["finishTrial"].tap()
    }

    func testManageCategoryFromContainingApp() {
        enableKeyboard()
        app.activate()
        app.buttons["manageCategories"].tap()
        app.buttons["addCategory"].tap()
        let name = "Weekend travel plans and reading suggestions " + String(UUID().uuidString.prefix(5))
        let field = app.textFields["categoryName"]
        field.tap(); field.typeText(name)
        app.buttons["saveCategory"].tap()
        let created = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        let transfer = app.navigationBars["保存到键盘"]
        XCTAssertTrue(waitForAny([created, transfer], seconds: 12), app.debugDescription)
        if transfer.waitForExistence(timeout: 4) {
            let apply = app.buttons["applyCategoryChange"]
            selectClipboard(in: app, expecting: apply)
            XCTAssertTrue(apply.wait(for: \.isEnabled, toEqual: true, timeout: 10))
            apply.tap()
        }
        XCTAssertTrue(created.waitForExistence(timeout: 8), app.debugDescription)
        fixture.launch()
        fixture.textViews["input"].tap()
        selectClipboard(in: fixture, expecting: fixture.buttons["expandCategories"])
        let arrow = fixture.buttons["expandCategories"]
        let collapsedFrame = arrow.frame
        tapKeyboard(arrow, in: fixture)
        let choices = fixture.buttons.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH 'folder-'", name))
        let choice = choices.firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 8), fixture.debugDescription)
        XCTAssertEqual(choices.count, 1)
        XCTAssertGreaterThan(choice.frame.midY, fixture.buttons["folder-ordinary"].frame.midY + 20)
        XCTAssertEqual(arrow.frame, collapsedFrame)
        screenshot("ClipboardWrappedCategories", in: fixture)
        tapKeyboard(choice, in: fixture)
        let tab = fixture.buttons.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH 'tab-'", name)).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 8), fixture.debugDescription)
        XCTAssertTrue(tab.isSelected)
        XCTAssertTrue(choice.waitForNonExistence(timeout: 5))
        XCTAssertEqual(arrow.frame, collapsedFrame)
    }

    func testGlobeHandsTheActiveFieldBackToAnInstalledKeyboard() {
        enableKeyboard()
        fixture.launchArguments = ["-NaturalKeyboard"]
        fixture.launch()
        let input = fixture.textViews["input"]
        XCTAssertTrue(waitFor(input), fixture.debugDescription)
        input.tap()
        let categories = fixture.buttons["expandCategories"]
        selectClipboard(in: fixture, expecting: categories)
        let chineseInput = fixture.textViews.matching(identifier: "input")
            .matching(NSPredicate(format: "label BEGINSWITH[c] 'zh'")).firstMatch
        XCTAssertTrue(chineseInput.waitForExistence(timeout: 8), fixture.debugDescription)
        let switcher = systemSwitchKey(in: fixture)
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), fixture.debugDescription)
        switcher.tap()
        XCTAssertTrue(categories.waitForNonExistence(timeout: 8), fixture.debugDescription)
        let native = fixture.keyboards.firstMatch
        XCTAssertTrue(native.waitForExistence(timeout: 8), fixture.debugDescription)
        // A fresh iOS installation overlays the keyboard with Apple's QuickPath introduction.
        let introduction = fixture.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Speed up your typing by sliding")).firstMatch
        if introduction.waitForExistence(timeout: 4) {
            fixture.buttons["Continue"].tap()
            XCTAssertTrue(introduction.waitForNonExistence(timeout: 8), fixture.debugDescription)
        }
        if native.keys.matching(NSPredicate(format: "label ==[c] 'q'")).firstMatch.exists {
            let numbers = native.descendants(matching: .any).matching(NSPredicate(
                format: "label IN[c] %@ OR identifier IN[c] %@", ["more","numbers","123","数字"], ["more","123"])).firstMatch
            XCTAssertTrue(numbers.exists, native.debugDescription)
            let one = native.keys["1"]
            numbers.tap()
            XCTAssertTrue(one.waitForExistence(timeout: 8), native.debugDescription)
            one.tap()
            XCTAssertEqual(input.value as? String, "1", fixture.debugDescription)
            screenshot("InstalledSystemKeyboard", in: fixture)
            let emoji = native.buttons.matching(NSPredicate(format: "identifier == 'emoji' OR label IN[c] %@", ["Emoji","表情符号"])).firstMatch
            XCTAssertTrue(emoji.waitForExistence(timeout: 5), native.debugDescription)
            emoji.tap()
        }
        let emojiMode = fixture.textViews.matching(identifier: "input").matching(NSPredicate(format: "label ==[c] 'emoji'")).firstMatch
        let emojiSearch = fixture.descendants(matching: .any).matching(NSPredicate(
            format: "label IN[c] %@ OR placeholderValue IN[c] %@", ["Search Emoji","搜索表情符号"], ["Search Emoji","搜索表情符号"])).firstMatch
        XCTAssertTrue(waitForAny([emojiMode, emojiSearch], seconds: 8), fixture.debugDescription)
        screenshot("InstalledEmojiKeyboard", in: fixture)
        let globe = systemSwitchKey(in: fixture)
        XCTAssertTrue(globe.waitForExistence(timeout: 5), fixture.debugDescription)
        globe.press(forDuration: 1.0)
        let menu = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        menu.name = "ClipboardLanguageMenu"
        menu.lifetime = .keepAlways
        add(menu)
    }

    func testHistoryInSearchFieldUsesTheNativeKeyboardFootprint() {
        enableKeyboard()
        let field = fixture.descendants(matching: .any).matching(identifier: "searchInput").firstMatch
        fixture.launchArguments = ["-EmptySearch", "-SystemKeyboard"]
        fixture.launch()
        field.tap()
        let native = fixture.keyboards.firstMatch
        XCTAssertTrue(native.keys.matching(NSPredicate(format: "label ==[c] 'q'")).firstMatch.waitForExistence(timeout: 8))
        screenshot("NativeEmptySearch", in: fixture)
        fixture.launchArguments = ["-EmptySearch"]
        fixture.launch()
        field.tap()
        let expand = fixture.buttons["expandCategories"]
        selectClipboard(in: fixture, expecting: expand)
        for (item, name) in [("image", "图片"), ("text", text), ("second", "短句")] {
            copyInFixture(item)
            XCTAssertTrue(waitFor(historyKey(name, in: fixture), seconds: 30))
        }
        let ordinary = fixture.buttons["tab-ordinary"]
        let row = historyKey("短句", in: fixture)
        XCTAssertFalse(fixture.buttons["keyboardReturn"].exists)
        screenshot("ClipboardEmptySearch", in: fixture)
        let top = nativeTop(for: expand, in: fixture)
        attachGeometry("ClipboardSurfaceGeometry", in: fixture, fields: [
            "category": ordinary.frame, "arrow": expand.frame, "row": row.frame
        ], panelTop: top)
        row.tap()
        XCTAssertEqual(field.value as? String, "短句")
    }
}
