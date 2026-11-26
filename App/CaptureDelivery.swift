import Foundation
import CryptoKit
import Network
import SwiftUI
import UIKit

@MainActor final class CaptureDelivery: ObservableObject {
    static var hasDelivered: Bool { UserDefaults.standard.bool(forKey: "KeyboardReceivedCollection") }
    @Published private(set) var ticket: CaptureTicket?
    @Published private(set) var done = false
    @Published private(set) var error: String?
    @Published private(set) var needsConfirmation = false
    private var approval: CheckedContinuation<Bool, Never>?
    private var invitation: Data?
    private var listener: NWListener?
    private var link: CaptureLink?
    private var task: Task<Void, Never>?
    private var cycle = UUID()

    func start() {
        stop()
        done = false
        error = nil
        let generation = cycle
        do {
            guard let identity = try CaptureMirror.secret(create: true) else { throw HistoryError.unreadable }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                    guard let self, self.cycle == generation else { return }
                    switch state {
                    case .ready:
                        if let port = listener?.port {
                            let ticket = CaptureTicket(port: port.rawValue, identity: identity)
                            self.invitation = CaptureMirror.issueInvitation(for: ticket)
                            self.ticket = ticket
                        }
                    case .failed: self.error = "未能打开本机连接，请重试。"
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.cycle == generation, let ticket = self.ticket, self.link == nil else { connection.cancel(); return }
                    let link = CaptureLink(connection, ticket: ticket)
                    self.link = link
                    self.task = Task {
                        defer { link.close(); if self.cycle == generation { self.link = nil } }
                        do {
                            guard try await link.read() == Data("receive".utf8) else { return }
                            // A host field can be seen by another selected input method. Require a
                            // private keyboard credential, a same-team invitation or a native confirmation.
                            let challenge = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                            try await link.send(challenge)
                            let proof = try await link.read()
                            let keys = [identity, self.invitation].compactMap { $0 }
                            let trusted = keys.contains {
                                HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: challenge, using: SymmetricKey(data: $0))
                            }
                            if !trusted {
                                self.needsConfirmation = true
                                guard await withCheckedContinuation({ self.approval = $0 }) else { return }
                            }
                            try await link.send(identity)
                            for file in try await CaptureInbox.shared.entries() {
                                let filename = file.deletingPathExtension().lastPathComponent
                                guard let dash = filename.firstIndex(of: "-") else { throw HistoryError.unreadable }
                                let input: FileHandle
                                do { input = try FileHandle(forReadingFrom: file) }
                                catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
                                defer { try? input.close() }
                                let header = Data(filename[filename.index(after: dash)...].utf8)
                                try await link.send(header)
                                try await link.sendFile(input)
                                guard try await link.read() == header else { throw HistoryError.unreadable }
                                try await CaptureInbox.shared.acknowledge(file)
                            }
                            try await link.send(Data("done".utf8))
                            guard try await link.read() == Data("done".utf8), self.cycle == generation else { return }
                            UserDefaults.standard.set(true, forKey: "KeyboardReceivedCollection")
                            self.done = true
                        } catch { if self.cycle == generation { self.error = "传送已中断。已保存的条目会保留，点重试可继续。" } }
                    }
                }
            }
            listener.start(queue: CaptureLink.queue)
        } catch { self.error = "未能打开本机连接，请重试。" }
    }
    func answer(_ allow: Bool) {
        needsConfirmation = false
        let continuation = approval
        approval = nil
        continuation?.resume(returning: allow)
    }
    func stop() {
        answer(false)
        invitation = nil
        cycle = UUID()
        task?.cancel(); task = nil
        listener?.cancel(); listener = nil
        link?.close(); link = nil
        ticket = nil
    }
}

struct CaptureDeliveryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var delivery = CaptureDelivery()
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let error = delivery.error { Text(error); Button("重试") { delivery.start() } }
                else if let ticket = delivery.ticket {
                    Text("首次使用时，在下方点「存入键盘」。之后会自动接收。如果出现其他输入法，请用地球键选择 Clipboard。")
                    CaptureTicketField(marker: ticket.marker).frame(height: 2).accessibilityHidden(true)
                    if delivery.needsConfirmation {
                        Text("请确认下方显示的是 Clipboard 键盘，再允许它接收这批记录。").font(.subheadline)
                        Button("允许此次存入") { delivery.answer(true) }.buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("approveLocalReceiver")
                    }
                } else { ProgressView() }
                Spacer()
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                .navigationTitle("存入键盘").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("稍后") { dismiss() } } }
        }
        .onAppear { delivery.start() }.onDisappear { delivery.stop() }
        .onChange(of: delivery.done) { _, done in if done { dismiss() } }
    }
}

private struct CaptureTicketField: UIViewControllerRepresentable {
    let marker: String
    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.marker = marker
        return controller
    }
    func updateUIViewController(_ controller: Controller, context: Context) {
        if controller.marker != marker {
            controller.marker = marker
            controller.apply()
        }
    }
    final class Controller: UIViewController {
        var marker = ""
        private let field = Field()
        override func loadView() {
            field.autocorrectionType = .no
            field.returnKeyType = .join
            field.textColor = .clear
            field.tintColor = .clear
            field.isAccessibilityElement = false
            view = field
            apply()
        }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply() }
        func apply() {
            if field.text != marker {
                field.text = marker
                field.textContentType = UITextContentType(rawValue: marker)
            }
            if field.window != nil {
                field.becomeFirstResponder()
                field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            }
        }
    }
    private final class Field: UITextView {
        override var textInputContextIdentifier: String? { "Clipboard.keyboard.collect" }
        override var textInputMode: UITextInputMode? { ClipboardInputMode.enabled ?? super.textInputMode }
        override func insertText(_ text: String) {}
        override func deleteBackward() {}
        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
    }
}
