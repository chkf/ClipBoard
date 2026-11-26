import ActivityKit
import AVFAudio
import SwiftUI
import UIKit

@MainActor final class CopyCollector: NSObject, ObservableObject {
    static let shared = CopyCollector()
    enum Phase { case idle, starting, running }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var count = 0
    @Published private(set) var pending = 0
    @Published private(set) var message: String?
    @Published var showCollection = false
    @Published var showImport = false
    let picture = CopyPicture()
    private var wantsStart = false
    private var attached = false
    private var clock: Task<Void, Never>?
    private var writes: Task<Void, Never>?
    private var publishCopies: Task<Void, Never>?
    private var activity: Activity<CopyActivity>?
    private var observed: PasteStamp?
    private var sessionID = UUID()
    private var locking = false
    private var failedAt: Date?
    override init() {
        super.init()
        picture.started = { [weak self] in self?.didStart() }
        picture.stopped = { [weak self] in self?.stop() }
        picture.failed = { [weak self] reason in self?.stop(); self?.message = reason }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(willLock), name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        center.addObserver(self, selector: #selector(didUnlock), name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        center.addObserver(self, selector: #selector(boardChanged), name: UIPasteboard.changedNotification, object: nil)
        center.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        // A killed process can leave the last status on the Island. Never resume capture on launch.
        for stale in Activity<CopyActivity>.activities { Task { await stale.end(nil, dismissalPolicy: .immediate) } }
    }

    func requestToggle() {
        if phase != .idle || wantsStart { showCollection = true; stop(); return }
        showCollection = true
        wantsStart = true
        startIfReady()
    }
    func mountPicture(_ view: UIView) {
        if picture.layer.superlayer !== view.layer {
            picture.layer.removeFromSuperlayer()
            view.layer.addSublayer(picture.layer)
        }
        picture.layer.frame = view.bounds
        attached = view.window != nil
        if attached { startIfReady() }
    }
    func unmountPicture(_ view: UIView) {
        if picture.layer.superlayer === view.layer { attached = false }
    }
    func refreshPending() async {
        await CaptureInbox.shared.updateMirror()
        pending = (try? await CaptureInbox.shared.entries().count) ?? pending
    }
    private func startIfReady() {
        guard wantsStart, attached, phase == .idle, UIApplication.shared.applicationState == .active,
              UIApplication.shared.isProtectedDataAvailable else { return }
        wantsStart = false
        message = nil
        locking = false
        count = 0
        sessionID = UUID()
        phase = .starting
        do { try picture.start() } catch { stop(); message = error.localizedDescription }
    }
    private func didStart() {
        guard phase == .starting else { return }
        observed = SystemPasteboard.stamp
        failedAt = nil
        phase = .running
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(attributes: CopyActivity(session: sessionID),
                                             content: ActivityContent(state: .init(count: 0), staleDate: nil), pushType: nil)
        }
        clock = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                self?.sample()
                ticks += 1
                if ticks % 6 == 0, let self { self.picture.render(count: self.count) }
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
    }
    func stop() {
        wantsStart = false
        guard phase != .idle else { return }
        if phase == .running, !locking, UIApplication.shared.isProtectedDataAvailable { sample() }
        phase = .idle
        clock?.cancel()
        clock = nil
        picture.stop()
        let live = activity
        activity = nil
        Task { await live?.end(nil, dismissalPolicy: .immediate) }
        let last = writes
        let ending = sessionID
        Task {
            await last?.value
            await refreshPending()
            if ending == sessionID, phase == .idle, !locking, pending > 0, !CaptureDelivery.hasDelivered,
               UIApplication.shared.applicationState == .active { showImport = true }
        }
    }
    @objc private func willLock() { locking = true; stop() }
    @objc private func didUnlock() { locking = false }
    @objc private func becameActive() {
        picture.startIfReady()
        startIfReady()
        Task { await refreshPending() }
    }
    @objc private func boardChanged() { sample() }
    @objc private func interrupted(_ note: Notification) {
        if let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, raw == AVAudioSession.InterruptionType.began.rawValue { stop() }
    }

    private func sample() {
        guard phase == .running, !locking else { return }
        guard UIApplication.shared.isProtectedDataAvailable else { willLock(); return }
        let stamp = SystemPasteboard.stamp
        guard stamp != observed, failedAt.map({ Date().timeIntervalSince($0) >= 1 }) ?? true else { return }
        let providers: [NSItemProvider]
        do {
            guard let current = try SystemPasteboard.providers() else { return }
            providers = current
        } catch { failedAt = Date(); message = error.localizedDescription; return }
        // Begin loading each snapshot immediately. Only disk commits wait for the preceding copy.
        let captured = Date(), cycle = sessionID
        let prepared = Task { try await SystemPasteboard.read(providers) }
        let previous = writes
        observed = stamp
        writes = Task { [weak self] in
            await previous?.value
            do {
                guard let clip = try await prepared.value else { return }
                try await CaptureInbox.shared.save(CapturedItem(id: UUID(), date: captured, clip: clip))
                guard let self, cycle == self.sessionID else { return }
                self.count += 1
                self.message = nil
                if self.phase == .running {
                    self.publishCopies?.cancel()
                    self.publishCopies = Task {
                        try? await Task.sleep(for: .milliseconds(240))
                        if !Task.isCancelled { await CaptureInbox.shared.updateMirror() }
                    }
                    self.picture.render(count: self.count)
                    if let activity = self.activity {
                        await activity.update(ActivityContent(state: .init(count: self.count), staleDate: nil))
                    }
                }
            } catch {
                guard let self, self.sessionID == cycle else { return }
                self.message = error.localizedDescription
                if self.observed == stamp { self.observed = nil; self.failedAt = Date() }
            }
        }
    }
}
