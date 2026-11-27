import SwiftUI
import UIKit

// A separate simulator app supplies real inter-app pasteboard events and a keyboard host.
@main
struct FixtureApp: App {
    @State private var input = ""
    @State private var copyStatus = ""
    @State private var measure = false
    var body: some Scene {
        WindowGroup {
            VStack {
                Button("Copy text") {
                    let board = UIPasteboard.general
                    let value = "Clipboard UI fixture\nsecond line\nthird line"
                    let before = board.changeCount
                    board.setItems([["public.utf8-plain-text": value]], options: [.localOnly: true])
                    confirmWrite("Text copied", after: before) { board.string == value }
                }
                Button("Copy image") {
                    let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 36)).image { ctx in
                        UIColor.orange.setFill()
                        ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 36))
                    }
                    let board = UIPasteboard.general
                    let data = image.pngData()!
                    let before = board.changeCount
                    board.setItems([["public.png": data]], options: [.localOnly: true])
                    confirmWrite("Image copied", after: before) { board.data(forPasteboardType: "public.png") == data }
                }
                Button("Copy second") {
                    let board = UIPasteboard.general
                    let before = board.changeCount
                    board.setItems([["public.utf8-plain-text": "短句"]], options: [.localOnly: true])
                    confirmWrite("Second copied", after: before) { board.string == "短句" }
                }
                Button("Check clipboard image") {
                    copyStatus = UIPasteboard.general.hasImages ? "Image still on clipboard" : "Image missing"
                }
                Text(verbatim: copyStatus).accessibilityIdentifier("copyStatus")
                if ProcessInfo.processInfo.arguments.contains("-MeasureKeyboardSwitch") {
                    Button(measure ? "Finish measurement" : "Track keyboard") { measure.toggle() }
                    KeyboardFrameProbe(measure: measure).frame(width: 2, height: 2)
                        .accessibilityIdentifier("keyboardTravel")
                }
                if ProcessInfo.processInfo.arguments.contains("-EmptySearch") {
                    EmptySearchField().frame(height: 40)
                } else {
                    KeyboardField(text: $input, trackingSwitch: measure).frame(height: 100).border(.secondary)
                }
                Text(verbatim: input).accessibilityIdentifier("inserted")
            }
            .padding()
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if measure {
                    // Identify the measured handoff in the simulator's screen recording.
                    Color(red: 1, green: 0, blue: 1).frame(width: 54, height: 8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
    }

    private func confirmWrite(_ success: String, after previousCount: Int, matches: @escaping () -> Bool) {
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(3)
            while UIPasteboard.general.changeCount == previousCount, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(30))
            }
            copyStatus = UIPasteboard.general.changeCount != previousCount && matches() ? success : "Write failed"
        }
    }
}

private struct KeyboardField: UIViewRepresentable {
    @Binding var text: String
    let trackingSwitch: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> FixtureTextView {
        let view = FixtureTextView()
        view.accessibilityIdentifier = "input"
        view.delegate = context.coordinator
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-ReturnKey"), arguments.indices.contains(flag + 1) {
            switch arguments[flag + 1] {
            case "Search": view.returnKeyType = .search
            case "Send": view.returnKeyType = .send
            case "Done": view.returnKeyType = .done
            default: view.returnKeyType = .default
            }
            view.enablesReturnKeyAutomatically = true
            view.text = "sample"
        }
        return view
    }
    func updateUIView(_ view: FixtureTextView, context: Context) {
        view.trackingSwitch = trackingSwitch
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let field: KeyboardField
        init(_ field: KeyboardField) { self.field = field }
        func textViewDidChange(_ textView: UITextView) { field.text = textView.text }
    }
}

@MainActor private func fixtureInputMode() -> UITextInputMode? {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("-MeasureKeyboardSwitch") || arguments.contains("-SystemKeyboard") {
        return UITextInputMode.activeInputModes.first { $0.primaryLanguage?.hasPrefix("en") == true }
    }
    return ClipboardInputMode.enabled
}

private final class FixtureTextView: UITextView {
    var trackingSwitch = false
    override var textInputMode: UITextInputMode? {
        trackingSwitch ? super.textInputMode : (fixtureInputMode() ?? super.textInputMode)
    }
}

private struct EmptySearchField: UIViewRepresentable {
    final class Field: UISearchTextField {
        override var textInputMode: UITextInputMode? { fixtureInputMode() ?? super.textInputMode }
    }
    func makeUIView(context: Context) -> Field {
        let field = Field()
        field.accessibilityIdentifier = "searchInput"
        field.placeholder = "Search"
        field.returnKeyType = .search
        field.enablesReturnKeyAutomatically = true
        return field
    }
    func updateUIView(_ field: Field, context: Context) {}
}

private struct KeyboardFrameProbe: UIViewRepresentable {
    let measure: Bool
    func makeUIView(context: Context) -> FrameView { FrameView() }
    func updateUIView(_ view: FrameView, context: Context) { if measure { view.begin() } }
    static func dismantleUIView(_ view: FrameView, coordinator: ()) { view.end() }

    final class FrameView: UIView {
        private let marker = UIView()
        private var display: CADisplayLink?
        private var first: CGFloat?
        private var last: CGFloat = 0
        private var travel: CGFloat = 0
        private var samples = 0
        private var turns: [Int] = []

        func begin() {
            guard display == nil, let owner = window?.rootViewController?.view else { return }
            isAccessibilityElement = true
            accessibilityIdentifier = "keyboardTravel"
            // Follow the presentation layer so the probe sees motion between layout passes.
            marker.isUserInteractionEnabled = false
            marker.translatesAutoresizingMaskIntoConstraints = false
            owner.addSubview(marker)
            NSLayoutConstraint.activate([
                marker.topAnchor.constraint(equalTo: owner.keyboardLayoutGuide.topAnchor),
                marker.leadingAnchor.constraint(equalTo: owner.leadingAnchor),
                marker.heightAnchor.constraint(equalToConstant: 1),
                marker.widthAnchor.constraint(equalToConstant: 1)
            ])
            owner.layoutIfNeeded()
            let link = CADisplayLink(target: self, selector: #selector(sample))
            display = link
            link.add(to: .main, forMode: .common)
            sample()
        }

        @objc private func sample() {
            guard let owner = window?.rootViewController?.view else { return }
            let frame = owner.keyboardLayoutGuide.layoutFrame
            if first == nil && frame.height < 80 { return }
            let y = marker.layer.presentation()?.frame.minY ?? marker.frame.minY
            let point = Int(y.rounded())
            if turns.last != point {
                if turns.count > 1, let previous = turns.last,
                   (point > previous) == (previous > turns[turns.count - 2]) {
                    turns[turns.count - 1] = point
                } else { turns.append(point) }
            }
            if first == nil { first = y; last = y }
            travel += abs(y - last)
            last = y
            samples += 1
        }

        override var accessibilityValue: String? {
            get { "\(samples),\(first ?? 0),\(last),\(travel)" }
            set {}
        }
        override var accessibilityLabel: String? {
            get { turns.map(String.init).joined(separator: " → ") }
            set {}
        }
        func end() {
            display?.invalidate()
            display = nil
            marker.removeFromSuperview()
        }
    }
}
