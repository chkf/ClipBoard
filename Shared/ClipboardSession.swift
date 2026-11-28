import SwiftUI
import UIKit

enum KeyboardEntryPhase: Equatable {
    case preparing, categoriesOnly, history, unavailable
}

@MainActor
final class ClipboardSession: ObservableObject {
    @Published private(set) var rows: [ClipRow] = []
    @Published private(set) var settings = HistorySettings()
    @Published private(set) var loaded = false
    @Published private(set) var entryPhase = KeyboardEntryPhase.preparing
    @Published private(set) var checkingInitialPasteboard = false
    @Published private(set) var copied = 0
    @Published private(set) var message: String?
    @Published private(set) var fullAccess = false
    @Published private(set) var categories: [ClipCategory] = [.ordinary]
    @Published private(set) var category = ClipCategory.ordinary.id
    @Published private(set) var undoAvailable = false
    @Published private(set) var ordinaryCount = 0
    private(set) var store: HistoryStore?
    private let keyboardAccess: (() -> Bool)?
    private let open: (Bool) async throws -> HistoryStore
    private var monitor: Task<Void, Never>?
    private var firstRead: Task<Void, Never>?
    private var revealCategories: Task<Void, Never>?
    private var undoCleanup: Task<Void, Never>?
    private var capture: Task<Void, Never>?
    private var captureStamp: PasteStamp?
    private var notification: NSObjectProtocol?
    private var generation = UUID()
    private var listGeneration = UUID()
    private var failedStamp: PasteStamp?
    private var failedAttempts = 0
    private var retryAfter = Date.distantPast
    private var verifiedStamp: PasteStamp?
    private var revision = -1
    private var pageEnd = false
    private var paging = false
    private var lastPrune = Date.distantPast
    private var captureEnabled = true
    private var pendingEdit: Task<Void, Never>?
    var active = true

    init(keyboardAccess: (() -> Bool)? = nil,
         open: @escaping (Bool) async throws -> HistoryStore = { try await HistoryStore.shared(readOnly: $0) }) {
        self.keyboardAccess = keyboardAccess
        self.open = open
    }

