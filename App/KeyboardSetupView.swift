import SwiftUI
import UIKit

struct KeyboardSetupView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var tryingKeyboard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 15) {
                        Label("启用键盘", systemImage: "keyboard").font(.title3.bold())
                        Text("在「设置」→「通用」→「键盘」→「键盘」中添加 Clipboard，再打开「允许完全访问」。")
                            .foregroundStyle(.secondary)
                        Button("打开系统设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20).background(.background, in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 15) {
                        Label("试用键盘", systemImage: "text.cursor").font(.title3.bold())
                        Text("先复制一段文字，在输入框里切到 Clipboard，点一下记录即可插入。")
                            .foregroundStyle(.secondary)
                        Button { tryingKeyboard = true } label: {
                            Text("打开试用输入框").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("tryKeyboard")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20).background(.background, in: RoundedRectangle(cornerRadius: 20))
                }
                .frame(maxWidth: 580, alignment: .leading)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Clipboard")
        }
        .sheet(isPresented: $tryingKeyboard) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text("如果看到的是其他键盘，长按地球键选择 Clipboard。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    TrialInput()
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(18)
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("试用键盘").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { tryingKeyboard = false }.accessibilityIdentifier("finishTrial")
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { tryingKeyboard = false }
        }
    }
}

private struct TrialInput: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TrialController { TrialController() }
    func updateUIViewController(_ controller: TrialController, context: Context) {}
}

private final class TrialController: UIViewController {
    private let editor = TrialTextView()
    override func loadView() {
        editor.backgroundColor = .clear
        editor.font = .preferredFont(forTextStyle: .body)
        editor.adjustsFontForContentSizeCategory = true
        editor.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        editor.accessibilityIdentifier = "trialInput"
        editor.accessibilityLabel = "试用输入框"
        view = editor
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        editor.becomeFirstResponder()
    }
}

private final class TrialTextView: UITextView {
    override var textInputContextIdentifier: String? { "Clipboard.keyboard.trial" }
    override var textInputMode: UITextInputMode? { ClipboardInputMode.enabled ?? super.textInputMode }
}
