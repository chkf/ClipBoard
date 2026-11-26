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
    func acknowledge(_ item: URL) throws {
        do { try FileManager.default.removeItem(at: item) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { return }
    }

    // Large items and older batches stay in the outbox for the streaming transfer.
    func updateMirror() async {
        guard let files = try? entries(), !files.isEmpty || hadMirror else { return }
        do {
            guard let key = try await CaptureMirror.secret(create: true) else { return }
            let received = Set(try await CaptureMirror.acknowledgements(key: key))
            var data: [Data] = [], remaining = CaptureMirror.limit
            for file in files.reversed() {
                let name = file.deletingPathExtension().lastPathComponent
                if let dash = name.firstIndex(of: "-"), let id = UUID(uuidString: String(name[name.index(after: dash)...])), received.contains(id) {
                    try acknowledge(file)
                } else if data.count < CaptureMirror.maximumItems,
                          let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= remaining {
                    data.append(try Data(contentsOf: file))
                    remaining -= size
                }
            }
            try await CaptureMirror.publish(Array(data.reversed()), key: key)
            hadMirror = !data.isEmpty
        } catch { /* The protected outbox remains available for a foreground transfer. */ }
    }
    private var hadMirror = false

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
