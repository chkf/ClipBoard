import UIKit

@MainActor
enum ClipboardInputMode {
    static let settingsContext = "Clipboard.Keyboard.Settings.v1"
    static var enabled: UITextInputMode? {
        // The keyboard declares a BCP 47 private-use subtag so other Chinese keyboards keep their own identity.
        UITextInputMode.activeInputModes.first { $0.primaryLanguage?.lowercased() == "zh-hans-x-cliphist" }
    }
}
