import ActivityKit
import AppIntents
import Foundation

struct CopyActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable { var count: Int }
    let session: UUID
}

enum CollectionDestination: String, AppEnum {
    case collection
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Clipboard 功能"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.collection: "连续复制"]
}

struct ToggleCopyCollection: OpenIntent, TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "切换连续复制"
    @Parameter(title: "功能", default: .collection) var target: CollectionDestination
}

enum CollectionControl {
    static let kind = "net.chkf.Clipboard.collect"
    static let symbol = "list.clipboard.fill"
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
