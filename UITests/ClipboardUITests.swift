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

    @discardableResult
    private func selectClipboard(in owner: XCUIApplication, expecting entry: XCUIElement) -> Bool {
        if waitFor(entry, seconds: 3) { return true }
        let globeLabels = ["Next keyboard", "Show next keyboard", "Change Keyboard", "Switch Keyboard", "下一个键盘", "切换键盘"]
        let globe = owner.buttons.matching(NSPredicate(format: "label IN[c] %@ OR identifier IN %@",
            globeLabels, ["NextKeyboard", "InputModeSwitchKey"])).firstMatch
        let surface = owner.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["keyboardSpace", "autoSwitch"])).firstMatch
        let controls = [surface, globe]
        func focusFixtureField() {
            let search = fixture.descendants(matching: .any).matching(identifier: "searchInput").firstMatch
            if search.exists { search.tap() } else { fixture.textViews["input"].tap() }
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
        // Keep the switch marked while the input mode name fades off the space bar.
        try await Task.sleep(for: .seconds(2))
        fixture.buttons["Finish measurement"].tap()
    }

    func testKeyboardKeysManagementAndHistoryAcrossHosts() throws {
        enableKeyboard()
        fixture.launch()
        let input = fixture.textViews["input"]
        input.tap()
        selectClipboard(in: fixture, expecting: fixture.buttons["keyboardSpace"])
        copyInFixture("second")
        let short = historyKey("短句", in: fixture)
        XCTAssertTrue(waitFor(short), fixture.debugDescription)
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
        XCTAssertTrue(waitFor(picture, seconds: 30), fixture.debugDescription)
        let historyFrame = screenshot("ClipboardKeyboard", in: fixture)
        let screen = try XCTUnwrap(KeyboardScreen(historyFrame, screen: fixture.frame))
        let footer = fixture.buttons["keyboardSpace"].frame
        let commands = ["clearHistory", "undoHistory", "keyboardBackspace"]
        for (record, id) in zip([picture, historyKey(text, in: fixture), short], commands) {
            let face = fixture.buttons[id].frame
            let paintedRow = try XCTUnwrap(screen.verticalFace(at: CGPoint(x: record.frame.maxX - 14, y: face.midY)), id)
            XCTAssertEqual(face.minY, record.frame.minY, accuracy: 1.5, id)
            XCTAssertEqual(face.minY, paintedRow.lowerBound, accuracy: 1.5, id)
            XCTAssertEqual(face.maxY, paintedRow.upperBound, accuracy: 1.5, id)
            XCTAssertEqual(face.height, footer.height, accuracy: 1.5, id)
            XCTAssertLessThan(face.maxY, footer.minY, id)
            XCTAssertLessThanOrEqual(face.maxX, fixture.frame.maxX, id)
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
        trialKey.swipeRight()
        if app.buttons["置顶"].waitForExistence(timeout: 1) { app.buttons["置顶"].tap() }
        let pinned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "已置顶"), object: trialKey)
        XCTAssertEqual(XCTWaiter.wait(for: [pinned], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["nextKeyboard"].exists)
        XCTAssertFalse(app.buttons["showNumbers"].exists)
        XCTAssertFalse(app.buttons["showEmoji"].exists)
        let expand = app.buttons["expandCategories"]
        let arrow = expand.frame
        expand.tap()
        XCTAssertTrue(app.buttons["folder-work"].waitForExistence(timeout: 5))
        XCTAssertEqual(expand.frame, arrow)
        expand.tap()
        trialKey.swipeLeft()
        app.buttons["归类"].tap()
        app.buttons["folder-work"].tap()
        XCTAssertTrue(trialKey.waitForNonExistence(timeout: 5))
        app.buttons["tab-work"].tap()
        XCTAssertTrue(trialKey.waitForExistence(timeout: 5))
        trialKey.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertTrue(trialKey.waitForNonExistence(timeout: 5))
        app.buttons["undoHistory"].tap()
        XCTAssertTrue(trialKey.waitForExistence(timeout: 5))
        app.buttons["undoHistory"].tap()
        app.buttons["tab-ordinary"].tap()
        XCTAssertTrue(trialKey.waitForExistence(timeout: 5))
        trialKey.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertTrue(trialKey.waitForNonExistence(timeout: 5))
        app.buttons["finishTrial"].tap()

        fixture.launchArguments = []
        fixture.launch()
        fixture.textViews["input"].tap()
        selectClipboard(in: fixture, expecting: historyKey("图片", in: fixture))
        XCTAssertFalse(fixture.buttons["undoHistory"].isEnabled)
        XCTAssertFalse(short.exists)
        fixture.buttons["keyboardBackspace"].press(forDuration: 0.75)
        fixture.buttons["cancelClear"].tap()
        XCTAssertTrue(picture.exists)
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
        let haptics = app.switches["keyboardHaptics"]
        let originalHaptics = haptics.value as? String
        tapSwitch(haptics)
        let hapticsChanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", originalHaptics ?? ""), object: haptics)
        XCTAssertEqual(XCTWaiter.wait(for: [hapticsChanged], timeout: 5), .completed)
        let savedHaptics = haptics.value as? String
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
        XCTAssertEqual(haptics.value as? String, savedHaptics)
        tapSwitch(haptics)
        XCTAssertTrue(app.buttons["7 天"].isSelected)
        app.buttons["finishTrial"].tap()
    }

    func testManageCategoryFromContainingApp() {
        enableKeyboard()
        app.activate()
        app.buttons["manageCategories"].tap()
        app.buttons["addCategory"].tap()
        let name = "Trip-" + String(UUID().uuidString.prefix(5))
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
        selectClipboard(in: fixture, expecting: fixture.buttons["keyboardSpace"])
        fixture.buttons["expandCategories"].tap()
        XCTAssertTrue(fixture.buttons.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH 'folder-'", name)).firstMatch.waitForExistence(timeout: 8))
    }

    func testHoldSpaceMovesHostCursorWithoutInsertingSpace() {
        enableKeyboard()
        fixture.launchArguments = ["-ReturnKey", "Return"]
        fixture.launch()
        let input = fixture.textViews["input"]
        input.tap()
        selectClipboard(in: fixture, expecting: fixture.buttons["keyboardSpace"])
        copyInFixture("second")
        let clip = historyKey("短句", in: fixture)
        XCTAssertTrue(waitFor(clip)); clip.tap()
        let before = input.value as? String
        let space = fixture.buttons["keyboardSpace"]
        let start = space.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        start.press(forDuration: 0.7, thenDragTo: start.withOffset(CGVector(dx: -32, dy: 0)))
        XCTAssertEqual(input.value as? String, before)
        clip.tap()
        let after = input.value as? String
        XCTAssertNotEqual(after, (before ?? "") + "短句")
        XCTAssertEqual(after?.count, (before?.count ?? 0) + 2)
    }

    func testReturnKeysMatchTheActiveSystemField() throws {
        enableKeyboard()
        for (name, translated) in [("Return", "换行"), ("Search", "搜索"), ("Send", "发送"), ("Done", "完成")] {
            fixture.launchArguments = ["-ReturnKey", name, "-SystemKeyboard"]
            fixture.launch()
            fixture.textViews["input"].tap()
            let keyboard = fixture.keyboards.firstMatch
            XCTAssertTrue(keyboard.keys.matching(NSPredicate(format: "label ==[c] 'q'")).firstMatch.waitForExistence(timeout: 8))
            let nativeKey = try nativeReturn(name, translated, in: keyboard)
            let nativeFrame = screenshot("NativeReturn" + name, in: fixture)
            let nativeScreen = try XCTUnwrap(KeyboardScreen(nativeFrame, screen: fixture.frame))
            let nativeColor = nativeScreen.keycapColor(in: nativeKey.frame.insetBy(dx: 3, dy: 3))

            fixture.launchArguments = ["-ReturnKey", name]
            fixture.launch()
            fixture.textViews["input"].tap()
            let custom = fixture.buttons["keyboardReturn"]
            selectClipboard(in: fixture, expecting: custom)
            XCTAssertEqual(custom.label, translated)
            let customFrame = screenshot("ClipboardReturn" + name, in: fixture)
            let customScreen = try XCTUnwrap(KeyboardScreen(customFrame, screen: fixture.frame))
            let customColor = customScreen.keycapColor(in: custom.frame.insetBy(dx: 3, dy: 3))
            XCTAssertEqual(nativeColor.count, 3)
            XCTAssertEqual(customColor.count, 3)
            XCTAssertTrue(zip(nativeColor, customColor).allSatisfy { abs($0.0 - $0.1) <= 5 },
                          "\(name): system RGB \(nativeColor), Clipboard RGB \(customColor)")
            custom.tap()
            let result = try XCTUnwrap(fixture.textViews["input"].value as? String)
            XCTAssertEqual(result.filter(\.isNewline).count, 1)
            XCTAssertEqual(result.filter { !$0.isNewline }, "sample")
        }
    }

    private func nativeReturn(_ name: String, _ translated: String, in keyboard: XCUIElement) throws -> XCUIElement {
        let native = keyboard.descendants(matching: .any).matching(NSPredicate(
            format: "label IN[c] %@ OR identifier IN[c] %@", [name, translated], ["Return", name, translated])).firstMatch
        return try XCTUnwrap(native.exists ? native : keyboard.keys.allElementsBoundByIndex.filter {
            $0.frame.midX > fixture.frame.width * 0.80 && $0.frame.width > 55
        }.max(by: { $0.frame.midY < $1.frame.midY }))
    }

    func testSearchFieldMatchesNativeWhileEmpty() {
        enableKeyboard()
        let field = fixture.descendants(matching: .any).matching(identifier: "searchInput").firstMatch
        fixture.launchArguments = ["-EmptySearch", "-SystemKeyboard"]
        fixture.launch()
        field.tap()
        let keyboard = fixture.keyboards.firstMatch
        XCTAssertTrue(keyboard.keys.matching(NSPredicate(format: "label ==[c] 'q'")).firstMatch.waitForExistence(timeout: 8))
        screenshot("NativeEmptySearch", in: fixture)
        fixture.launchArguments = ["-EmptySearch"]
        fixture.launch()
        field.tap()
        let custom = fixture.buttons["keyboardReturn"]
        selectClipboard(in: fixture, expecting: custom)
        for (item, name) in [("image", "图片"), ("text", text), ("second", "短句")] {
            copyInFixture(item)
            XCTAssertTrue(waitFor(historyKey(name, in: fixture), seconds: 30))
        }
        XCTAssertFalse(custom.isEnabled)
        screenshot("ClipboardEmptySearch", in: fixture)
        historyKey("短句", in: fixture).tap()
        XCTAssertEqual(field.value as? String, "短句")
        XCTAssertTrue(custom.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        fixture.buttons["keyboardBackspace"].tap()
        fixture.buttons["keyboardBackspace"].tap()
        XCTAssertTrue(custom.wait(for: \.isEnabled, toEqual: false, timeout: 5))
    }
}
