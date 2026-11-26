import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private lazy var session = ClipboardSession(keyboardAccess: { [weak self] in self?.hasFullAccess ?? false })
    private let globe = UIButton(type: .system)
    private let returnKey = UIButton(type: .system)
    private let commands = UIStackView()
    private let settingsSpacer = UIView()
    private let presentation = KeyboardPresentation()
    private var visible = false

    override func viewDidLoad() {
        super.viewDidLoad()
        let history = KeyboardHistory(session: session, presentation: presentation) { [weak self] row in
            guard let self else { return }
            Task {
                if row.isImage && !self.hasFullAccess { return }
                await self.session.selectInKeyboard(row, insert: { self.textDocumentProxy.insertText($0) },
                                                   advance: { self.advanceToNextInputMode() })
            }
        }
        let host = UIHostingController(rootView: history)
        addChild(host)
        host.view.backgroundColor = .clear

        let space = UIButton(type: .system)
        let erase = UIButton(type: .system)
        configure(globe, symbol: "globe", label: "切换键盘", id: "nextKeyboard")
        configure(space, title: "空格", label: "空格", id: "keyboardSpace")
        configure(erase, symbol: "delete.left", label: "退格", id: "keyboardBackspace")
        configure(returnKey, title: "换行", label: "换行", id: "keyboardReturn")
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        space.addAction(UIAction { [weak self] _ in self?.textDocumentProxy.insertText(" ") }, for: .touchUpInside)
        erase.addAction(UIAction { [weak self] _ in self?.textDocumentProxy.deleteBackward() }, for: .touchUpInside)
        returnKey.addAction(UIAction { [weak self] _ in self?.textDocumentProxy.insertText("\n") }, for: .touchUpInside)
        globe.isHidden = !needsInputModeSwitchKey

        settingsSpacer.isHidden = true
        [globe, space, erase, returnKey, settingsSpacer].forEach { commands.addArrangedSubview($0) }
        commands.spacing = 6
        let column = UIStackView(arrangedSubviews: [host.view, commands])
        column.axis = .vertical
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = KeyboardPalette.tray
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 6),
            column.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -6),
            column.topAnchor.constraint(equalTo: view.topAnchor),
            column.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -5)
        ])
        for (key, width) in [(globe, CGFloat(48)), (erase, 54), (returnKey, 84)] {
            let constraint = key.widthAnchor.constraint(equalToConstant: width)
            constraint.priority = .defaultHigh
            constraint.isActive = true
        }
        let commandHeight = commands.heightAnchor.constraint(equalToConstant: 45)
        commandHeight.priority = .defaultHigh
        commandHeight.isActive = true
        host.didMove(toParent: self)
        NotificationCenter.default.addObserver(self, selector: #selector(hostBackground),
                                               name: .NSExtensionHostDidEnterBackground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hostInactive),
                                               name: .NSExtensionHostWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hostActive),
                                               name: .NSExtensionHostDidBecomeActive, object: nil)
    }

    private func configure(_ button: UIButton, title: String? = nil, symbol: String? = nil, label: String, id: String) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = symbol.flatMap { UIImage(systemName: $0) }
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        config.baseForegroundColor = .label
        config.cornerStyle = .fixed
        config.background.cornerRadius = 8
        config.background.backgroundColor = KeyboardPalette.key
        button.configuration = config
        button.configurationUpdateHandler = { key in
            key.configuration?.background.backgroundColor = key.isHighlighted ? KeyboardPalette.pressed : KeyboardPalette.key
        }
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.18
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowRadius = 0
        button.accessibilityLabel = label
        button.accessibilityIdentifier = id
    }

    private func updateReturnKey() {
        let title: String
        switch textDocumentProxy.returnKeyType ?? .default {
        case .done: title = "完成"
        case .send: title = "发送"
        case .search, .google, .yahoo: title = "搜索"
        case .go: title = "前往"
        case .next: title = "下一项"
        case .join: title = "加入"
        case .continue: title = "继续"
        default: title = "换行"
        }
        if returnKey.configuration?.title != title {
            returnKey.configuration?.title = title
            returnKey.accessibilityLabel = title
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateReturnKey()
        if visible && session.active { hostActive() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        visible = true
        updateReturnKey()
        hostActive()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hostActive()
    }
    override func viewWillDisappear(_ animated: Bool) {
        visible = false
        session.active = false
        super.viewWillDisappear(animated)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // UIKit can still show the outgoing hierarchy during its input-mode transition.
        if !visible { session.stop() }
    }
    @objc private func hostActive() {
        guard visible else { return }
        let proxy = textDocumentProxy
        let type: UITextContentType? = proxy.textContentType ?? nil
        let settings = type?.rawValue == ClipboardInputMode.settingsContext ||
            (proxy.returnKeyType == .join && proxy.autocorrectionType == .no &&
             proxy.selectedText == ClipboardInputMode.settingsContext)
        if presentation.settings != settings {
            presentation.settings = settings
            // Leave the globe available on devices where UIKit asks the extension to supply it.
            for key in commands.arrangedSubviews where key !== globe && key !== settingsSpacer { key.isHidden = settings }
            settingsSpacer.isHidden = !settings
        }
        let hideGlobe = !needsInputModeSwitchKey
        if globe.isHidden != hideGlobe { globe.isHidden = hideGlobe }
        let hideCommands = settings && hideGlobe
        if commands.isHidden != hideCommands { commands.isHidden = hideCommands }
        session.start(fullAccess: hasFullAccess, captureEnabled: !settings)
    }
    @objc private func hostInactive() { session.active = false }
    @objc private func hostBackground() { session.stop() }
}
