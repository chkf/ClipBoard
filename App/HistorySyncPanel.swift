import SwiftUI
import UIKit

struct HistorySyncPanel: View {
    @ObservedObject var sync: ForegroundHistorySync

    var body: some View {
        VStack(spacing: 6) {
            if let invite = sync.invitation {
                HStack {
                    ZStack {
                        SyncField(marker: invite.marker)
                            .accessibilityLabel("键盘同步输入框")
                        Text(status).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    }
                    .frame(height: 42)
                    Button("稍后") { sync.stop() }.accessibilityIdentifier("dismissKeyboardSync")
                }
                if case .pairing(let code) = sync.phase {
                    Button("配对主 App · " + code) { sync.approve() }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("pairMain")
                }
            } else if case .failed(let reason) = sync.phase {
                Text(reason).font(.footnote)
            } else if sync.phase == .done {
                Label("键盘历史已同步", systemImage: "checkmark")
                    .font(.footnote).accessibilityIdentifier("keyboardSynced")
            }
        }
        .padding(.horizontal, 12)
    }

    private var status: String {
        switch sync.phase {
        case .pairing: return "请核对上、下两个配对码，在两处确认。"
        case .transferring: return "正在与本机键盘同步…"
        default: return "用地球键切到 Clipboard 后会自动同步。"
        }
    }
}

private struct SyncField: UIViewRepresentable {
    let marker: String

    func makeUIView(context: Context) -> SyncTextField { SyncTextField() }

    func updateUIView(_ field: SyncTextField, context: Context) {
        guard field.text != marker else { return }
        field.textContentType = UITextContentType(rawValue: marker)
        field.text = marker
        field.activate()
    }

    static func dismantleUIView(_ field: SyncTextField, coordinator: ()) { field.resignFirstResponder() }
}

private final class SyncTextField: UITextField {
    override var textInputContextIdentifier: String? { "Clipboard.keyboard.history" }
    override var textInputMode: UITextInputMode? {
        let candidates = UITextInputMode.activeInputModes.filter { $0.primaryLanguage == "zh-Hans" }
        return candidates.count == 1 ? candidates[0] : super.textInputMode
    }
    override var accessibilityValue: String? { get { nil } set {} }

    override init(frame: CGRect) {
        super.init(frame: frame)
        textColor = .clear
        tintColor = .clear
        keyboardType = .URL
        returnKeyType = .done
        autocorrectionType = .no
        spellCheckingType = .no
        autocapitalizationType = .none
        accessibilityIdentifier = "keyboardSyncField"
    }
    required init?(coder: NSCoder) { nil }
    override func didMoveToWindow() { super.didMoveToWindow(); activate() }
    override func insertText(_ text: String) {}
    override func deleteBackward() {}

    func activate() {
        guard window != nil, let text, !text.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, window != nil else { return }
            if !isFirstResponder { becomeFirstResponder() }
            selectedTextRange = textRange(from: beginningOfDocument, to: endOfDocument)
        }
    }
}
