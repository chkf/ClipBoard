import SwiftUI

@main
struct ClipboardApp: App {
    @Environment(\.scenePhase) private var phase
    @StateObject private var session = ClipboardSession()

    var body: some Scene {
        WindowGroup {
            HistoryView(session: session)
                .onChange(of: phase, initial: true) { _, newPhase in
                    switch newPhase {
                    case .active: session.start(.app)
                    case .inactive: session.active = false
                    case .background: session.stop()
                    @unknown default: break
                    }
                }
        }
    }
}
