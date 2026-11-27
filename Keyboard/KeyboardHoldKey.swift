import SwiftUI
import UIKit

/// A single control owns the tap and hold, so a completed hold never also emits a keystroke.
struct KeyboardHoldKey: UIViewRepresentable {
    let label: String
    let id: String
    var symbol: String?
    var holdLabel: String
    let tap: () -> Void
    let hold: () -> Void
    var moveCursor: ((Int) -> Void)?
    @Environment(\.keyboardFeedback) private var feedback

    init(_ label: String, id: String, symbol: String? = nil, holdLabel: String, tap: @escaping () -> Void,
         hold: @escaping () -> Void, moveCursor: ((Int) -> Void)? = nil) {
        self.label = label; self.id = id; self.symbol = symbol; self.holdLabel = holdLabel
        self.tap = tap; self.hold = hold; self.moveCursor = moveCursor
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
        key.addGestureRecognizer(press)
        key.accessibilityCustomActions = [UIAccessibilityCustomAction(name: holdLabel) { [weak handler] _ in
            guard let handler else { return false }; handler.owner.feedback(); handler.owner.hold(); return true
        }]
        return key
    }
    func updateUIView(_ uiView: UIButton, context: Context) { context.coordinator.owner = self }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    @MainActor final class Coordinator: NSObject {
        var owner: KeyboardHoldKey
        private var held = false
        private var anchor: CGFloat = 0
        init(_ owner: KeyboardHoldKey) { self.owner = owner }
        @objc func down(_ sender: UIButton) { held = false; sender.backgroundColor = KeyboardPalette.pressed }
        @objc func cancel(_ sender: UIButton) { sender.backgroundColor = KeyboardPalette.key }
        @objc func tap(_ sender: UIButton) {
            sender.backgroundColor = KeyboardPalette.key
            guard !held else { return }
            owner.feedback(); owner.tap()
        }
        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            let x = gesture.location(in: gesture.view).x
            switch gesture.state {
            case .began:
                held = true; anchor = x; owner.feedback(); owner.hold()
            case .changed:
                guard let move = owner.moveCursor else { return }
                let stride: CGFloat = 8
                let offset = Int((x - anchor) / stride)
                if offset != 0 { anchor += CGFloat(offset) * stride; move(offset) }
            case .ended, .cancelled, .failed:
                gesture.view?.backgroundColor = KeyboardPalette.key
            default: break
            }
        }
    }
}
