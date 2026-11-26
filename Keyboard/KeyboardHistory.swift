import SwiftUI
import UIKit

struct KeyboardHistory: View {
    @ObservedObject var session: ClipboardSession
    @ObservedObject var presentation: KeyboardPresentation
    let select: (ClipRow) -> Void
    let insert: (String) -> Void
    let erase: () -> Void
    let selectedText: () -> String?
    let adjustHeight: (Int?) -> Void
    let receive: () -> Void
    let globe: (UIButton) -> Void
    @State private var confirmClear = false
    @State private var draft = ""
    @State private var emojiGroup = 0
    @State private var moreNumbers = false
    @State private var searchDigits = false
    @State private var copiedImage = false
    private let gap: CGFloat = 5

    var body: some View {
        GeometryReader { bounds in
            let compact = bounds.size.height < 195
            let bottom = compact ? CGFloat(35) : 45
            let rail = min(56, max(43, bounds.size.width * 0.122))
            VStack(spacing: gap) {
                if presentation.ticket != nil {
                    VStack(spacing: 14) {
                        Image(systemName: "tray.and.arrow.down").font(.title2)
                        if let note = presentation.importMessage { Text(note).font(.footnote) }
                        if !session.fullAccess { Text("请先在系统设置中允许键盘完全访问。").font(.footnote) }
                        Button(presentation.receiving ? "正在存入…" : "存入键盘", action: receive)
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("receiveCollectedCopies")
                            .disabled(presentation.receiving || !session.loaded || !session.fullAccess)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if presentation.needsGlobe { SystemGlobe(install: globe).frame(width: rail, height: bottom) }
                } else if presentation.settings {
                    settings
                    if presentation.needsGlobe { SystemGlobe(install: globe).frame(width: rail, height: bottom).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    HStack(spacing: gap) {
                        panel.frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack(spacing: gap) {
                            if presentation.page == .history {
                                KeyboardKey(label: "清空历史", id: "clearHistory", symbol: "trash", foreground: Color(uiColor: .systemBlue)) {
                                    confirmClear = true
                                }.disabled(!session.fullAccess).frame(height: bottom)
                                KeyboardKey(label: "搜索历史", id: "openSearch", symbol: "magnifyingglass") { openSearch() }
                                    .frame(height: bottom)
                            } else {
                                KeyboardKey(label: "返回剪贴板", id: "returnToHistory", symbol: "list.clipboard") { showHistory() }
                                    .frame(height: bottom)
                            }
                            KeyboardKey(label: "退格", id: "keyboardBackspace", symbol: "delete.left", fontSize: 22, action: backspace)
                        }.frame(width: rail)
                    }
                    HStack(spacing: gap) {
                        if presentation.needsGlobe { SystemGlobe(install: globe).frame(width: rail * 0.8) }
                        let numbers = presentation.page == .numbers
                        KeyboardKey(label: numbers ? "返回剪贴板" : "数字和符号", id: numbers ? "numbersBack" : "showNumbers",
                                    symbol: numbers ? "list.clipboard" : nil, title: "123", fontSize: 17) {
                            if numbers { showHistory() } else { presentation.page = .numbers; moreNumbers = false }
                        }.frame(width: rail)
                        let emoji = presentation.page == .emoji
                        KeyboardKey(label: emoji ? "返回剪贴板" : "表情", id: emoji ? "emojiBack" : "showEmoji",
                                    symbol: emoji ? "list.clipboard" : "face.smiling", fontSize: 21) {
                            if emoji { showHistory() } else { presentation.page = .emoji }
                        }.frame(width: rail)
                        KeyboardKey(label: "空格", id: "keyboardSpace", title: "空格", fill: KeyboardPalette.key, fontSize: 16) { type(" ") }
                        let key = presentation.page == .search ? HostReturnKey(.search) : presentation.returnKey
                        KeyboardKey(label: key.label, id: "keyboardReturn", symbol: key.symbol,
                                    fill: key.accented && key.enabled ? .systemBlue : KeyboardPalette.modifier,
                                    foreground: !key.enabled ? Color(uiColor: .tertiaryLabel) : key.accented ? .white : .primary,
                                    fontSize: key.symbol == nil ? 17 : 22) {
                            if presentation.page == .search { session.filter(draft); presentation.page = .history }
                            else { insert("\n") }
                        }.disabled(!key.enabled).frame(width: max(64, bounds.size.width * 0.225))
                    }.frame(height: bottom)
                }
            }
            .padding(.horizontal, 6).padding(.top, compact ? 3 : 5).padding(.bottom, 5)
        }
        .task(id: session.copied) {
            guard session.copied > 0 else { return }
            copiedImage = true
            try? await Task.sleep(for: .seconds(1.3))
            if !Task.isCancelled { copiedImage = false }
        }
        .onChange(of: presentation.page) { _, _ in confirmClear = false }
        .onChange(of: session.fullAccess) { _, access in if !access { confirmClear = false } }
    }

    @ViewBuilder private var panel: some View {
        switch presentation.page {
        case .history:
            VStack(alignment: .leading, spacing: 3) {
                if confirmClear {
                    HStack {
                        Text("清空未置顶记录？").font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        Button("取消") { confirmClear = false }.accessibilityIdentifier("cancelClear")
                        Button("清空", role: .destructive) {
                            Task { await session.edit { try await $0.clearUnpinned() }; confirmClear = false }
                        }.accessibilityIdentifier("confirmClear")
                    }.font(.subheadline).frame(minHeight: 36)
                } else {
                    HStack {
                        Text(copiedImage ? "图片已复制" : session.query.isEmpty ? "剪贴板" : "搜索 · " + session.query)
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        if !session.query.isEmpty {
                            Button("显示全部") { showHistory() }.font(.caption)
                        }
                    }.padding(.leading, 4).frame(height: 23)
                }
                if !session.fullAccess { note("打开「允许完全访问」可记录新内容。") }
                if let message = session.message { note(message) }
                if session.loaded && session.rows.isEmpty {
                    Text(session.query.isEmpty ? "暂无历史记录" : "没有匹配的记录")
                        .foregroundStyle(.secondary).font(.subheadline).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(session.rows) { row in
                            Button { select(row) } label: {
                                HStack(spacing: 7) {
                                    if row.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                                    ClipLabel(row: row, session: session)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .frame(maxWidth: .infinity, minHeight: 43, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(KeycapStyle()).disabled(!session.fullAccess && row.isImage)
                            .accessibilityLabel(Text(verbatim: row.isImage ? "图片" : row.preview))
                            .accessibilityValue(row.isPinned ? "已置顶" : "")
                            .accessibilityIdentifier("historyKey")
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if session.fullAccess {
                                    Button { togglePin(row) } label: { Label(row.isPinned ? "取消置顶" : "置顶", systemImage: row.isPinned ? "pin.slash" : "pin.fill") }
                                        .tint(.orange)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if session.fullAccess {
                                    Button(role: .destructive) { Task { await session.edit { try await $0.delete(row.id) } } }
                                        label: { Label("删除", systemImage: "trash") }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 1, leading: 1, bottom: 4, trailing: 1))
                            .listRowSeparator(.hidden).listRowBackground(Color.clear)
                            .task { await session.nextPage(after: row) }
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 0)
                    .contentMargins(.vertical, 0, for: .scrollContent)
                }
            }
        case .numbers:
            VStack(spacing: gap) {
                keyRows(moreNumbers ? ["[]{}#%^*+=", "_\\|~<>€£¥", ".,?!:;\"'"] : ["1234567890", "-/:;()¥&@\"", ".,?!'。？！"])
                Button(moreNumbers ? "123" : "#+=") { moreNumbers.toggle() }
                    .font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 26).buttonStyle(.borderless)
            }
        case .emoji:
            let names = ["表情", "手势", "生活", "符号"]
            let icons = ["😀😃😄😁😆🥹😂🤣😊😇🙂🙃😉😍🥰😘😎🥳🤔😅🥲😭😴🤯",
                         "👍👎👏🙌🫶🤝🙏✌️🤞🤟👌🤌👋🤙💪✊👊🤛🫰🤷",
                         "🎉🎂🎁🎈☕️🍵🍎🍕🍜🌞🌙⭐️🌈🌻🐶🐱🚗✈️🏠📱",
                         "❤️🧡💛💚💙💜🖤🤍💔💯✅❌❓❗️✨🔥💡📌💬🎵"]
            VStack(spacing: 4) {
                Picker("表情分类", selection: $emojiGroup) {
                    ForEach(names.indices, id: \.self) { index in Text(verbatim: names[index]).tag(index) }
                }.pickerStyle(.segmented)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 4)], spacing: 4) {
                        ForEach(Array(icons[emojiGroup]), id: \.self) { char in
                            KeyboardKey(label: String(char), id: "emoji-" + String(char), fill: KeyboardPalette.key,
                                        fontSize: 23) { type(String(char)) }.frame(height: 36)
                        }
                    }.padding(.vertical, 1)
                }
            }
        case .search:
            VStack(spacing: gap) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text(draft.isEmpty ? "文字或拼音" : draft).lineLimit(1)
                        .foregroundStyle(draft.isEmpty ? .secondary : .primary)
                    Spacer(minLength: 0)
                    Button("粘贴") { if let value = UIPasteboard.general.string { draft = value } }
                        .disabled(!session.fullAccess)
                    Button(searchDigits ? "ABC" : "123") { searchDigits.toggle() }
                }.font(.subheadline).padding(.horizontal, 7).frame(minHeight: 31)
                keyRows(searchDigits ? ["1234567890","-/:;()&@",".,?!_#"] : ["qwertyuiop","asdfghjkl","zxcvbnm"])
            }
        }
    }

    private func keyRows(_ rows: [String]) -> some View {
        ForEach(rows, id: \.self) { row in
            HStack(spacing: 3) {
                ForEach(Array(row), id: \.self) { char in
                    KeyboardKey(label: String(char), id: "key-" + String(char), fill: KeyboardPalette.key,
                                fontSize: 20) { type(String(char)) }
                }
            }
        }
    }
    private func togglePin(_ row: ClipRow) { Task { await session.edit { try await $0.pin(row.id, enabled: !row.isPinned) } } }
    private func showHistory() { session.filter(""); presentation.page = .history }
    private func openSearch() { draft = selectedText() ?? session.query; searchDigits = false; presentation.page = .search }
    private func type(_ text: String) { if presentation.page == .search { draft += text } else { insert(text) } }
    private func backspace() { if presentation.page == .search { if !draft.isEmpty { draft.removeLast() } } else { erase() } }
    private func note(_ text: String) -> some View { Text(text).font(.caption).foregroundStyle(.secondary) }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !session.fullAccess { note("打开键盘的「允许完全访问」后即可修改历史设置。") }
                if let message = session.message { note(message) }
                Text("历史保留期限").font(.subheadline.weight(.semibold))
                Picker("保留期限", selection: Binding(get: { session.settings.retention }, set: { days in
                    Task { await session.edit { try await $0.retention(days) } }
                })) { ForEach(HistorySettings.durations, id: \.self) { days in Text("\(days) 天").tag(days) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("retentionDays").disabled(!session.fullAccess || !session.loaded)
                Toggle("插入后自动切换键盘", isOn: Binding(get: { session.settings.autoSwitch }, set: { enabled in
                    Task { await session.edit { try await $0.autoSwitch(enabled) } }
                })).font(.subheadline).accessibilityIdentifier("autoSwitch").disabled(!session.fullAccess || !session.loaded)
                HStack {
                    Text("键盘高度").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("默认") { adjustHeight(nil) }.font(.caption)
                    Stepper(presentation.heightOffset.formatted(.number.sign(strategy: .always())) + " pt",
                            onIncrement: { adjustHeight(2) }, onDecrement: { adjustHeight(-2) })
                        .fixedSize().font(.subheadline).accessibilityIdentifier("heightAdjustment")
                }
            }.padding(10)
        }
    }
}
