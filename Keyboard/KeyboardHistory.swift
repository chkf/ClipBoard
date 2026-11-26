import SwiftUI
import UIKit

enum KeyboardPalette {
    static let tray = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.125, alpha: 1) : .systemGray5 }
    static let key = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : .white }
    static let pressed = UIColor { $0.userInterfaceStyle == .dark ? .systemGray : .systemGray3 }
}

private struct KeycapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(uiColor: configuration.isPressed ? KeyboardPalette.pressed : KeyboardPalette.key))
                    .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
            }
    }
}

@MainActor
final class KeyboardPresentation: ObservableObject {
    @Published var settings = false
}

struct KeyboardHistory: View {
    @ObservedObject var session: ClipboardSession
    @ObservedObject var presentation: KeyboardPresentation
    let select: (ClipRow) -> Void
    @State private var deleting = false
    @State private var confirmingClear = false
    @State private var copiedImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if presentation.settings {
                settings
            } else {
                toolbar
                if !session.fullAccess {
                    note("在系统键盘设置中打开「允许完全访问」，即可保存和管理历史。")
                } else if let message = session.message {
                    note(message)
                }
                if session.rows.isEmpty && session.loaded {
                    Text("暂无历史记录").font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(session.rows) { row in
                                Button {
                                    if deleting {
                                        Task { await session.edit { try await $0.delete(row.id) } }
                                    } else { select(row) }
                                } label: {
                                    HStack(spacing: 10) {
                                        if deleting {
                                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                        }
                                        ClipLabel(row: row, session: session)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(KeycapStyle())
                                .disabled(!session.fullAccess && (row.isImage || deleting))
                                .accessibilityLabel(Text(verbatim: row.isImage ? "图片" : row.preview))
                                .accessibilityHint(deleting ? "删除这条历史记录" : row.isImage ? "复制图片" : "插入文本")
                                .accessibilityIdentifier(deleting ? "deleteHistoryKey" : "historyKey")
                                .task { await session.nextPage(after: row) }
                            }
                        }
                        .padding(.horizontal, 1).padding(.bottom, 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: session.fullAccess) { _, allowed in
            if !allowed { deleting = false; confirmingClear = false }
        }
        .task(id: session.copied) {
            guard session.copied > 0 else { return }
            copiedImage = true
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { copiedImage = false }
        }
    }

    private func note(_ value: String) -> some View {
        Text(value).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.bottom, 4)
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text(confirmingClear ? "清空全部历史？" : deleting ? "删除历史" : copiedImage ? "图片已复制" : "剪贴板")
                .font(.headline).padding(.leading, 7)
            Spacer()
            if confirmingClear {
                Button("取消") { confirmingClear = false }.accessibilityIdentifier("cancelClear")
                Button("确认清空", role: .destructive) {
                    Task {
                        await session.edit { try await $0.delete() }
                        confirmingClear = false
                        deleting = false
                    }
                }.accessibilityIdentifier("confirmClear")
            } else if deleting {
                Button("清空", role: .destructive) { confirmingClear = true }.accessibilityIdentifier("clearHistory")
                Button("完成") { deleting = false }.accessibilityIdentifier("closeKeyboardPanel")
            } else {
                Button { deleting = true } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("删除历史记录").accessibilityIdentifier("editHistory")
                .disabled(!session.fullAccess || session.rows.isEmpty)
            }
        }
        .padding(.trailing, 4).frame(height: 44).buttonStyle(.borderless)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !session.fullAccess { note("打开键盘的「允许完全访问」后即可修改设置。") }
                if let message = session.message { note(message) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("历史保留期限").font(.subheadline.weight(.semibold))
                    Picker("保留期限", selection: Binding(get: { session.settings.retention }, set: { days in
                        Task { await session.edit { try await $0.retention(days) } }
                    })) {
                        ForEach(HistorySettings.durations, id: \.self) { days in Text("\(days) 天").tag(days) }
                    }
                    .pickerStyle(.segmented).accessibilityIdentifier("retentionDays")
                }
                .frame(minHeight: 40)
                Toggle("插入后自动切换键盘", isOn: Binding(get: { session.settings.autoSwitch }, set: { enabled in
                    Task { await session.edit { try await $0.autoSwitch(enabled) } }
                }))
                .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("autoSwitch")
            }
            .padding(16)
            .disabled(!session.fullAccess || !session.loaded)
        }
    }
}
