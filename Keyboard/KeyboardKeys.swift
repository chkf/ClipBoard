import SwiftUI
import UIKit

enum KeyboardPalette {
    static let tray = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.125, alpha: 1) : .systemGray5 }
    static let key = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : .white }
    static let modifier = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.28, alpha: 1) : UIColor(white: 0.79, alpha: 1) }
    static let returnAccent = UIColor(red: 0, green: 122/255, blue: 1, alpha: 1)
    static let returnNeutral = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 60/255, alpha: 1) : .white }
    static let pressed = UIColor { $0.userInterfaceStyle == .dark ? .systemGray : .systemGray3 }
}

enum KeyboardPage { case history, numbers, emoji, search }

struct HostReturnKey: Equatable {
    var label: String
    var symbol: String?
    let accented: Bool
    let enabled: Bool
    init(_ type: UIReturnKeyType = .default, enabled: Bool = true) {
        self.enabled = enabled
        accented = type != .default
        switch type {
        case .done: label = "完成"; symbol = "checkmark"
        case .send: label = "发送"; symbol = "arrow.up"
        case .search, .google, .yahoo: label = "搜索"; symbol = "magnifyingglass"
        case .go: label = "前往"; symbol = "arrow.right"
        case .next: label = "下一项"
        case .join: label = "加入"
        case .continue: label = "继续"
        case .route: label = "路线"
        case .emergencyCall: label = "紧急呼叫"
        default: label = "换行"; symbol = "return"
        }
    }
}

@MainActor final class KeyboardPresentation: ObservableObject {
    @Published var settings = false
    @Published var page: KeyboardPage = .history
    @Published var returnKey = HostReturnKey()
    @Published var heightOffset = 0
    @Published var needsGlobe = false
    @Published var ticket: CaptureTicket?
    @Published var receiving = false
    @Published var importMessage: String?
}

struct KeycapStyle: ButtonStyle {
    var fill: UIColor = KeyboardPalette.key
    var foreground: Color = .primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(uiColor: configuration.isPressed ? KeyboardPalette.pressed : fill))
                    .shadow(color: .black.opacity(0.20), radius: 0, y: 1)
            }
    }
}

struct KeyboardKey: View {
    let label: String
    let id: String
    var symbol: String? = nil
    var title: String? = nil
    var fill = KeyboardPalette.modifier
    var foreground: Color = .primary
    var fontSize: CGFloat = 18
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol { Image(systemName: symbol).font(.system(size: fontSize, weight: .regular)) }
                else { Text(verbatim: title ?? label).font(.system(size: fontSize)).lineLimit(1).minimumScaleFactor(0.65) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(KeycapStyle(fill: fill, foreground: foreground))
        .accessibilityLabel(Text(verbatim: label)).accessibilityIdentifier(id)
    }
}

struct SystemGlobe: UIViewRepresentable {
    let install: (UIButton) -> Void
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.tintColor = .label
        button.backgroundColor = KeyboardPalette.modifier
        button.layer.cornerRadius = 8
        button.accessibilityLabel = "切换输入法"
        button.accessibilityIdentifier = "nextKeyboard"
        install(button)
        return button
    }
    func updateUIView(_ view: UIButton, context: Context) {}
}
