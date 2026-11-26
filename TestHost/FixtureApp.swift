import SwiftUI
import UIKit

// A separate simulator app supplies real inter-app pasteboard events and a keyboard host.
@main
struct FixtureApp: App {
    @State private var input = ""
    var body: some Scene {
        WindowGroup {
            VStack {
                Button("Copy text") {
                    UIPasteboard.general.string = "Clipboard UI fixture\nsecond line\nthird line"
                }
                Button("Copy image") {
                    let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 36)).image { ctx in
                        UIColor.orange.setFill()
                        ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 36))
                    }
                    UIPasteboard.general.setData(image.pngData()!, forPasteboardType: "public.png")
                }
                KeyboardField(text: $input).frame(height: 100).border(.secondary)
                Text(verbatim: input).accessibilityIdentifier("inserted")
            }.padding()
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
    // The fresh English simulator has one enabled zh-Hans input source after Settings setup.
    // Ask UIKit for that real system input mode when this field becomes first responder.
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "zh-Hans" } ?? super.textInputMode
    }
}
