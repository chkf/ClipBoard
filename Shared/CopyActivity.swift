import ActivityKit
import AppIntents

struct CopyActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable { var count: Int }
    let session: UUID
}

struct ToggleCopyCollection: LiveActivityIntent {
    static let title: LocalizedStringResource = "开始或停止连拷"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        #if CLIPBOARD_HOST
        CopyCollector.shared.requestToggle()
        #endif
        return .result()
    }
}

struct EndCopyCollection: LiveActivityIntent {
    static let title: LocalizedStringResource = "停止连拷"
    @MainActor func perform() async throws -> some IntentResult {
        #if CLIPBOARD_HOST
        CopyCollector.shared.stop()
        #endif
        return .result()
    }
}
