import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private lazy var session = ClipboardSession(keyboardAccess: { [weak self] in self?.hasFullAccess ?? false })
    private let globe = UIButton(type: .system)
    private var height: NSLayoutConstraint?
    private var visible = false

    override func viewDidLoad() {
        super.viewDidLoad()
        let list = KeyboardHistory(session: session) { [weak self] row in
            guard let self else { return }
            Task {
                if row.isImage && !self.hasFullAccess { return }
                await self.session.selectInKeyboard(row, insert: { self.textDocumentProxy.insertText($0) },
                                                    advance: { self.advanceToNextInputMode() })
            }
        }
        let host = UIHostingController(rootView: list)
        addChild(host)
        host.view.backgroundColor = .clear
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.tintColor = .label
        globe.accessibilityLabel = "切换键盘"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let switchRow = UIStackView(arrangedSubviews: [globe, UIView()])
        switchRow.isHidden = !needsInputModeSwitchKey
        let column = UIStackView(arrangedSubviews: [host.view, switchRow])
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            column.topAnchor.constraint(equalTo: view.topAnchor),
            column.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            globe.widthAnchor.constraint(equalToConstant: 52)
        ])
        let globeHeight = globe.heightAnchor.constraint(equalToConstant: 44)
        globeHeight.priority = .defaultHigh
        globeHeight.isActive = true
        height = view.heightAnchor.constraint(equalToConstant: 252)
        height?.priority = UILayoutPriority(999)
        height?.isActive = true
        host.didMove(toParent: self)
        NotificationCenter.default.addObserver(self, selector: #selector(hostBackground),
                                                name: .NSExtensionHostDidEnterBackground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hostInactive),
                                                name: .NSExtensionHostWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hostActive),
                                                name: .NSExtensionHostDidBecomeActive, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        hostActive()
    }

    override func viewWillDisappear(_ animated: Bool) {
        visible = false
        session.stop()
        super.viewWillDisappear(animated)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        globe.superview?.isHidden = !needsInputModeSwitchKey
        height?.constant = traitCollection.verticalSizeClass == .compact ? 178 : 252
    }

    @objc private func hostActive() {
        if visible { session.start(.keyboard(fullAccess: hasFullAccess)) }
    }
    @objc private func hostInactive() { session.active = false }
    @objc private func hostBackground() { session.stop() }
}

private struct KeyboardHistory: View {
    @ObservedObject var session: ClipboardSession
    let select: (ClipRow) -> Void
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !session.mode.mayWrite {
                Text("在系统键盘设置中允许完全访问，以收集剪贴板和复制图片。")
                    .font(.footnote).foregroundStyle(.secondary).padding(8)
            } else if let message = session.message {
                Text(message).font(.footnote).foregroundStyle(.secondary).padding(8)
            } else if showCopied {
                Text("图片已复制，可在输入框中粘贴").font(.footnote).padding(8)
            }
            if session.rows.isEmpty {
                Text("暂无历史记录").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(session.rows) { row in
                    Button { select(row) } label: { ClipLabel(row: row, session: session, compact: true) }
                        .buttonStyle(.plain)
                        .disabled(row.isImage && !session.mode.mayWrite)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .task { await session.nextPage(after: row) }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .task(id: session.copied) {
            guard session.copied > 0 else { return }
            showCopied = true
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { showCopied = false }
        }
    }
}
