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
        let surface = owner.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["keyboardSpace", "autoSwitch", "receiveCollectedCopies"])).firstMatch
        for _ in 0..<4 {
            if surface.exists || entry.exists { break }
            XCTAssertTrue(globe.waitForExistence(timeout: 5), owner.debugDescription)
            globe.tap()
            if surface.waitForExistence(timeout: 3) || entry.exists { break }
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
        XCTAssertEqual(samples[1], samples[2], accuracy: 8, "The settled keyboard changed the host's input area")
        fixture.buttons["Finish measurement"].tap()
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
        trialKey.swipeRight()
        app.buttons["置顶"].tap()
        XCTAssertEqual(trialKey.value as? String, "已置顶")
        app.buttons["openSearch"].tap()
        app.buttons["key-d"].tap()
        app.buttons["key-j"].tap()
        app.buttons["keyboardReturn"].tap()
        XCTAssertTrue(trialKey.waitForExistence(timeout: 5))
        XCTAssertFalse(historyKey("图片", in: app).exists)
        app.buttons["显示全部"].tap()
        app.buttons["showNumbers"].tap()
        app.buttons["key-8"].tap()
        app.buttons["numbersBack"].tap()
        app.buttons["showEmoji"].tap()
        app.buttons["emoji-😀"].tap()
        app.buttons["emojiBack"].tap()
        XCTAssertEqual(app.textViews["trialInput"].value as? String, "短句8😀")
        trialKey.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertTrue(trialKey.waitForNonExistence(timeout: 5))
        app.buttons["finishTrial"].tap()

        fixture.launchArguments = []
        fixture.launch()
        fixture.textViews["input"].tap()
        selectClipboard(in: fixture, expecting: historyKey("图片", in: fixture))
        XCTAssertFalse(short.exists)
        fixture.buttons["clearHistory"].tap()
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

    func testReturnKeysMatchTheActiveSystemField() throws {
        continueAfterFailure = true
        enableKeyboard()
        for (name, translated) in [("Return", "换行"), ("Search", "搜索"), ("Send", "发送"), ("Done", "完成")] {
            fixture.launchArguments = ["-ReturnKey", name]
            fixture.launch()
            fixture.textViews["input"].tap()
            let keyboard = fixture.keyboards.firstMatch
            XCTAssertTrue(keyboard.keys.matching(NSPredicate(format: "label ==[c] 'q'")).firstMatch.waitForExistence(timeout: 8))
            let native = keyboard.descendants(matching: .any).matching(NSPredicate(
                format: "label IN[c] %@ OR identifier IN[c] %@", [name, translated], [name, translated])).firstMatch
            let nativeKey = try XCTUnwrap(native.exists ? native : keyboard.keys.allElementsBoundByIndex.filter {
                $0.frame.midX > fixture.frame.width * 0.80 && $0.frame.width > 55
            }.max(by: { $0.frame.midY < $1.frame.midY }))
            screenshot("NativeReturn" + name, in: fixture)
            let nativeScreen = try XCTUnwrap(KeyboardScreen(fixture.screenshot(), screen: fixture.frame))
            let nativeBlue = nativeScreen.blueFraction(in: nativeKey.frame.insetBy(dx: 3, dy: 3))
            let custom = fixture.buttons["keyboardReturn"]
            selectClipboard(in: fixture, expecting: custom)
            XCTAssertEqual(custom.label, translated)
            screenshot("ClipboardReturn" + name, in: fixture)
            let customScreen = try XCTUnwrap(KeyboardScreen(fixture.screenshot(), screen: fixture.frame))
            let customBlue = customScreen.blueFraction(in: custom.frame.insetBy(dx: 3, dy: 3))
            XCTAssertEqual(nativeBlue > 0.40, customBlue > 0.40, "\(name): system blue \(nativeBlue), Clipboard blue \(customBlue), \(nativeKey)")
            custom.tap()
            let result = try XCTUnwrap(fixture.textViews["input"].value as? String)
            XCTAssertEqual(result.filter(\.isNewline).count, 1)
            XCTAssertEqual(result.filter { !$0.isNewline }, "sample")
        }
    }

    private func pictureFrame() -> CGRect? {
        let frame = fixture.frame
        if let picture = KeyboardScreen(XCUIScreen.main.screenshot(), screen: frame)?.pictureFrame() { return picture }
        let candidates = springboard.descendants(matching: .any).matching(NSPredicate(
            format: "identifier CONTAINS[c] 'pictureinpicture' OR identifier CONTAINS[c] 'PIP' OR label CONTAINS[c] 'picture in picture'"))
        return candidates.allElementsBoundByIndex.map(\.frame).first {
            $0.width > 70 && $0.width < frame.width * 0.95 && $0.height > 25 && $0.height < frame.height * 0.45
        }
    }

    private func stowPicture() throws {
        let frame = try XCTUnwrap(pictureFrame(), "The system Picture in Picture window was not visible over the fixture.")
        let screen = fixture.frame
        let origin = fixture.coordinate(withNormalizedOffset: .zero)
        let center = origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        let edge = origin.withOffset(CGVector(dx: frame.midX < screen.midX ? 1 : screen.width - 1, dy: frame.midY))
        center.press(forDuration: 0.15, thenDragTo: edge, withVelocity: .fast, thenHoldForDuration: 0.1)
        let stowed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.pictureFrame() == nil }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stowed], timeout: 6), .completed, "The full picture remained onscreen after dragging it to the edge.")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "CollectionAtScreenEdge"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testBatchReachesTheRealKeyboardWithSeparateContainers() {
        enableKeyboard()
        let prefix = String(UUID().uuidString.prefix(5)) + "-"
        app.launchEnvironment["CLIPBOARD_TEST_BATCH"] = prefix
        app.launch()
        XCTAssertTrue(app.buttons["captureToggle"].waitForExistence(timeout: 10))
        let deliver = app.buttons["deliverCopies"]
        let privateContainers = deliver.waitForExistence(timeout: 3)
        if privateContainers { deliver.tap(); finishDelivery() }
        fixture.launch()
        fixture.textViews["input"].tap()
        selectClipboard(in: fixture, expecting: historyKey(prefix + "three", in: fixture))
        for word in ["one", "two"] { XCTAssertTrue(historyKey(prefix + word, in: fixture).exists) }
        if privateContainers {
            let second = "next-" + prefix
            app.launchEnvironment["CLIPBOARD_TEST_BATCH"] = second
            app.launch()
            XCTAssertTrue(app.buttons["captureToggle"].waitForExistence(timeout: 12))
            fixture.activate()
            if !fixture.buttons["keyboardSpace"].exists { fixture.textViews["input"].tap() }
            let newest = historyKey(second + "three", in: fixture)
            if waitFor(newest, seconds: 8) {
                XCTContext.runActivity(named: "Subsequent local batch arrived automatically in the external keyboard") { _ in }
            } else {
                XCTContext.runActivity(named: "Complete the subsequent local batch via the trusted foreground receiver") { _ in }
                app.activate()
                XCTAssertTrue(deliver.waitForExistence(timeout: 8), app.debugDescription)
                deliver.tap()
                XCTAssertTrue(deliver.waitForNonExistence(timeout: 18))
                XCTAssertTrue(app.buttons["captureToggle"].waitForExistence(timeout: 18), app.debugDescription)
                fixture.activate()
                if !fixture.buttons["keyboardSpace"].exists { fixture.textViews["input"].tap() }
            }
            for word in ["one", "two", "three"] { XCTAssertTrue(waitFor(historyKey(second + word, in: fixture), seconds: 6)) }
        }
    }

    private func finishDelivery() {
        let receive = app.buttons["receiveCollectedCopies"], sheet = app.navigationBars["存入键盘"]
        if !receive.waitForExistence(timeout: 2), sheet.exists { selectClipboard(in: app, expecting: receive) }
        if receive.exists {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR enabled == true"), object: receive)
            _ = XCTWaiter.wait(for: [ready], timeout: 10)
            if receive.exists, receive.isEnabled { receive.tap() }
        }
        let confirmation = app.buttons["approveLocalReceiver"]
        if confirmation.waitForExistence(timeout: 3) { confirmation.tap() }
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["deliverCopies"].waitForNonExistence(timeout: 10), app.debugDescription)
    }

    func testVisibleCollectionSavesThreeCopiesAcrossApps() throws {
        enableKeyboard()
        app.activate()
        app.buttons["openCollection"].tap()
        app.buttons["captureToggle"].tap()
        let unsupported = label("这台设备当前不支持画中画。", in: app)
        if unsupported.waitForExistence(timeout: 2) { throw XCTSkip("AVKit reports that Picture in Picture is unavailable on this simulator.") }
        XCTAssertTrue(label("停止连拷", in: app).waitForExistence(timeout: 14), app.debugDescription)
        fixture.launchArguments = ["-CollectionFixture"]
        fixture.launch()
        copyInFixture("alpha")
        allowPasteIfRequested()
        try stowPicture()
        for word in ["bravo", "charlie"] {
            copyInFixture(word)
            allowPasteIfRequested()
        }
        app.activate()
        XCTAssertTrue(label("3 条", in: app).waitForExistence(timeout: 8) ||
                      app.descendants(matching: .any).matching(NSPredicate(format: "value == '3 条' OR label CONTAINS '3 条'")).firstMatch.exists,
                      app.debugDescription)
        app.buttons["captureToggle"].tap()
        if app.navigationBars["存入键盘"].waitForExistence(timeout: 4) { finishDelivery() }
        else if app.buttons["deliverCopies"].exists { app.buttons["deliverCopies"].tap(); finishDelivery() }
        fixture.activate()
        fixture.textViews["input"].tap()
        selectClipboard(in: fixture, expecting: historyKey("charlie", in: fixture))
        for word in ["alpha", "bravo"] { XCTAssertTrue(historyKey(word, in: fixture).exists, fixture.debugDescription) }
    }
}
