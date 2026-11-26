import CryptoKit
import Foundation
import Network

struct CaptureTicket: Equatable {
    let port: UInt16
    let secret: Data
    let proof: Data
    private var endpoint: String { "CBC2.\(port)." + secret.base64EncodedString() }
    var marker: String { endpoint + "." + proof.base64EncodedString() }
    init(port: UInt16, identity: Data) {
        self.port = port
        let secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        self.secret = secret
        let endpoint = "CBC2.\(port)." + secret.base64EncodedString()
        proof = Data(HMAC<SHA256>.authenticationCode(for: Data(endpoint.utf8), using: SymmetricKey(data: identity)))
    }
    init?(_ marker: String?) {
        guard let marker, marker.count < 120 else { return nil }
        let parts = marker.split(separator: ".")
        guard parts.count == 4, parts[0] == "CBC2", let port = UInt16(parts[1]), port > 1023,
              let key = Data(base64Encoded: String(parts[2])), key.count == 32,
              let proof = Data(base64Encoded: String(parts[3])), proof.count == 32 else { return nil }
        self.port = port
        secret = key
        self.proof = proof
    }
    func authenticates(_ identity: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: Data(endpoint.utf8), using: SymmetricKey(data: identity))
    }
}

// One short-lived, authenticated connection on the device. The keyboard only receives
// the pending copies; the containing app never reads the keyboard's history or settings.
final class CaptureLink: @unchecked Sendable {
    static let queue = DispatchQueue(label: "Clipboard.capture.delivery", qos: .userInitiated)
    static let chunk = 64 * 1024
    private let connection: NWConnection
    private let key: SymmetricKey
    private let timeout = DispatchSource.makeTimerSource(queue: CaptureLink.queue)
    init(_ connection: NWConnection, ticket: CaptureTicket) {
        self.connection = connection
        key = SymmetricKey(data: ticket.secret)
        timeout.setEventHandler { [weak connection] in connection?.cancel() }
        timeout.schedule(deadline: .now() + 30)
        timeout.resume()
        connection.start(queue: Self.queue)
    }
    deinit { timeout.cancel(); connection.cancel() }
    func close() { timeout.cancel(); connection.cancel() }
    func send(_ data: Data) async throws {
        guard data.count <= Self.chunk else { throw HistoryError.unreadable }
        let sealed = try ChaChaPoly.seal(data, using: key).combined
        let encoded = withUnsafeBytes(of: UInt32(sealed.count).bigEndian) { Data($0) } + sealed
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            timeout.schedule(deadline: .now() + 30)
            connection.send(content: encoded, completion: .contentProcessed { error in
                if let error { done.resume(throwing: error) } else { done.resume() }
            })
        }
    }
    func read() async throws -> Data {
        let n = try await bytes(4).reduce(0) { ($0 << 8) | Int($1) }
        guard (28...(Self.chunk + 28)).contains(n) else { throw HistoryError.unreadable }
        return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: await bytes(n)), using: key)
    }
    private func bytes(_ count: Int) async throws -> Data {
        var result = Data()
        while result.count < count {
            try Task.checkCancellation()
            let needed = count - result.count
            let part: Data = try await withCheckedThrowingContinuation { done in
                timeout.schedule(deadline: .now() + 30)
                connection.receive(minimumIncompleteLength: 1, maximumLength: needed) { data, _, _, error in
                    if let error { done.resume(throwing: error) }
                    else if let data, !data.isEmpty { done.resume(returning: data) }
                    else { done.resume(throwing: HistoryError.unreadable) }
                }
            }
            result.append(part)
        }
        return result
    }
    func sendFile(_ file: URL) async throws {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: Self.chunk), !chunk.isEmpty { try await send(chunk) }
        try await send(Data())
    }
    func receiveItems(into store: HistoryStore, ticket: CaptureTicket) async throws {
        try await send(Data("receive".utf8))
        let identity = try await read()
        guard identity.count == 32, ticket.authenticates(identity) else { throw HistoryError.unreadable }
        try await CaptureMirror.remember(identity)
        while true {
            let header = try await read()
            if header == Data("done".utf8) { try await send(Data("done".utf8)); return }
            guard let id = UUID(uuidString: String(decoding: header, as: UTF8.self)) else { throw HistoryError.unreadable }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: tmp) }
            try Data().write(to: tmp, options: .completeFileProtection)
            let output = try FileHandle(forWritingTo: tmp)
            do {
                while true {
                    let bytes = try await read()
                    if bytes.isEmpty { break }
                    try output.write(contentsOf: bytes)
                }
                try output.close()
            } catch { try? output.close(); throw error }
            let item = try PropertyListDecoder().decode(CapturedItem.self, from: Data(contentsOf: tmp, options: .mappedIfSafe))
            guard item.id == id else { throw HistoryError.unreadable }
            try await store.importCapture(item)
            try await send(header)
        }
    }
}
