import SwiftUI

struct HistoryView: View {
    @ObservedObject var session: ClipboardSession
    @State private var settingsPresented = false
    @State private var preview: ClipRow?
    @State private var showCopied = false

    var body: some View {
        NavigationStack {
            List(session.rows) { row in
                ClipLabel(row: row, session: session)
                    .gesture(LongPressGesture().exclusively(before: TapGesture()).onEnded { result in
                        switch result {
                        case .first: preview = row
                        case .second: Task { await session.copy(row) }
                        }
                    })
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { Task { await session.copy(row) } }
                    .accessibilityAction(named: "预览") { preview = row }
                    .swipeActions {
                        Button("删除", systemImage: "trash", role: .destructive) {
                            Task { await session.edit { try await $0.delete(row.id) } }
                        }
                    }
                    .task { await session.nextPage(after: row) }
            }
            .listStyle(.plain)
            .overlay {
                if session.rows.isEmpty && session.loaded {
                    ContentUnavailableView {
                        Label("暂无历史记录", systemImage: "list.clipboard")
                    } description: {
                        if !session.settings.keyboardConfigured {
                            Text("在「设置」→「通用」→「键盘」→「键盘」中添加 Clipboard，开启「允许完全访问」，然后在输入框中切换到 Clipboard。系统询问时请选择「允许粘贴」。")
                        }
                    }
                }
            }
            .navigationTitle("Clipboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("设置", systemImage: "gearshape") { settingsPresented = true }
                        .accessibilityIdentifier("openSettings")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message = session.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                        .padding().frame(maxWidth: .infinity).background(.bar)
                } else if showCopied {
                    Label("已复制", systemImage: "checkmark").font(.subheadline)
                        .padding(.horizontal, 16).padding(.vertical, 9).glassEffect().padding(.bottom, 8)
                        .allowsHitTesting(false)
                }
            }
        }
        .sensoryFeedback(.success, trigger: session.copied)
        .task(id: session.copied) {
            guard session.copied > 0 else { return }
            showCopied = true
            try? await Task.sleep(for: .seconds(1.4))
            if !Task.isCancelled { showCopied = false }
        }
        .sheet(isPresented: $settingsPresented) { SettingsView(session: session) }
        .sheet(item: $preview) { row in PreviewView(row: row, session: session) }
    }
}
