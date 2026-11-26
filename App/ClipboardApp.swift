import SwiftUI

@main
struct ClipboardApp: App {
    var body: some Scene {
        WindowGroup {
            KeyboardSetupView()
                #if DEBUG && targetEnvironment(simulator)
                .task {
                    guard let prefix = ProcessInfo.processInfo.environment["CLIPBOARD_TEST_BATCH"] else { return }
                    for word in ["one", "two", "three"] {
                        let item = CapturedItem(id: UUID(), date: Date(), clip: .text(prefix + word))
                        try? await CaptureInbox.shared.save(item)
                    }
                    await CopyCollector.shared.refreshPending()
                    CopyCollector.shared.showCollection = true
                }
                #endif
        }
    }
}
