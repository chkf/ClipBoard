import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var keyboardFeedback: @MainActor () -> Void = {}
}

@MainActor final class KeyboardPresentation: ObservableObject {
    static let hapticsPreference = "KeyboardHapticsEnabled"
    @Published var settings = false
    @Published var categoryRequest: CategoryRequest?
    @Published var heightOffset = 0
    @Published var needsGlobe = false
    @Published var appearanceID = UUID()
}

/// The same candidate measures its natural width in both presentations.
struct CategoryButton: UIViewRepresentable {
    let category: ClipCategory
    let selected: Bool
    let expanded: Bool
    let fontSize: CGFloat
    let height: CGFloat
    let maximumWidth: CGFloat
    let choose: () -> Void
    let manage: () -> Void

    final class Coordinator: NSObject {
        var owner: CategoryButton
        init(_ owner: CategoryButton) { self.owner = owner }
        @objc func tapped() { owner.choose() }
        @objc func held(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began { owner.manage() }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        let handler = context.coordinator
        button.addTarget(handler, action: #selector(Coordinator.tapped), for: .touchUpInside)
        button.addGestureRecognizer(UILongPressGestureRecognizer(target: handler, action: #selector(Coordinator.held(_:))))
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 9, bottom: 0, right: 9)
        button.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "历史操作") { [weak handler] _ in
            guard let handler else { return false }
            handler.owner.manage()
            return true
        }]
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.owner = self
        button.setTitle(category.name, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: fontSize, weight: selected ? .medium : .regular)
        button.titleLabel?.numberOfLines = expanded ? 0 : 1
        button.titleLabel?.lineBreakMode = expanded ? .byCharWrapping : .byTruncatingTail
        button.titleLabel?.textAlignment = .center
        button.setTitleColor(selected ? .label : .label.withAlphaComponent(0.88), for: .normal)
        button.accessibilityLabel = category.name
        button.accessibilityHint = "长按打开历史操作"
        button.accessibilityTraits = selected ? [.button, .selected] : .button
        button.accessibilityIdentifier = (expanded ? "folder-" : "tab-") + (category.id.isEmpty ? "ordinary" : category.id)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        let title = category.name as NSString
        let font = UIFont.systemFont(ofSize: fontSize, weight: selected ? .medium : .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let limit = max(1, min(maximumWidth, proposal.width ?? maximumWidth))
        let width = min(limit, max(44, ceil(title.size(withAttributes: attributes).width) + 18))
        guard expanded else { return CGSize(width: width, height: height) }
        let text = title.boundingRect(with: CGSize(width: max(1, width - 18), height: .greatestFiniteMagnitude),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        return CGSize(width: width, height: max(height, ceil(text.height) + 6))
    }
}

struct CategoryFlow: Layout {
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width + 0.01 {
                y += rowHeight
                x = 0
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + 1
            rowHeight = max(rowHeight, size.height)
        }
        return (frames, y + rowHeight)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(1, proposal.width ?? subviews.first?.sizeThatFits(.unspecified).width ?? 1)
        return CGSize(width: width, height: arrange(subviews, width: width).height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, arrange(subviews, width: max(1, bounds.width)).frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(frame.size))
        }
    }
}

/// UIKit owns the whole row's hit region, including the blank area after a short label.
struct HistoryRowButton: UIViewRepresentable {
    let row: ClipRow
    let enabled: Bool
    let select: () -> Void

    final class Coordinator {
        var select: () -> Void
        init(_ select: @escaping () -> Void) { self.select = select }
    }
    final class HitButton: UIButton {
        override var isHighlighted: Bool {
            didSet { backgroundColor = UIColor.label.withAlphaComponent(isHighlighted ? 0.08 : 0.015) }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(select) }
    func makeUIView(context: Context) -> UIButton {
        let button = HitButton(type: .custom)
        button.backgroundColor = UIColor.label.withAlphaComponent(0.015)
        button.accessibilityIdentifier = "historyKey"
        button.addAction(UIAction { [weak coordinator = context.coordinator] _ in coordinator?.select() }, for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.select = select
        button.isEnabled = enabled
        button.accessibilityLabel = row.isImage ? "图片" : row.preview
        button.accessibilityValue = row.isPinned ? "已置顶" : nil
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

struct HistoryRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.primary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.08 : 0.015))
            .contentShape(Rectangle())
    }
}

struct SystemGlobe: UIViewRepresentable {
    let install: (UIButton) -> Void
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = "切换输入法"
        button.accessibilityHint = "轻点切到下一个键盘，长按选择系统键盘或表情符号。"
        button.accessibilityIdentifier = "nextKeyboard"
        install(button)
        return button
    }
    func updateUIView(_ view: UIButton, context: Context) {}
}

struct CategoryDisclosure: UIViewRepresentable {
    let expanded: Bool
    let toggle: () -> Void

    final class Coordinator {
        var toggle: () -> Void
        init(_ toggle: @escaping () -> Void) { self.toggle = toggle }
    }
    func makeCoordinator() -> Coordinator { Coordinator(toggle) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.tintColor = .label
        button.accessibilityIdentifier = "expandCategories"
        button.addAction(UIAction { [weak coordinator = context.coordinator] _ in coordinator?.toggle() }, for: .primaryActionTriggered)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.toggle = toggle
        button.accessibilityLabel = expanded ? "收起分类" : "展开全部分类"
        let symbol = expanded ? "chevron.up" : "chevron.down"
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)), for: .normal)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}