    func start(fullAccess: Bool, captureEnabled: Bool = true) {
        let resuming = !active
        if monitor != nil, fullAccess == self.fullAccess, captureEnabled == self.captureEnabled {
            active = true
            if resuming { verifiedStamp = nil }
            return
        }
        let cutoff = Date().addingTimeInterval(-Double(settings.retention) * 86_400).timeIntervalSince1970
        let reuse = entryPhase == .history && category == ClipCategory.ordinary.id &&
            self.fullAccess == fullAccess && self.captureEnabled == captureEnabled &&
            rows.prefix(60).allSatisfy { $0.isPinned || $0.updated > cutoff }
        suspendForSwitch()
        if reuse {
            if rows.count > 60 { rows = Array(rows.prefix(60)) }
        } else {
            clearPresentation()
        }
        active = true
        self.fullAccess = fullAccess
        self.captureEnabled = captureEnabled
        // Keep a settled empty page on a warm switch. Pasteboard IPC begins in
        // tick, after UIKit has returned from the input-mode handoff.
        checkingInitialPasteboard = fullAccess && captureEnabled && (!reuse || checkingInitialPasteboard)
        loaded = false
        undoAvailable = false
        message = nil
        let generation = self.generation
        if !reuse {
            // A contended or protected database must not hold up category navigation.
            revealCategories = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                guard let self, self.generation == generation, self.entryPhase == .preparing else { return }
                self.entryPhase = .categoriesOnly
            }
        }
        if captureEnabled {
            notification = NotificationCenter.default.addObserver(forName: UIPasteboard.changedNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == generation else { return }
                    // The provider may become readable after a paste prompt while UIKit
                    // still exposes the same (batched) counter to the extension.
                    self.verifiedStamp = nil
                    await self.tick(generation)
                }
            }
        }
        let initial = Task { [weak self] in
            guard let self else { return }
            await self.tick(generation)
        }
        firstRead = initial
        monitor = Task { [weak self] in
            await initial.value
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                await self?.tick(generation)
            }
        }
    }

    // UIKit may still be compositing the outgoing keyboard. End the session now
    // and leave its last presentation intact until the next host is known.
    func suspendForSwitch() {
        active = false
        monitor?.cancel()
        firstRead?.cancel()
        revealCategories?.cancel()
        capture?.cancel()
        if let notification { NotificationCenter.default.removeObserver(notification) }
        notification = nil
        monitor = nil
        firstRead = nil
        revealCategories = nil
        capture = nil
        captureStamp = nil
        generation = UUID()
        failedStamp = nil
        failedAttempts = 0
        verifiedStamp = nil
        revision = -1
        let edit = pendingEdit
        edit?.cancel()
        pendingEdit = nil
        if let store {
            undoCleanup = Task { await edit?.value; try? await store.discardUndo() }
        }
        listGeneration = UUID()
        store = nil
        paging = false
        pageEnd = false
    }

    func stop() {
        suspendForSwitch()
        clearPresentation()
        fullAccess = false
    }

    func finishDisappearance() {
        guard !active else { return }
        if category != ClipCategory.ordinary.id || entryPhase != .history {
            clearPresentation()
        } else if rows.count > 60 {
            rows = Array(rows.prefix(60))
        }
    }

    private func clearPresentation() {
        entryPhase = .preparing
        category = ClipCategory.ordinary.id
        categories = [.ordinary]
        undoAvailable = false
        ordinaryCount = 0
        lastPrune = .distantPast
        loaded = false
        rows = []
        message = nil
        checkingInitialPasteboard = false
    }

    private func tick(_ cycle: UUID) async {
        await undoCleanup?.value
        guard generation == cycle, active else { return }
        if let current = keyboardAccess?(), current != fullAccess {
            start(fullAccess: current, captureEnabled: captureEnabled)
            return
        }
        do {
            if store == nil {
                let connection = try await open(!fullAccess)
                guard generation == cycle else { return }
                // A pasteboard notification can finish opening the session while the timer is awaiting I/O.
                if store == nil { store = connection }
            }
            guard let store else { return }
            if fullAccess, Date().timeIntervalSince(lastPrune) >= 60 {
                try await store.prune()
                guard generation == cycle else { return }
                lastPrune = Date()
            }
            let state = try await refresh(store, cycle: cycle)
            guard generation == cycle, active, fullAccess, captureEnabled else { return }
            let stamp = SystemPasteboard.stamp
            if captureStamp == stamp { return }
            capture?.cancel()
            capture = nil
            captureStamp = nil
            // On first appearance verify the content as well as the counter. UIKit may
            // publish a batched counter update at the end of a foreground event loop.
            if failedStamp == stamp, failedAttempts >= 3 || Date() < retryAfter { return }
            guard state.event?.stamp != stamp || verifiedStamp != stamp else { return }
            captureStamp = stamp
            capture = Task { [weak self] in
                guard let self else { return }
                defer {
                    if self.generation == cycle, self.captureStamp == stamp {
                        if self.checkingInitialPasteboard { self.checkingInitialPasteboard = false }
                        self.capture = nil
                        self.captureStamp = nil
                    }
                }
                do {
                    guard let providers = try SystemPasteboard.providers() else { return }
                    let clip = try await SystemPasteboard.read(providers)
                    try Task.checkCancellation()
                    // A paste prompt may temporarily deactivate the host while an authorized
                    // provider finishes. Entering the background invalidates the generation.
                    guard self.generation == cycle, self.fullAccess, self.keyboardAccess?() != false, SystemPasteboard.stamp == stamp else { return }
                    if clip == nil, UIPasteboard.general.hasImages { throw HistoryError.unreadable }
                    try await store.observe(clip, stamp: stamp, replacing: state.event)
                    guard self.generation == cycle else { return }
                    self.failedStamp = nil
                    self.failedAttempts = 0
                    self.message = nil
                    let committed = try await self.refresh(store, cycle: cycle)
                    if self.generation == cycle, committed.event == PasteEvent(stamp: stamp, key: clip?.key) {
                        self.verifiedStamp = stamp
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard self.generation == cycle, !Task.isCancelled else { return }
                    if case HistoryError.unreadable = error {
                        self.failedAttempts = self.failedStamp == stamp ? self.failedAttempts + 1 : 1
                        self.failedStamp = stamp
                        self.retryAfter = Date().addingTimeInterval(Double(self.failedAttempts))
                    }
                    self.message = error.localizedDescription
                }
            }
        } catch {
            guard generation == cycle, active else { return }
            if !loaded {
                clearPresentation()
                entryPhase = .unavailable
            }
            if fullAccess { message = error.localizedDescription }
        }
    }

    @discardableResult
    private func refresh(_ store: HistoryStore, cycle: UUID) async throws -> HistoryState {
        let list = listGeneration
        let limit = max(60, rows.count)
        let (state, page) = try await store.categoryPage(since: revision, category: category, limit: limit)
        guard generation == cycle, list == listGeneration, state.revision > revision, let page else { return state }
        pageEnd = page.rows.count < limit
        revision = state.revision
        var update = Transaction()
        update.disablesAnimations = true
        withTransaction(update) {
            if categories != page.categories { categories = page.categories }
            if category != page.selected { category = page.selected }
            if undoAvailable != page.canUndo { undoAvailable = page.canUndo }
            if ordinaryCount != page.ordinaryCount { ordinaryCount = page.ordinaryCount }
            if settings != state.settings { settings = state.settings }
            if rows != page.rows { rows = page.rows }
            if entryPhase == .unavailable { message = nil }
            if !loaded { loaded = true }
            if entryPhase != .history { entryPhase = .history }
        }
        revealCategories?.cancel()
        return state
    }

    // A tap on a retained preview waits for the new session's connection. Read
    // bodies from that connection, and abandon the tap if the keyboard changes.
    private func readyStore(_ cycle: UUID) async -> HistoryStore? {
        guard generation == cycle, active else { return nil }
        if !loaded { await firstRead?.value }
        guard generation == cycle, active else { return nil }
        return store
    }

    func thumbnail(_ id: String) async -> Data? {
        let cycle = generation
        guard let store = await readyStore(cycle) else { return nil }
        let data = try? await store.thumbnail(id)
        return generation == cycle && active ? data : nil
    }

    func selectCategory(_ id: String) {
        guard category != id else { return }
        listGeneration = UUID()
        category = id
        rows = []
        entryPhase = .categoriesOnly
        paging = false
        pageEnd = false
        revision = -1
        loaded = false
        let cycle = generation
        Task {
            guard let store = await readyStore(cycle) else { return }
            do { _ = try await refresh(store, cycle: cycle) }
            catch { if generation == cycle { message = error.localizedDescription } }
        }
    }

    func nextPage(after row: ClipRow) async {
        guard row.id == rows.last?.id, !pageEnd, !paging else { return }
        let cycle = generation, list = listGeneration
        guard let store = await readyStore(cycle), list == listGeneration,
              row.id == rows.last?.id, !pageEnd, !paging else { return }
        let startingRevision = revision
        paging = true
        defer { if generation == cycle, list == listGeneration { paging = false } }
        do {
            let page = try await store.page(after: row, category: category)
            guard generation == cycle, list == listGeneration, revision == startingRevision, rows.last?.id == row.id else { return }
            rows.append(contentsOf: page)
            pageEnd = page.count < 60
        } catch { if generation == cycle { message = error.localizedDescription } }
    }

    @discardableResult
    func copy(_ row: ClipRow) async -> Bool {
        let cycle = generation
        guard fullAccess, keyboardAccess?() != false, let store = await readyStore(cycle),
              keyboardAccess?() != false else { return false }
        do {
            try await store.copy(row.id) { try SystemPasteboard.write($0) }
            guard generation == cycle else { return false }
            message = nil
            copied += 1
            try await refresh(store, cycle: cycle)
            return true
        } catch { if generation == cycle { message = error.localizedDescription }; return false }
    }

    func selectInKeyboard(_ row: ClipRow, insert: (String) -> Void, advance: () -> Void) async {
        if row.isImage {
            if await copy(row) { UIAccessibility.post(notification: .announcement, argument: "图片已复制") }
            return
        }
        let cycle = generation
        guard let store = await readyStore(cycle) else { return }
        do {
            let body = try await store.body(row.id)
            let state = try await store.state()
            guard generation == cycle, active, let text = body.text else { return }
            insert(text)
            if state.settings.autoSwitch { advance() }
        } catch { if generation == cycle { message = error.localizedDescription } }
    }

    func edit(_ change: (HistoryStore) async throws -> Void) async {
        guard fullAccess, keyboardAccess?() != false, let store else { return }
        let cycle = generation
        do {
            try await change(store)
            try await refresh(store, cycle: cycle)
        } catch { if generation == cycle { message = error.localizedDescription } }
    }

    // Enqueue taps in delivery order (including Undo). A hidden keyboard abandons queued work.
    func enqueue(_ change: @escaping (HistoryStore) async throws -> Void) {
        guard active, fullAccess, keyboardAccess?() != false else { return }
        let cycle = generation
        let previous = pendingEdit
        pendingEdit = Task {
            await previous?.value
            guard !Task.isCancelled, let store = await readyStore(cycle), !Task.isCancelled,
                  keyboardAccess?() != false else { return }
            do {
                try await change(store)
                guard generation == cycle else { return }
                message = nil
                try await refresh(store, cycle: cycle)
            } catch { if generation == cycle { message = error.localizedDescription } }
        }
    }

    func perform(_ action: HistoryAction) { enqueue { try await $0.organize(action) } }
    func undo() { enqueue { try await $0.undoOrganization() } }
    func report(_ error: Error) { message = error.localizedDescription }

}
