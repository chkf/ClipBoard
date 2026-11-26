import SwiftUI
import AppIntents
import WidgetKit

@main
struct ClipboardApp: App {
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            KeyboardSetupView()
                .onAppIntentExecution(ToggleCopyCollection.self) { _ in
                    CopyCollector.shared.requestToggle(external: true)
                }
                .onChange(of: scenePhase, initial: true) { _, phase in CopyCollector.shared.sceneChanged(phase) }
                .task {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
                    if UserDefaults.standard.string(forKey: "IndexedControlsBuild") != version {
                        ControlCenter.shared.reloadControls(ofKind: CollectionControl.kind)
                        ClipboardShortcuts.updateAppShortcutParameters()
                        UserDefaults.standard.set(version, forKey: "IndexedControlsBuild")
                    }
                }
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

struct ClipboardShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToggleCopyCollection(), phrases: ["用\(.applicationName)连续复制"],
                    shortTitle: "切换连续复制", systemImageName: "list.clipboard.fill")
    }
}
