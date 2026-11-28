import SwiftUI
import UIKit

private final class HistoryInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }

    var panelHeight: CGFloat = 243 {
        didSet { if oldValue != panelHeight { invalidateIntrinsicContentSize() } }
    }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: panelHeight) }
    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        CGSize(width: super.systemLayoutSizeFitting(targetSize).width, height: panelHeight)
    }
}

final class KeyboardViewController: UIInputViewController {
    private lazy var session = ClipboardSession(keyboardAccess: { [weak self] in self?.hasFullAccess ?? false })
    private let presentation = KeyboardPresentation()
    private let surface = UIView()
    private lazy var keyImpact = UIImpactFeedbackGenerator(style: .light, view: view)
    private var rootHeight: NSLayoutConstraint?
    private var surfaceHeight: NSLayoutConstraint?
    private var visible = false
    private var spaceNameTimeout: Task<Void, Never>?
    private var layoutWidth: CGFloat = 0
    private var applyingCategory = false

    private var heightKey: String {
        traitCollection.verticalSizeClass == .compact ? "KeyboardHeight.landscape" : "KeyboardHeight.portrait"
    }
    private func height(for width: CGFloat) -> CGFloat {
        let base: CGFloat
        if traitCollection.verticalSizeClass == .compact { base = 162 }
        else if traitCollection.userInterfaceIdiom == .pad { base = 264 }
        else { base = min(266, max(220, (243 + (width - 402) / 3).rounded())) }
        return base + CGFloat(UserDefaults.standard.integer(forKey: heightKey))
    }

