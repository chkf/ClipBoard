import UIKit

@MainActor
enum ClipboardInputMode {
    static let settingsContext = "Clipboard.Keyboard.Settings.v1"
    static var enabled: UITextInputMode? {
        // Older installations can have the previous language tag cached by the system.
        UITextInputMode.activeInputModes.first { ["und-x-cliphist", "zh-hans-x-cliphist"].contains($0.primaryLanguage?.lowercased() ?? "") }
    }
}
