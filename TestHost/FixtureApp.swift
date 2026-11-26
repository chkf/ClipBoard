import SwiftUI
import UIKit

// A separate simulator app supplies real inter-app pasteboard events and a keyboard host.
@main
struct FixtureApp: App {
    @State private var input = ""
    @State private var copyStatus = ""
    var body: some Scene {
        WindowGroup {
            VStack {
                Button("Copy text") {
                    let board = UIPasteboard.general
                    let value = "Clipboard UI fixture\nsecond line\nthird line"
                    let before = board.changeCount
                    board.string = value
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
                    board.setData(data, forPasteboardType: "public.png")
                    confirmWrite("Image copied", after: before) { board.data(forPasteboardType: "public.png") == data }
                }
                Button("Copy second") {
                    let board = UIPasteboard.general
                    let before = board.changeCount
                    board.string = "Saved while the main app was closed"
                    confirmWrite("Second copied", after: before) { board.string == "Saved while the main app was closed" }
                }
                Button("Check clipboard image") {
                    copyStatus = UIPasteboard.general.hasImages ? "Image still on clipboard" : "Image missing"
                }
                Text(verbatim: copyStatus).accessibilityIdentifier("copyStatus")
                KeyboardField(text: $input).frame(height: 100).border(.secondary)
                Text(verbatim: input).accessibilityIdentifier("inserted")
            }
            .padding()
            .buttonStyle(.bordered)
            .controlSize(.large)
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

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = FixtureTextView()
        view.accessibilityIdentifier = "input"
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {}

    final class Coordinator: NSObject, UITextViewDelegate {
        let field: KeyboardField
        init(_ field: KeyboardField) { self.field = field }
        func textViewDidChange(_ textView: UITextView) { field.text = textView.text }
    }
}

private final class FixtureTextView: UITextView {
    override var textInputMode: UITextInputMode? {
        ClipboardInputMode.enabled ?? super.textInputMode
    }
}
