import SwiftUI
import UIKit

/// A single control owns the tap and hold, so a completed hold never also emits a keystroke.
struct KeyboardHoldKey: UIViewRepresentable {
    let label: String
    let id: String
    var symbol: String?
    var holdLabel: String?
    let tap: () -> Void
    let hold: () -> Void
    var repeatsOnHold: Bool
    var moveCursor: ((Int) -> Void)?
    @Environment(\.keyboardFeedback) private var feedback
    @Environment(\.isEnabled) private var isEnabled

    init(_ label: String, id: String, symbol: String? = nil, holdLabel: String? = nil, tap: @escaping () -> Void,
         hold: @escaping () -> Void, repeatsOnHold: Bool = false, moveCursor: ((Int) -> Void)? = nil) {
        self.label = label; self.id = id; self.symbol = symbol; self.holdLabel = holdLabel
        self.tap = tap; self.hold = hold; self.repeatsOnHold = repeatsOnHold; self.moveCursor = moveCursor
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIButton {
        let key = UIButton(type: .custom)
        key.setImage(symbol.flatMap { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)) }, for: .normal)
        key.tintColor = .label
        key.layer.cornerRadius = 8
        key.layer.cornerCurve = .continuous
        key.backgroundColor = KeyboardPalette.key
        key.accessibilityLabel = label
        key.accessibilityIdentifier = id
        let handler = context.coordinator
        key.addTarget(handler, action: #selector(Coordinator.down), for: .touchDown)
        key.addTarget(handler, action: #selector(Coordinator.tap), for: .touchUpInside)
        key.addTarget(handler, action: #selector(Coordinator.cancel), for: [.touchCancel,.touchUpOutside])
        let press = UILongPressGestureRecognizer(target: handler, action: #selector(Coordinator.longPress(_:)))
        press.minimumPressDuration = 0.42
        press.cancelsTouchesInView = false
        key.addGestureRecognizer(press)
        if let holdLabel {
            key.accessibilityCustomActions = [UIAccessibilityCustomAction(name: holdLabel) { [weak handler] _ in
                guard let handler, handler.owner.isEnabled else { return false }
                handler.owner.feedback(); handler.owner.hold(); return true
            }]
        } else if repeatsOnHold {
            key.accessibilityHint = "按住连续退格"
        }
        return key
    }
    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.owner = self
        uiView.isEnabled = isEnabled
        uiView.tintColor = isEnabled ? .label : .tertiaryLabel
        if !isEnabled { context.coordinator.stopRepeating() }
    }
    static func dismantleUIView(_ uiView: UIButton, coordinator: Coordinator) { coordinator.stopRepeating() }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    @MainActor final class Coordinator: NSObject {
        var owner: KeyboardHoldKey
        private var held = false
        private var anchor: CGFloat = 0
        private var repeating: Task<Void, Never>?
        init(_ owner: KeyboardHoldKey) { self.owner = owner }
        func stopRepeating() { repeating?.cancel(); repeating = nil }
        @objc func down(_ sender: UIButton) { stopRepeating(); held = false; sender.backgroundColor = KeyboardPalette.pressed }
        @objc func cancel(_ sender: UIButton) { stopRepeating(); sender.backgroundColor = KeyboardPalette.key }
        @objc func tap(_ sender: UIButton) {
            cancel(sender)
            guard !held else { return }
            owner.feedback(); owner.tap()
        }
        private func repeatWhilePressed(_ gesture: UILongPressGestureRecognizer) {
            repeating = Task { [weak self, weak gesture] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(85)) } catch { return }
                    guard let self, let gesture, let button = gesture.view as? UIButton, button.window != nil,
                          button.isEnabled, gesture.state == .began || gesture.state == .changed,
                          button.bounds.contains(gesture.location(in: button)) else { return }
                    self.owner.hold()
                }
            }
        }
        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            let x = gesture.location(in: gesture.view).x
            switch gesture.state {
            case .began:
                guard owner.isEnabled else { return }
                held = true; anchor = x; owner.feedback(); owner.hold()
                if owner.repeatsOnHold { repeatWhilePressed(gesture) }
            case .changed:
                if owner.repeatsOnHold, let key = gesture.view, !key.bounds.contains(gesture.location(in: key)) {
                    stopRepeating()
                }
                guard let move = owner.moveCursor else { return }
                let stride: CGFloat = 8
                let offset = Int((x - anchor) / stride)
                if offset != 0 { anchor += CGFloat(offset) * stride; move(offset) }
            case .ended, .cancelled, .failed:
                stopRepeating()
                gesture.view?.backgroundColor = KeyboardPalette.key
            default: break
            }
        }
    }
}
