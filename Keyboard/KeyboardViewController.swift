import SwiftUI
import UIKit

private final class HistoryInputView: UIInputView {
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
    private var rootHeight: NSLayoutConstraint?
    private var surfaceHeight: NSLayoutConstraint?
    private var visible = false
    private var layoutWidth: CGFloat = 0

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
        let panel = HistoryInputView(frame: CGRect(x: 0, y: 0, width: width, height: target), inputViewStyle: .default)
        panel.allowsSelfSizing = true
        panel.panelHeight = target
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.clipsToBounds = true
        view = panel
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
            selectedText: { [weak self] in self?.textDocumentProxy.selectedText },
            adjustHeight: { [weak self] delta in self?.adjustHeight(delta) },
            globe: { [weak self] button in
                if let self { button.addTarget(self, action: #selector(self.handleInputModeList(from:with:)), for: .allTouchEvents) }
            })
        let host = UIHostingController(rootView: keyboard)
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = true
        host.view.translatesAutoresizingMaskIntoConstraints = false
        surface.backgroundColor = KeyboardPalette.tray
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
        visible = true
        updateHeight()
        hostActive()
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); hostActive() }
    override func viewWillDisappear(_ animated: Bool) {
        visible = false
        session.active = false
        super.viewWillDisappear(animated)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !visible {
            session.stop(); presentation.page = .history
        }
    }
    @objc private func hostActive() {
        guard visible else { return }
        let proxy = textDocumentProxy
        let type: UITextContentType? = proxy.textContentType ?? nil
        let settings = type?.rawValue == ClipboardInputMode.settingsContext ||
            (proxy.returnKeyType == .join && proxy.autocorrectionType == .no && proxy.selectedText == ClipboardInputMode.settingsContext)
        if presentation.settings != settings { presentation.settings = settings }
        updateTraits()
        session.start(fullAccess: hasFullAccess, captureEnabled: !settings)
    }
    @objc private func hostInactive() { session.active = false }
    @objc private func hostBackground() { session.stop() }
}
