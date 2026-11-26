import UIKit
import UniformTypeIdentifiers

enum SystemPasteboard {
    @MainActor static var stamp: PasteStamp {
        PasteStamp(boot: PasteStamp.systemBoot, count: UIPasteboard.general.changeCount)
    }

    // UIKit publishes providers first; representations and image decoding load off the UI thread.
    @MainActor static func providers() throws -> [NSItemProvider]? {
        let board = UIPasteboard.general
        // During foreground hand-off the change count can be visible before the representations.
        // An empty type probe is cheap to retry and must not consume a copy event.
        guard board.hasImages || board.hasStrings || board.hasURLs else { return nil }
        let providers = board.itemProviders
        guard !providers.isEmpty else { throw HistoryError.unreadable }
        return providers
    }

    static func read(_ providers: [NSItemProvider]) async throws -> PreparedClip? {
        for provider in providers {
            try Task.checkCancellation()
            let types = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
            if provider.registeredTypeIdentifiers.isEmpty { throw HistoryError.unreadable }
            if let image = types.first(where: { $0.conforms(to: .image) }) {
                let data = try await representation(image.identifier, from: provider)
                return try ImageContent.prepare(data)
            }
            if types.contains(where: { $0.conforms(to: .fileURL) }) { continue }
            if let text = types.first(where: { $0.conforms(to: .plainText) }) {
                let data = try await representation(text.identifier, from: provider)
                let string: String?
                if data.starts(with: [0xFE, 0xFF]) || data.starts(with: [0xFF, 0xFE]) {
                    string = String(data: data, encoding: .utf16)
                } else if text.conforms(to: .utf16PlainText) || text.conforms(to: .utf16ExternalPlainText) {
                    string = String(data: data, encoding: .utf16LittleEndian)
                } else {
                    string = String(data: data, encoding: .utf8)
                }
                guard let string else { throw HistoryError.unreadable }
                if !string.isEmpty { return .text(string) }
            } else if types.contains(where: { $0.conforms(to: .url) }) {
                let url: URL = try await withCheckedThrowingContinuation { continuation in
                    provider.loadObject(ofClass: NSURL.self) { value, _ in
                        if let value = value as? URL { continuation.resume(returning: value) }
                        else { continuation.resume(throwing: HistoryError.unreadable) }
                    }
                }
                if !url.isFileURL { return .text(url.absoluteString) }
            }
        }
        return nil
    }

    static func representation(_ type: String, from provider: NSItemProvider) async throws -> Data {
        let progress = Progress(totalUnitCount: 1)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let read = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                    if let data { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: HistoryError.unreadable) }
                }
                progress.addChild(read, withPendingUnitCount: 1)
                if progress.isCancelled { read.cancel() }
            }
        } onCancel: { progress.cancel() }
    }

    // Called on the storage actor while its SQLite write transaction owns the copy event.
    static func write(_ body: ClipBody) throws -> PasteStamp {
        let changed = DispatchSemaphore(value: 0)
        let sample = DispatchQueue.main.sync {
            let board = UIPasteboard.general
            let before = board.changeCount
            let observer = NotificationCenter.default.addObserver(forName: UIPasteboard.changedNotification,
                                                                   object: board, queue: nil) { _ in changed.signal() }
            let item: [String: Any]
            if let text = body.text { item = [body.type: text] }
            else { item = [body.type: body.data] }
            board.setItems([item], options: [.localOnly: true])
            return (before: before, after: stamp, observer: observer)
        }
        defer { NotificationCenter.default.removeObserver(sample.observer) }
        if sample.after.count != sample.before { return sample.after }
        // UIKit may defer incrementing changeCount until the end of the current event loop.
        // Wait on the storage actor, leaving the UI thread free to deliver the change.
        _ = changed.wait(timeout: .now() + 0.7)
        let published = DispatchQueue.main.sync { stamp }
        guard published.count != sample.before else { throw HistoryError.unreadable }
        return published
    }
}
