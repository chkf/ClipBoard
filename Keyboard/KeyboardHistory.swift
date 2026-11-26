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

struct KeyboardHistory: View {
    @ObservedObject var session: ClipboardSession
    let select: (ClipRow) -> Void
    private enum Page { case history, deletion, settings }
    @State private var page = Page.history
    @State private var confirmingClear = false
    @State private var copiedImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(page == .settings ? "键盘设置" : page == .deletion ? "删除历史" : copiedImage ? "图片已复制" : "剪贴板")
                    .font(.headline).padding(.leading, 7)
                Spacer()
                if page == .history {
                    Button { page = .deletion } label: {
                        Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("删除历史记录").accessibilityIdentifier("editHistory")
                    .disabled(!session.fullAccess || session.rows.isEmpty)
                    Button { page = .settings } label: {
                        Image(systemName: "gearshape").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("键盘设置").accessibilityIdentifier("keyboardSettings")
                } else {
                    Button("完成") { confirmingClear = false; page = .history }
                        .frame(minWidth: 52, minHeight: 44).accessibilityIdentifier("closeKeyboardPanel")
                }
            }
            .buttonStyle(.plain)
            if page == .settings {
                settings
            } else {
                if !session.fullAccess {
                    note("在系统键盘设置中打开「允许完全访问」，即可保存和管理历史。")
                } else if let message = session.message {
                    note(message)
                }
                if session.rows.isEmpty {
                    Text("暂无历史记录").font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(session.rows) { row in
                                Button {
                                    if page == .deletion {
                                        Task { await session.edit { try await $0.delete(row.id) } }
                                    } else { select(row) }
                                } label: {
                                    HStack(spacing: 10) {
                                        if page == .deletion {
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
                                .disabled(!session.fullAccess && (row.isImage || page == .deletion))
                                .accessibilityLabel(Text(verbatim: row.isImage ? "图片" : row.preview))
                                .accessibilityHint(page == .deletion ? "删除这条历史记录" : row.isImage ? "复制图片" : "插入文本")
                                .accessibilityIdentifier(page == .deletion ? "deleteHistoryKey" : "historyKey")
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
            if !allowed { page = .history; confirmingClear = false }
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

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("保留期限").font(.subheadline)
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
                Divider()
                if confirmingClear {
                    HStack {
                        Text("清空全部历史？").font(.subheadline)
                        Spacer()
                        Button("取消") { confirmingClear = false }.accessibilityIdentifier("cancelClear")
                        Button("确认清空", role: .destructive) {
                            Task { await session.edit { try await $0.delete() }; confirmingClear = false }
                        }.accessibilityIdentifier("confirmClear")
                    }.buttonStyle(.bordered).frame(minHeight: 44)
                } else {
                    Button("清空历史记录", role: .destructive) { confirmingClear = true }
                        .frame(minHeight: 44).accessibilityIdentifier("clearHistory")
                }
            }
            .padding(.horizontal, 8)
            .disabled(!session.fullAccess)
        }
    }
}
