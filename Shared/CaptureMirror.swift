import CryptoKit
import UIKit

// The containing app keeps the durable outbox. This local, same-team pasteboard lets a
// separately signed keyboard pick up a recent batch even while the containing app is suspended.
@MainActor enum CaptureMirror {
    nonisolated static let limit = 1024 * 1024
    nonisolated static let maximumItems = 128
    private static var cachedKey: Data?
    private static let type = "com.chkf.clipboard.encrypted-batch"

    static func secret(create: Bool = false) throws -> Data? {
        if let cachedKey { return cachedKey }
        let url = try keyURL()
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard data.count == 32 else { throw HistoryError.unreadable }
            cachedKey = data
        } else if create {
            try remember(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
        }
        return cachedKey
    }
    static func remember(_ data: Data) throws {
        guard data.count == 32 else { throw HistoryError.unreadable }
        if cachedKey != data {
            var url = try keyURL()
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            cachedKey = data
        }
    }
    private static func keyURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("CollectionReceiverKey")
    }

    private static func board(_ channel: String, key: Data, create: Bool) -> UIPasteboard? {
        let name = "net.chkf.clipboard." + SHA256.hash(data: key).hex + "." + channel
        return UIPasteboard(name: UIPasteboard.Name(rawValue: name), create: create)
    }
    private static func put<T: Encodable>(_ value: T, on board: UIPasteboard, key: Data, channel: String) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let sealed = try ChaChaPoly.seal(encoder.encode(value), using: SymmetricKey(data: key), authenticating: Data(channel.utf8))
        board.setItems([[type: sealed.combined]], options: [.localOnly: true])
    }
    private static func get<T: Decodable>(_ result: T.Type, from board: UIPasteboard, key: Data, channel: String) throws -> T? {
        guard let encrypted = board.data(forPasteboardType: type), encrypted.count <= 2 * limit else { return nil }
        let plain = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: encrypted), using: SymmetricKey(data: key), authenticating: Data(channel.utf8))
        return try PropertyListDecoder().decode(result, from: plain)
    }
    static func publish(_ encodedItems: [Data], key: Data) throws {
        guard let board = board("copies", key: key, create: !encodedItems.isEmpty) else { return }
        try put(encodedItems, on: board, key: key, channel: "copies")
    }
    static func acknowledgements(key: Data) throws -> [UUID] {
        guard let board = board("received", key: key, create: false) else { return [] }
        return try get([UUID].self, from: board, key: key, channel: "received") ?? []
    }
    @MainActor final class Reader {
        private var lastDigest: Data?
        private var checkedCount: Int?
        private var checkedAt = Date.distantPast
        func receive(into store: HistoryStore) async throws {
            guard let key = try CaptureMirror.secret(), let source = board("copies", key: key, create: false) else { return }
            let count = source.changeCount
            guard checkedCount != count || Date().timeIntervalSince(checkedAt) >= 8 else { return }
            checkedCount = count
            checkedAt = Date()
            guard let encrypted = source.data(forPasteboardType: type), encrypted.count <= 2 * limit else { return }
            let digest = Data(SHA256.hash(data: encrypted))
            guard digest != lastDigest else { return }
            let unsealed = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: encrypted), using: SymmetricKey(data: key),
                                                authenticating: Data("copies".utf8))
            let items = try PropertyListDecoder().decode([Data].self, from: unsealed)
            guard items.count <= maximumItems else { return }
            var receipts = try acknowledgements(key: key)
            for data in items {
                let item = try PropertyListDecoder().decode(CapturedItem.self, from: data)
                try await store.importCapture(item)
                if !receipts.contains(item.id) { receipts.append(item.id) }
            }
            if !items.isEmpty, let response = board("received", key: key, create: true) {
                try put(Array(receipts.suffix(maximumItems * 2)), on: response, key: key, channel: "received")
            }
            lastDigest = digest
        }
    }
}
