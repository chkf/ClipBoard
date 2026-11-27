import SwiftUI
import UIKit

enum KeyboardPalette {
    static let key = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.16) : .white }
    static let disabledReturn = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.40) : UIColor(white: 0, alpha: 0.15) }
    static let returnAccent = UIColor(red: 0, green: 122/255, blue: 1, alpha: 1)
    static let pressed = UIColor { $0.userInterfaceStyle == .dark ? .systemGray : .systemGray3 }
}

extension EnvironmentValues {
    @Entry var keyboardFeedback: @MainActor () -> Void = {}
}

struct KeyboardLayout {
    let keyHeight: CGFloat
    let rowGap: CGFloat
    let bottomInset: CGFloat
    let sideInset: CGFloat = 6.5
    let columnGap: CGFloat = 6
    let smallKey: CGFloat
    let returnWidth: CGFloat
    let rowCount: Int
    let headerHeight: CGFloat
    var rowsHeight: CGFloat { CGFloat(rowCount) * (keyHeight + rowGap) - rowGap }

    init(size: CGSize) {
        let compact = size.height < 190
        let preferred = compact ? 34 : min(48, max(38, (43 + (size.width - 402) / 16).rounded()))
        let minHeader: CGFloat = compact ? 22 : 28
        rowGap = compact ? 6 : 11
        bottomInset = compact ? 3 : min(7, max(3, (size.width - 402) / 15 + 3))
        let available = max(0, size.height - bottomInset - minHeader)
        keyHeight = min(preferred, max(20, floor((available - 3 * rowGap) / 4)))
        // Keep complete records between the header and the input row, also at a custom height.
        rowCount = max(3, Int((available + rowGap) / (keyHeight + rowGap)) - 1)
        headerHeight = max(0, size.height - bottomInset - CGFloat(rowCount + 1) * keyHeight - CGFloat(rowCount) * rowGap)
        let unit = max(1, (size.width - 2 * sideInset + columnGap) / 8)
        smallKey = max(1, unit - columnGap)
        returnWidth = max(1, 2 * unit - columnGap)
    }
}

struct HostReturnKey: Equatable {
    var label: String
    var symbol: String?
    let accented: Bool
    let enabled: Bool
    var fill: UIColor {
        guard enabled else { return KeyboardPalette.disabledReturn }
        return accented ? KeyboardPalette.returnAccent : KeyboardPalette.key
    }
    var foreground: Color {
        guard enabled else { return Color(uiColor: .label).opacity(0.10) }
        return accented ? .white : .primary
    }
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
    static let hapticsPreference = "KeyboardHapticsEnabled"
    @Published var settings = false
    @Published var categoryRequest: CategoryRequest?
    @Published var returnKey = HostReturnKey()
    @Published var heightOffset = 0
    @Published var needsGlobe = false
    @Published var showsInputModeName = false
    @Published var appearanceID = UUID()
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
            }
    }
}

struct KeyboardKey: View {
    @Environment(\.keyboardFeedback) private var feedback
    let label: String
    let id: String
    var symbol: String? = nil
    var title: String? = nil
    var fill = KeyboardPalette.key
    var foreground: Color = .primary
    var fontSize: CGFloat = 18
    let action: () -> Void

    var body: some View {
        Button { feedback(); action() } label: {
            Group {
                if let symbol { Image(systemName: symbol).font(.system(size: fontSize, weight: .regular)) }
                else if title == "" { Color.clear }
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
        button.backgroundColor = KeyboardPalette.key
        button.layer.cornerRadius = 8
        button.accessibilityLabel = "切换输入法"
        button.accessibilityHint = "轻点切到下一个键盘，长按选择系统键盘或表情符号。"
        button.accessibilityIdentifier = "nextKeyboard"
        install(button)
        return button
    }
    func updateUIView(_ view: UIButton, context: Context) {}
}
