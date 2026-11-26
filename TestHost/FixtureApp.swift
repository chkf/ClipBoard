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
                TextEditor(text: $input).accessibilityIdentifier("input").frame(height: 100).border(.secondary)
                Text(verbatim: input).accessibilityIdentifier("inserted")
            }.padding()
        }
    }
}
