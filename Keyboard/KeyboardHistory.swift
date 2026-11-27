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
    let globe: (UIButton) -> Void
    @State private var confirmClear = false
    @State private var draft = ""
    @State private var emojiGroup = 0
    @State private var moreNumbers = false
    @State private var searchDigits = false
    @State private var copiedImage = false
    @AppStorage(KeyboardPresentation.hapticsPreference) private var hapticsEnabled = true
    @Environment(\.keyboardFeedback) private var feedback

    var body: some View {
        GeometryReader { bounds in
            let layout = KeyboardLayout(size: bounds.size)
            let rail = min(56, max(43, bounds.size.width * 0.122))
            VStack(spacing: 0) {
                if presentation.settings {
                    settings
                    if presentation.needsGlobe {
                        SystemGlobe(install: globe).frame(width: rail, height: layout.keyHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    header.frame(height: layout.headerHeight)
                    HStack(alignment: .top, spacing: layout.columnGap) {
                        panel(layout).frame(maxWidth: .infinity, maxHeight: .infinity)
                        commands(layout).frame(width: rail)
                    }.frame(height: layout.rowsHeight)
                    footer(layout).frame(height: layout.keyHeight).padding(.top, layout.rowGap)
                }
            }
            .padding(.horizontal, layout.sideInset).padding(.bottom, layout.bottomInset)
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

    @ViewBuilder private var header: some View {
        switch presentation.page {
        case .history:
            HStack(spacing: 8) {
                if confirmClear {
                    Text("清空未置顶记录？").fontWeight(.semibold)
                    Spacer(minLength: 0)
                    Button("取消") { confirmClear = false }.accessibilityIdentifier("cancelClear")
                    Button("清空", role: .destructive) {
                        Task { await session.edit { try await $0.clearUnpinned() }; confirmClear = false }
                    }.accessibilityIdentifier("confirmClear")
                } else {
                    if let message = session.message { note(message) }
                    else if !session.fullAccess { note("打开「允许完全访问」可记录新内容。") }
                    else {
                        Text(copiedImage ? "图片已复制" : session.query.isEmpty ? "剪贴板" : "搜索 · " + session.query)
                            .fontWeight(.semibold).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !session.query.isEmpty {
                        Button("显示全部") { showHistory() }
                    }
                }
            }.font(.subheadline).padding(.horizontal, 4)
        case .search:
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(draft.isEmpty ? "文字或拼音" : draft).lineLimit(1)
                    .foregroundStyle(draft.isEmpty ? .secondary : .primary)
                Spacer(minLength: 0)
                Button("粘贴") { if let value = UIPasteboard.general.string { draft = value } }
                    .disabled(!session.fullAccess)
                Button(searchDigits ? "ABC" : "123") { searchDigits.toggle() }
            }.font(.subheadline).padding(.horizontal, 4)
        case .emoji:
            Picker("表情分类", selection: $emojiGroup) {
                ForEach(Array(["表情", "手势", "生活", "符号"].enumerated()), id: \.offset) { index, name in
                    Text(verbatim: name).tag(index)
                }
            }.pickerStyle(.segmented)
        case .numbers:
            Color.clear.accessibilityHidden(true)
        }
    }

    private func commands(_ layout: KeyboardLayout) -> some View {
        VStack(spacing: layout.rowGap) {
            if presentation.page == .history {
                KeyboardKey(label: "清空历史", id: "clearHistory", symbol: "trash", foreground: Color(uiColor: .systemBlue)) {
                    confirmClear = true
                }.disabled(!session.fullAccess).frame(height: layout.keyHeight)
                KeyboardKey(label: "搜索历史", id: "openSearch", symbol: "magnifyingglass", action: openSearch)
                    .frame(height: layout.keyHeight)
            } else {
                switch presentation.page {
                case .search:
                    KeyboardKey(label: "返回剪贴板", id: "returnToHistory", symbol: "list.clipboard", action: showHistory)
                        .frame(height: layout.keyHeight)
                case .numbers:
                    KeyboardKey(label: moreNumbers ? "常用数字" : "更多符号", id: "moreNumbers",
                                title: moreNumbers ? "123" : "#+=") { moreNumbers.toggle() }.frame(height: layout.keyHeight)
                default:
                    KeyboardKey(label: "搜索历史", id: "openSearch", symbol: "magnifyingglass", action: openSearch)
                        .frame(height: layout.keyHeight)
                }
                Color.clear.frame(height: layout.keyHeight).accessibilityHidden(true)
            }
            KeyboardKey(label: "退格", id: "keyboardBackspace", symbol: "delete.left", fontSize: 20, action: backspace)
                .frame(height: layout.keyHeight)
        }
    }

    private func footer(_ layout: KeyboardLayout) -> some View {
        HStack(spacing: layout.columnGap) {
            if presentation.needsGlobe {
                SystemGlobe(install: globe).frame(width: layout.smallKey)
            }
            let numbers = presentation.page == .numbers
            KeyboardKey(label: numbers ? "返回剪贴板" : "数字和符号", id: numbers ? "numbersBack" : "showNumbers",
                        symbol: numbers ? "list.clipboard" : nil, title: "123", fontSize: 17) {
                if numbers { showHistory() } else { presentation.page = .numbers; moreNumbers = false }
            }.frame(width: layout.smallKey)
            let emoji = presentation.page == .emoji
            KeyboardKey(label: emoji ? "返回剪贴板" : "表情", id: emoji ? "emojiBack" : "showEmoji",
                        symbol: emoji ? "list.clipboard" : "face.smiling", fontSize: 20) {
                if emoji { showHistory() } else { presentation.page = .emoji }
            }.frame(width: layout.smallKey)
            KeyboardKey(label: "空格", id: "keyboardSpace", title: "") { type(" ") }
            let key = presentation.page == .search ? HostReturnKey(.search) : presentation.returnKey
            KeyboardKey(label: key.label, id: "keyboardReturn", symbol: key.symbol,
                        fill: key.fill, foreground: key.foreground, fontSize: key.symbol == nil ? 17 : 19) {
                if presentation.page == .search { session.filter(draft); presentation.page = .history }
                else { insert("\n") }
            }.disabled(!key.enabled).frame(width: layout.returnWidth)
        }
    }

    @ViewBuilder private func panel(_ layout: KeyboardLayout) -> some View {
        switch presentation.page {
        case .history:
            if session.loaded && session.rows.isEmpty {
                Text(session.query.isEmpty ? "暂无历史记录" : "没有匹配的记录")
                    .foregroundStyle(.secondary).font(.subheadline)
            } else {
                history(layout)
            }
        case .numbers:
            keyRows(moreNumbers ? ["[]{}#%^*+=", "_\\|~<>€£¥", ".,?!:;\"'"] : ["1234567890", "-/:;()¥&@\"", ".,?!'。？！"], layout)
        case .search:
            keyRows(searchDigits ? ["1234567890","-/:;()&@",".,?!_#"] : ["qwertyuiop","asdfghjkl","zxcvbnm"], layout)
        case .emoji:
            let icons = ["😀😃😄😁😆🥹😂🤣😊😇🙂🙃😉😍🥰😘😎🥳🤔😅🥲😭😴🤯",
                         "👍👎👏🙌🫶🤝🙏✌️🤞🤟👌🤌👋🤙💪✊👊🤛🫰🤷",
                         "🎉🎂🎁🎈☕️🍵🍎🍕🍜🌞🌙⭐️🌈🌻🐶🐱🚗✈️🏠📱",
                         "❤️🧡💛💚💙💜🖤🤍💔💯✅❌❓❗️✨🔥💡📌💬🎵"]
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 4)], spacing: layout.rowGap) {
                    ForEach(Array(icons[emojiGroup]), id: \.self) { char in
                        KeyboardKey(label: String(char), id: "emoji-" + String(char), fontSize: 23) { type(String(char)) }
                            .frame(height: layout.keyHeight)
                    }
                }
            }
        }
    }

    private func history(_ layout: KeyboardLayout) -> some View {
        List {
            ForEach(session.rows) { row in
                Button { feedback(); select(row) } label: {
                    HStack(spacing: 7) {
                        if row.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                        ClipLabel(row: row, session: session, keyHeight: layout.keyHeight)
                    }
                    .padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: layout.keyHeight).contentShape(Rectangle())
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
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
                .task { await session.nextPage(after: row) }
            }
        }
        .listStyle(.plain).listRowSpacing(layout.rowGap).scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.vertical, 0, for: .scrollContent)
    }

    private func keyRows(_ rows: [String], _ layout: KeyboardLayout) -> some View {
        VStack(spacing: layout.rowGap) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(Array(row), id: \.self) { char in
                        KeyboardKey(label: String(char), id: "key-" + String(char), fontSize: 20) { type(String(char)) }
                    }
                }.frame(height: layout.keyHeight)
            }
        }.frame(maxHeight: .infinity, alignment: .top)
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
                Toggle("按键触感", isOn: $hapticsEnabled)
                    .font(.subheadline).accessibilityIdentifier("keyboardHaptics")
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
