import Foundation
import XCTest

final class HistoryContainerTests: XCTestCase {
    private let configured = "group.net.chkf.Clipboard"

    func testExplicitConfigurationAndRewrittenHostID() {
        let host = "com.example.MyClipboard"
        let hostGroup = "group." + host
        XCTAssertEqual(HistoryContainer.candidates(configured: configured, hostID: host, signerGroups: nil),
                       [configured, hostGroup])
        XCTAssertEqual(HistoryContainer.candidates(configured: configured, hostID: host, signerGroups: [hostGroup]),
                       [hostGroup])
        XCTAssertEqual(HistoryContainer.candidates(configured: configured, hostID: host, signerGroups: [hostGroup, configured]),
                       [configured])
    }

    func testSideStoreRemapIsIndependentOfListOrderAndOtherGroups() {
        let expected = configured + ".AB12CD34EF"
        let unrelated = "group.com.example.Other"
        for groups in [[unrelated, expected], [expected, unrelated, expected]] {
            XCTAssertEqual(HistoryContainer.candidates(configured: configured, hostID: nil, signerGroups: groups),
                           [expected])
        }
        for groups in [[], [unrelated], [configured + ".widgets"], [expected, configured + ".ZX98YX76WV"]] {
            XCTAssertTrue(HistoryContainer.candidates(configured: configured, hostID: nil, signerGroups: groups).isEmpty)
        }
    }

    func testInstalledAppAndKeyboardResolveTheProvisionedContainer() async throws {
        let host = Bundle.main
        let plugins = try XCTUnwrap(host.builtInPlugInsURL)
        let keyboard = try XCTUnwrap(Bundle(url: plugins.appendingPathComponent("ClipboardKeyboard.appex")))
        if host.object(forInfoDictionaryKey: "ClipboardPrivateHistory") as? Bool == true {
            XCTAssertThrowsError(try HistoryContainer.url(for: host))
            XCTAssertThrowsError(try HistoryContainer.url(for: keyboard))
            let store = try await HistoryStore.shared()
            _ = try await store.state()
            return
        }
        let provisioned = host.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]
        let group = try XCTUnwrap(provisioned?.first ?? (host.object(forInfoDictionaryKey: "ClipboardAppGroup") as? String))
        let expected = try XCTUnwrap(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group))
        XCTAssertEqual(try HistoryContainer.url(for: host), expected)
        XCTAssertEqual(try HistoryContainer.url(for: keyboard), expected)
    }
}
