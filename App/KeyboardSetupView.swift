import SwiftUI
import UIKit

struct KeyboardSetupView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private enum Panel: String, Identifiable {
        case trial, settings, collection
        var id: String { rawValue }
    }
    @State private var panel: Panel?
    @ObservedObject private var collector = CopyCollector.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button { collector.showCollection = true } label: {
                        HStack {
                            Image(systemName: "rectangle.on.rectangle")
                            Text("连续复制").font(.headline)
                            Spacer()
                            if collector.phase == .running { Text("\(collector.count) 条").monospacedDigit() }
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain).accessibilityIdentifier("openCollection")
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
                    .padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 15) {
                        Label("试用键盘", systemImage: "text.cursor").font(.title3.bold())
                        Text("先复制一段文字，在输入框里切到 Clipboard，点一下记录即可插入。")
                            .foregroundStyle(.secondary)
                        Button { panel = .trial } label: {
                            Text("打开试用输入框").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("tryKeyboard")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                }
                .frame(maxWidth: 580, alignment: .leading)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Clipboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("键盘设置", systemImage: "gearshape") { panel = .settings }
                        .accessibilityIdentifier("openKeyboardSettings")
                }
            }
        }
        .onOpenURL { url in
            if url.scheme == "clipboard-collect", url.host == "session" { collector.showCollection = true }
        }
        .sheet(item: Binding(get: { collector.showCollection ? .collection : panel }, set: { value in
            collector.showCollection = value == .collection
            panel = value == .collection ? nil : value
        })) { (current: Panel) in
            if current == .collection {
                CopyCollectionView(collector: collector)
            } else {
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text(current == .settings ? "下方选项直接保存到键盘。如果出现其他输入法，请用地球键选 Clipboard。" : "如果看到的是其他键盘，长按地球键选择 Clipboard。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if current == .settings {
                        TrialInput(settings: true).frame(height: 1).accessibilityHidden(true)
                        Spacer(minLength: 0)
                    } else {
                        TrialInput(settings: false)
                            .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(18)
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(current == .settings ? "键盘设置" : "试用键盘").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { panel = nil }.accessibilityIdentifier("finishTrial")
                    }
                }
            }
            .presentationDetents(current == .settings ? [.medium] : [.large])
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { panel = nil }
        }
    }
}

private struct TrialInput: UIViewControllerRepresentable {
    let settings: Bool
    func makeUIViewController(context: Context) -> TrialController {
        let controller = TrialController()
        controller.settings = settings
        return controller
    }
    func updateUIViewController(_ controller: TrialController, context: Context) {}
}

private final class TrialController: UIViewController {
    private let editor = TrialTextView()
    var settings = false
    override func loadView() {
        editor.backgroundColor = .clear
        editor.font = .preferredFont(forTextStyle: .body)
        editor.adjustsFontForContentSizeCategory = true
        editor.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        editor.accessibilityIdentifier = "trialInput"
        editor.accessibilityLabel = "试用输入框"
        if settings {
            editor.textContentType = UITextContentType(rawValue: ClipboardInputMode.settingsContext)
            editor.text = ClipboardInputMode.settingsContext
            editor.textColor = .clear
            editor.tintColor = .clear
            editor.autocorrectionType = .no
            editor.returnKeyType = .join
            editor.isAccessibilityElement = false
        }
        view = editor
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        editor.becomeFirstResponder()
        if settings { editor.selectedTextRange = editor.textRange(from: editor.beginningOfDocument, to: editor.endOfDocument) }
    }
}

private final class TrialTextView: UITextView {
    override var textInputContextIdentifier: String? { "Clipboard.keyboard.trial" }
    override var textInputMode: UITextInputMode? { ClipboardInputMode.enabled ?? super.textInputMode }
}
