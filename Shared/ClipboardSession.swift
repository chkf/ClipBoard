import SwiftUI
import UIKit

@MainActor
final class ClipboardSession: ObservableObject {
    enum Mode: Equatable {
        case app, keyboard(fullAccess: Bool)
        var mayWrite: Bool { self != .keyboard(fullAccess: false) }
    }

    @Published private(set) var rows: [ClipRow] = []
    @Published private(set) var settings = HistorySettings()
    @Published private(set) var loaded = false
    @Published private(set) var copied = 0
    @Published private(set) var message: String?
    @Published private(set) var mode: Mode = .app
    private(set) var store: HistoryStore?
    private let keyboardAccess: (() -> Bool)?
    private let open: (Bool) async throws -> HistoryStore
    private var monitor: Task<Void, Never>?
    private var capture: Task<Void, Never>?
    private var captureStamp: PasteStamp?
    private var notification: NSObjectProtocol?
    private var generation = UUID()
    private var failedStamp: PasteStamp?
    private var verifiedStamp: PasteStamp?
    private var revision = -1
    private var pageEnd = false
    private var paging = false
    private var lastPrune = Date.distantPast
    var active = true

    init(keyboardAccess: (() -> Bool)? = nil,
         open: @escaping (Bool) async throws -> HistoryStore = { try await HistoryStore.shared(readOnly: $0) }) {
        self.keyboardAccess = keyboardAccess
        self.open = open
    }

    func start(_ mode: Mode) {
        active = true
        if monitor != nil, mode == self.mode { return }
        stop()
        self.mode = mode
        let generation = self.generation
        notification = NotificationCenter.default.addObserver(forName: UIPasteboard.changedNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.tick(generation) }
        }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick(generation)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        monitor?.cancel()
        capture?.cancel()
        if let notification { NotificationCenter.default.removeObserver(notification) }
        notification = nil
        monitor = nil
        capture = nil
        captureStamp = nil
        generation = UUID()
        failedStamp = nil
        verifiedStamp = nil
        revision = -1
        lastPrune = .distantPast
        store = nil
        loaded = false
        rows = []
        message = nil
        paging = false
    }

    private func tick(_ cycle: UUID) async {
        guard generation == cycle, active else { return }
        if case .keyboard(let previous) = mode, let current = keyboardAccess?(), current != previous {
            start(.keyboard(fullAccess: current))
            return
        }
        do {
            if store == nil {
                let connection = try await open(!mode.mayWrite)
                guard generation == cycle else { return }
                if mode == .keyboard(fullAccess: true) { try await connection.keyboardConfigured() }
                guard generation == cycle else { return }
                store = connection
            }
            guard let store else { return }
            if mode.mayWrite, Date().timeIntervalSince(lastPrune) >= 60 {
                try await store.prune()
                guard generation == cycle else { return }
                lastPrune = Date()
            }
            let state = try await refresh(store, cycle: cycle)
            guard generation == cycle, active, mode.mayWrite else { return }
            let stamp = SystemPasteboard.stamp
            if captureStamp == stamp { return }
            capture?.cancel()
            capture = nil
            captureStamp = nil
            // On first appearance verify the content as well as the counter. UIKit may
            // publish a batched counter update at the end of a foreground event loop.
            guard failedStamp != stamp, state.event?.stamp != stamp || verifiedStamp != stamp else { return }
            captureStamp = stamp
            capture = Task { [weak self] in
                guard let self else { return }
                defer {
                    if self.generation == cycle, self.captureStamp == stamp {
                        self.capture = nil
                        self.captureStamp = nil
                    }
                }
                do {
                    guard let providers = try SystemPasteboard.providers() else { return }
                    let clip = try await SystemPasteboard.read(providers)
                    try Task.checkCancellation()
                    guard self.generation == cycle, SystemPasteboard.stamp == stamp else { return }
                    try await store.observe(clip, stamp: stamp, replacing: state.event)
                    guard self.generation == cycle else { return }
                    self.message = nil
                    let committed = try await self.refresh(store, cycle: cycle)
                    if self.generation == cycle, committed.event == PasteEvent(stamp: stamp, key: clip?.key) {
                        self.verifiedStamp = stamp
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard self.generation == cycle, !Task.isCancelled else { return }
                    if case HistoryError.unreadable = error { self.failedStamp = stamp }
                    self.message = error.localizedDescription
                }
            }
        } catch {
            if generation == cycle, mode.mayWrite { message = error.localizedDescription }
        }
    }

    @discardableResult
    private func refresh(_ store: HistoryStore, cycle: UUID) async throws -> HistoryState {
        let state = try await store.state()
        guard generation == cycle, state.revision > revision else { return state }
        let limit = max(60, rows.count)
        let page = try await store.page(limit: limit)
        guard generation == cycle, state.revision > revision else { return state }
        settings = state.settings
        rows = page
        pageEnd = page.count < limit
        revision = state.revision
        loaded = true
        return state
    }

    func nextPage(after row: ClipRow) async {
        guard row.id == rows.last?.id, !pageEnd, !paging, let store else { return }
        let cycle = generation, startingRevision = revision
        paging = true
        defer { if generation == cycle { paging = false } }
        do {
            let page = try await store.page(after: row)
            guard generation == cycle, revision == startingRevision, rows.last?.id == row.id else { return }
            rows.append(contentsOf: page)
            pageEnd = page.count < 60
        } catch { if generation == cycle { message = error.localizedDescription } }
    }

    func body(_ row: ClipRow) async -> ClipBody? {
        do { return try await store?.body(row.id) }
        catch { message = error.localizedDescription; return nil }
    }

    @discardableResult
    func copy(_ row: ClipRow) async -> Bool {
        guard mode.mayWrite, let store else { return false }
        let cycle = generation
        do {
            try await store.copy(row.id) { try SystemPasteboard.write($0) }
            guard generation == cycle else { return false }
            message = nil
            copied += 1
            try await refresh(store, cycle: cycle)
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func selectInKeyboard(_ row: ClipRow, insert: (String) -> Void, advance: () -> Void) async {
        guard let store else { return }
        if row.isImage {
            if await copy(row) { UIAccessibility.post(notification: .announcement, argument: "图片已复制") }
            return
        }
        let cycle = generation
        do {
            let body = try await store.body(row.id)
            let state = try await store.state()
            guard generation == cycle, let text = body.text else { return }
            insert(text)
            if state.settings.autoSwitch { advance() }
        } catch { message = error.localizedDescription }
    }

    func edit(_ change: (HistoryStore) async throws -> Void) async {
        guard mode.mayWrite, let store else { return }
        let cycle = generation
        do {
            try await change(store)
            try await refresh(store, cycle: cycle)
        } catch { if generation == cycle { message = error.localizedDescription } }
    }
}