    override func loadView() {
        // The remote view can momentarily cover more than the keyboard during the handoff.
        let width = UIScreen.main.bounds.width
        let target = height(for: width)
        let panel = HistoryInputView(frame: CGRect(x: 0, y: 0, width: width, height: target), inputViewStyle: .keyboard)
        panel.allowsSelfSizing = true
        panel.panelHeight = target
        panel.isOpaque = false
        panel.clipsToBounds = true
        inputView = panel
        preferredContentSize = CGSize(width: 0, height: target)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let keyboard = KeyboardHistory(session: session, presentation: presentation,
            select: { [weak self] row in
                guard let self else { return }
                Task {
                    await self.session.selectInKeyboard(row, insert: { self.textDocumentProxy.insertText($0) },
                                                        advance: { self.advanceToNextInputMode() })
                    self.updateTraits()
                }
            },
            insert: { [weak self] text in self?.textDocumentProxy.insertText(text); self?.updateTraits() },
            erase: { [weak self] in self?.textDocumentProxy.deleteBackward(); self?.updateTraits() },
            moveCursor: { [weak self] offset in self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset) },
            applyCategory: { [weak self] request in self?.applyCategory(request) },
            adjustHeight: { [weak self] delta in self?.adjustHeight(delta) },
            globe: { [weak self] button in
                if let self { button.addTarget(self, action: #selector(self.handleInputModeList(from:with:)), for: .allTouchEvents) }
            })
        let host = UIHostingController(rootView: keyboard.environment(\.keyboardFeedback, { [weak self] in
            self?.playKeyFeedback()
        }))
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = true
        host.view.translatesAutoresizingMaskIntoConstraints = false
        surface.backgroundColor = .clear
        surface.clipsToBounds = true
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)
        surface.addSubview(host.view)
        let requested = view.heightAnchor.constraint(equalToConstant: preferredContentSize.height)
        requested.priority = UILayoutPriority(999)
        let measured = surface.heightAnchor.constraint(equalToConstant: preferredContentSize.height)
        rootHeight = requested
        surfaceHeight = measured
        NSLayoutConstraint.activate([
            requested, measured, surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor), surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: surface.topAnchor), host.view.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
        host.didMove(toParent: self)
        registerForTraitChanges([UITraitVerticalSizeClass.self, UITraitHorizontalSizeClass.self]) {
            (controller: KeyboardViewController, _: UITraitCollection) in controller.updateHeight()
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(hostBackground), name: .NSExtensionHostDidEnterBackground, object: nil)
        center.addObserver(self, selector: #selector(hostInactive), name: .NSExtensionHostWillResignActive, object: nil)
        center.addObserver(self, selector: #selector(hostActive), name: .NSExtensionHostDidBecomeActive, object: nil)
    }

    private func applyCategory(_ request: CategoryRequest) {
        guard !applyingCategory, visible, hasFullAccess, let store = session.store,
              CategoryRequest.decode(textDocumentProxy.selectedText) == request else { return }
        let document = textDocumentProxy.documentIdentifier
        applyingCategory = true
        Task {
            defer { applyingCategory = false }
            do {
                try await store.applyCategory(request)
                guard visible, textDocumentProxy.documentIdentifier == document,
                      CategoryRequest.decode(textDocumentProxy.selectedText) == request else { return }
                textDocumentProxy.insertText(request.receipt)
            } catch { session.report(error) }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if view.bounds.width > 0, view.bounds.width != layoutWidth {
            layoutWidth = view.bounds.width
            updateHeight()
        }
    }
    private func adjustHeight(_ delta: Int?) {
        let value = delta.map { min(48, max(-48, UserDefaults.standard.integer(forKey: heightKey) + $0)) } ?? 0
        UserDefaults.standard.set(value, forKey: heightKey)
        updateHeight()
    }
    private func updateHeight() {
        let offset = UserDefaults.standard.integer(forKey: heightKey)
        if presentation.heightOffset != offset { presentation.heightOffset = offset }
        let target = height(for: layoutWidth > 0 ? layoutWidth : UIScreen.main.bounds.width)
        guard target != surfaceHeight?.constant else { return }
        rootHeight?.constant = target
        surfaceHeight?.constant = target
        (view as? HistoryInputView)?.panelHeight = target
        preferredContentSize = CGSize(width: 0, height: target)
    }
    private func updateTraits() {
        let proxy = textDocumentProxy
        let key = HostReturnKey(proxy.returnKeyType ?? .default,
                                enabled: proxy.enablesReturnKeyAutomatically != true || proxy.hasText)
        if presentation.returnKey != key { presentation.returnKey = key }
        let style: UIUserInterfaceStyle
        switch proxy.keyboardAppearance ?? .default {
        case .dark: style = .dark
        case .light: style = .light
        default: style = .unspecified
        }
        if overrideUserInterfaceStyle != style { overrideUserInterfaceStyle = style }
        if presentation.needsGlobe != needsInputModeSwitchKey { presentation.needsGlobe = needsInputModeSwitchKey }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if visible { updateTraits(); if session.active { hostActive() } }
    }
    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        DispatchQueue.main.async { [weak self] in
            if let self, self.visible, self.session.active { self.hostActive() }
        }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !visible { presentation.showsInputModeName = true }
        visible = true
        updateHeight()
        hostActive()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if hapticsEnabled { keyImpact.prepare() }
        hostActive()
        if presentation.showsInputModeName, spaceNameTimeout == nil {
            spaceNameTimeout = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1150))
                guard !Task.isCancelled, let self else { return }
                self.presentation.showsInputModeName = false
                self.spaceNameTimeout = nil
            }
        }
    }

    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: KeyboardPresentation.hapticsPreference) as? Bool ?? true
    }
    private func playKeyFeedback() {
        UIDevice.current.playInputClick()
        if hapticsEnabled {
            keyImpact.impactOccurred()
            keyImpact.prepare()
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        visible = false
        spaceNameTimeout?.cancel()
        spaceNameTimeout = nil
        session.suspendForSwitch()
        super.viewWillDisappear(animated)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !visible else { return }
        session.finishDisappearance()
        presentation.appearanceID = UUID()
        presentation.categoryRequest = nil
        presentation.settings = false
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        if !visible { session.stop() }
    }
    @objc private func hostActive() {
        guard visible else { return }
        let proxy = textDocumentProxy
        let type: UITextContentType? = proxy.textContentType ?? nil
        let commandField = type?.rawValue == CategoryRequest.context ||
            (proxy.returnKeyType == .join && proxy.autocorrectionType == .no && proxy.selectedText?.hasPrefix(CategoryRequest.context + ":") == true)
        let request = commandField ? CategoryRequest.decode(proxy.selectedText) : nil
        if presentation.categoryRequest != request { presentation.categoryRequest = request }
        let settings = type?.rawValue == ClipboardInputMode.settingsContext ||
            (proxy.returnKeyType == .join && proxy.autocorrectionType == .no && proxy.selectedText == ClipboardInputMode.settingsContext)
        if presentation.settings != settings { presentation.settings = settings }
        updateTraits()
        session.start(fullAccess: hasFullAccess, captureEnabled: !settings && !commandField)
    }
    @objc private func hostInactive() { session.active = false }
    @objc private func hostBackground() { session.stop(); presentation.appearanceID = UUID() }
}
