import UIKit

@MainActor
enum ClipboardInputMode {
    static let settingsContext = "Clipboard.Keyboard.Settings.v1"
    static var enabled: UITextInputMode? {
        let modes = UITextInputMode.activeInputModes
        // iOS can retain the neutral identifier when updating an enabled 1.3.0 keyboard.
        return modes.first { $0.primaryLanguage?.lowercased() == "zh-hans-x-cliphist" }
            ?? modes.first { $0.primaryLanguage?.lowercased() == "und-x-cliphist" }
    }
}
