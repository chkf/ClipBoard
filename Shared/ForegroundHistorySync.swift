import Foundation
import Network
import SwiftUI

struct SyncInvitation: Equatable {
    let port: NWEndpoint.Port
    let token: String
    var marker: String { "CBS1/" + String(port.rawValue) + "/" + token }

    init(port: NWEndpoint.Port, token: String) { self.port = port; self.token = token }

    init?(_ marker: String?) {
        guard let marker, marker.utf8.count <= 46 else { return nil }
        let parts = marker.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "CBS1", let number = UInt16(parts[1]), number > 1023,
              let port = NWEndpoint.Port(rawValue: number), parts[2].count == 32,
              parts[2].allSatisfy({ $0.isHexDigit }) else { return nil }
        self.init(port: port, token: String(parts[2]))
    }
}

@MainActor
final class ForegroundHistorySync: ObservableObject {
    enum Phase: Equatable { case idle, waiting, pairing(String), transferring, done, failed(String) }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var invitation: SyncInvitation?
    private var listener: NWListener?
    private var channel: HistoryChannel?
    private var exchange: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var consent: CheckedContinuation<Void, Error>?
    private var generation = UUID()
    private var lastInvitation: SyncInvitation?

    func stop() {
        generation = UUID()
        listener?.cancel()
        listener = nil
        channel?.cancel()
        channel = nil
        exchange?.cancel()
        exchange = nil
        deadline?.cancel()
        deadline = nil
        consent?.resume(throwing: CancellationError())
        consent = nil
        lastInvitation = nil
        invitation = nil
        phase = .idle
    }

    func offer(_ store: HistoryStore) {
        stop()
        guard store.privateDirectory != nil, !store.readOnly else { return }
        let cycle = generation
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let server = try NWListener(using: parameters)
            listener = server
            phase = .waiting
            server.stateUpdateHandler = { [weak self, weak server] state in
                Task { @MainActor in
                    guard let self, self.generation == cycle else { return }
                    switch state {
                    case .ready:
                        if let port = server?.port {
                            self.invitation = SyncInvitation(port: port, token: UUID().uuidString.replacingOccurrences(of: "-", with: ""))
                        }
                    case .failed:
                        self.fail("未能打开本机同步，请重试。")
                    default: break
                    }
                }
            }
            server.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.generation == cycle, let invite = self.invitation, self.channel == nil else {
                        connection.cancel()
                        return
                    }
                    self.run(connection, invite: invite, host: true, store: store)
                }
            }
            server.start(queue: HistoryChannel.queue)
        } catch { fail("未能打开本机同步，请重试。") }
    }

    func join(_ invite: SyncInvitation?, store: HistoryStore) {
        guard let invite, invite != lastInvitation, store.privateDirectory != nil, !store.readOnly else { return }
        stop()
        lastInvitation = invite
        phase = .waiting
        let connection = NWConnection(host: "127.0.0.1", port: invite.port, using: .tcp)
        run(connection, invite: invite, host: false, store: store)
    }

    func approve() {
        guard let pending = consent else { return }
        consent = nil
        phase = .transferring
        pending.resume()
    }

    private func fail(_ message: String) {
        let attempted = lastInvitation
        stop()
        lastInvitation = attempted
        phase = .failed(message)
    }

    private func run(_ connection: NWConnection, invite: SyncInvitation, host: Bool, store: HistoryStore) {
        guard let directory = store.privateDirectory else { connection.cancel(); return }
        let link = HistoryChannel(connection)
        channel = link
        let cycle = generation
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, let self, generation == cycle else { return }
            fail("配对超时，请重新打开同步。")
        }
        exchange = Task { [weak self] in
            guard let self else { return }
            do {
                let file = directory.appendingPathComponent("keyboard-pairing.plist")
                var identity = try HistoryIdentity.load(at: file)
                let (peer, code) = try await link.authenticate(identity: identity, invitation: invite.token, host: host)
                guard generation == cycle, !Task.isCancelled else { throw CancellationError() }
                let needsPair = identity.peer != peer
                try await link.send(needsPair)
                let partnerNeedsPair: Bool = try await link.read()
                guard generation == cycle, !Task.isCancelled else { throw CancellationError() }
                if needsPair || partnerNeedsPair {
                    phase = .pairing(code)
                    try await withCheckedThrowingContinuation { self.consent = $0 }
                }
                try await link.send(true)
                let approved: Bool = try await link.read()
                guard approved, generation == cycle else { throw HistoryLinkError.closed }
                if needsPair { identity.peer = peer; try identity.save(at: file) }
                deadline?.cancel()
                deadline = nil
                phase = .transferring
                try await link.exchange(store: store, host: host)
                guard generation == cycle else { return }
                stop()
                lastInvitation = invite
                phase = .done
            } catch {
                if generation == cycle { fail("同步未完成。已有记录已保留，下次打开可继续。") }
            }
        }
    }
}
