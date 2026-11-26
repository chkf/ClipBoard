import Foundation

actor CaptureInbox {
    static let shared = CaptureInbox()
    private var history: HistoryStore?
    private var folder: URL {
        get throws {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            var directory = root.appendingPathComponent("CollectedCopies", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.protectionKey: FileProtectionType.complete])
            var options = URLResourceValues()
            options.isExcludedFromBackup = true
            try directory.setResourceValues(options)
            return directory
        }
    }
    func entries() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "clip" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func acknowledge(_ item: URL) throws { try FileManager.default.removeItem(at: item) }

    func save(_ item: CapturedItem) async throws {
        if let container = try? HistoryContainer.url() {
            if history == nil { history = try HistoryStore(directory: container.appendingPathComponent("History")) }
            if let history {
                try await history.importCapture(item)
                return
            }
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let time = String(Int64(item.date.timeIntervalSince1970 * 1_000_000))
        let name = time + "-" + item.id.uuidString + ".clip"
        try encoder.encode(item).write(to: try folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
    }
}
