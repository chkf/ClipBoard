import SwiftUI

struct SettingsView: View {
    @ObservedObject var session: ClipboardSession
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("保留期限", selection: Binding(get: { session.settings.retention }, set: { days in
                    Task { await session.edit { try await $0.retention(days) } }
                })) {
                    ForEach(HistorySettings.durations, id: \.self) { days in Text("\(days) 天").tag(days) }
                }
                Toggle("插入后自动切换键盘", isOn: Binding(get: { session.settings.autoSwitch }, set: { enabled in
                    Task { await session.edit { try await $0.autoSwitch(enabled) } }
                })).accessibilityIdentifier("autoSwitch")
                Section {
                    Button("清空历史记录", role: .destructive) { confirming = true }
                        .accessibilityIdentifier("clearHistory")
                }
            }
            .alert("清空全部历史记录？", isPresented: $confirming) {
                Button("取消", role: .cancel) {}
                Button("确认清空", role: .destructive) {
                    Task { await session.edit { try await $0.delete() } }
                }
            } message: { Text("保存的文本和图片将从这台设备移除。") }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("closeSettings")
                }
            }
        }
    }
}
