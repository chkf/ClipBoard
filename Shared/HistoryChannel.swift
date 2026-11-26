import CryptoKit
import Foundation
import Network

enum HistoryLinkError: LocalizedError {
    case invalid, closed
    var errorDescription: String? {
        switch self {
        case .invalid: return "无法验证本次键盘同步，请重新打开同步。"
        case .closed: return "同步连接已关闭，已有记录已保留。"
        }
    }
}

struct HistoryIdentity: Codable {
    let secret: Data
    var peer: Data?

    static func load(at file: URL) throws -> Self {
        do { return try PropertyListDecoder().decode(Self.self, from: Data(contentsOf: file)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            let value = Self(secret: Curve25519.KeyAgreement.PrivateKey().rawRepresentation, peer: nil)
            try value.save(at: file)
            return value
        }
    }

    func save(at file: URL) throws {
        try PropertyListEncoder().encode(self).write(to: file, options: [.atomic, .completeFileProtection])
    }
}

private struct PeerHello: Codable {
    let invitation: String
    let key: Data
    let nonce: Data
}

// One protocol task owns the connection; cancellation may also arrive from the UI.
final class HistoryChannel: @unchecked Sendable {
    static let queue = DispatchQueue(label: "Clipboard.history.exchange", qos: .utility)
    private let connection: NWConnection
    private let idleTimer = DispatchSource.makeTimerSource(queue: HistoryChannel.queue)
    private var sendingKey: SymmetricKey?
    private var receivingKey: SymmetricKey?
    private var sent: UInt64 = 0
    private var received: UInt64 = 0
    private let chunk = 64 * 1024

    init(_ connection: NWConnection) {
        self.connection = connection
        idleTimer.setEventHandler { [weak connection] in connection?.cancel() }
        idleTimer.schedule(deadline: .now() + 120)
        idleTimer.resume()
        connection.start(queue: Self.queue)
    }
    deinit { idleTimer.cancel() }
    func cancel() { idleTimer.cancel(); connection.cancel() }

    func authenticate(identity: HistoryIdentity, invitation: String, host: Bool) async throws -> (peer: Data, code: String) {
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: identity.secret)
        let mine = PeerHello(invitation: invitation, key: privateKey.publicKey.rawRepresentation,
                             nonce: Data(SHA256.hash(data: Data(UUID().uuidString.utf8))))
        if !host { try await send(mine) }
        let other: PeerHello = try await read()
        guard other.invitation == invitation, other.key != mine.key, other.nonce.count == 32 else { throw HistoryLinkError.invalid }
        if host { try await send(mine) }
        let remote = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: other.key)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: remote)
        let salt = host ? mine.nonce + other.nonce : other.nonce + mine.nonce
        func derive(_ purpose: String) -> SymmetricKey {
            shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
                                          sharedInfo: Data(("Clipboard history v1 " + purpose).utf8), outputByteCount: 32)
        }
        sendingKey = derive(host ? "app" : "keyboard")
        receivingKey = derive(host ? "keyboard" : "app")
        let digits = derive("pair").withUnsafeBytes { $0.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } } % 1_000_000
        return (other.key, String(format: "%06u", digits))
    }

    func send<T: Encodable>(_ value: T) async throws { try await writeFrame(JSONEncoder().encode(value)) }
    func read<T: Decodable>() async throws -> T { try JSONDecoder().decode(T.self, from: await readFrame()) }

    private func writeFrame(_ cleartext: Data) async throws {
        try Task.checkCancellation()
        guard cleartext.count <= chunk else { throw HistoryLinkError.invalid }
        let payload: Data
        if let key = sendingKey {
            let sequence = withUnsafeBytes(of: sent.bigEndian) { Data($0) }
            payload = try ChaChaPoly.seal(cleartext, using: key, authenticating: sequence).combined
        } else { payload = cleartext }
        let header = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            idleTimer.schedule(deadline: .now() + 120)
            connection.send(content: header + payload, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
        sent += 1
    }

    private func readFrame() async throws -> Data {
        let prefix = try await exact(4)
        let count = prefix.reduce(0) { ($0 << 8) | Int($1) }
        guard count > 0, count <= (receivingKey == nil ? 1024 : chunk + 28) else { throw HistoryLinkError.invalid }
        let payload = try await exact(count)
        let sequence = withUnsafeBytes(of: received.bigEndian) { Data($0) }
        received += 1
        guard let key = receivingKey else { return payload }
        return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: payload), using: key, authenticating: sequence)
    }

    private func exact(_ count: Int) async throws -> Data {
        var result = Data()
        while result.count < count {
            try Task.checkCancellation()
            let remaining = count - result.count
            let part: Data = try await withCheckedThrowingContinuation { continuation in
                idleTimer.schedule(deadline: .now() + 120)
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { bytes, _, _, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let bytes, !bytes.isEmpty { continuation.resume(returning: bytes) }
                    else { continuation.resume(throwing: HistoryLinkError.closed) }
                }
            }
            result.append(part)
        }
        return result
    }

    func exchange(store: HistoryStore, host: Bool) async throws {
        // Always merge the keyboard first, so the return snapshot includes its edits as well as the app's.
        if host {
            try await acceptSnapshot(store: store, fromMainApp: false)
            try await offerSnapshot(store: store)
            let finished: Bool = try await read()
            guard finished else { throw HistoryLinkError.invalid }
            try await send(true)
        } else {
            try await offerSnapshot(store: store)
            try await acceptSnapshot(store: store, fromMainApp: true)
            try await send(true)
            let finished: Bool = try await read()
            guard finished else { throw HistoryLinkError.invalid }
        }
    }

    private func offerSnapshot(store: HistoryStore) async throws {
        let version = try await store.receipt().local
        try await send(version)
        let needed: Bool = try await read()
        guard needed else { return }
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("out.sqlite3")
        try await store.exportHistory(to: url)
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        while let bytes = try file.read(upToCount: chunk), !bytes.isEmpty { try await writeFrame(bytes) }
        try await writeFrame(Data())
    }

    private func acceptSnapshot(store: HistoryStore, fromMainApp: Bool) async throws {
        let version: HistoryVersion = try await read()
        let needed = try await store.receipt().received != version
        try await send(needed)
        guard needed else { return }
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("in.sqlite3")
        try Data().write(to: url, options: .completeFileProtection)
        let file = try FileHandle(forWritingTo: url)
        do {
            while true {
                let bytes = try await readFrame()
                guard !bytes.isEmpty else { break }
                try file.write(contentsOf: bytes)
            }
            try file.close()
        } catch { try? file.close(); throw error }
        try Task.checkCancellation()
        try await store.mergeHistory(from: url, expectedID: version.id, fromMainApp: fromMainApp)
    }

    private static func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false,
                                               attributes: [.protectionKey: FileProtectionType.complete])
        return dir
    }
}
