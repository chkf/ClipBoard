import SwiftUI
import UIKit

struct KeyboardHistory: View {
    @ObservedObject var session: ClipboardSession
    @ObservedObject var presentation: KeyboardPresentation
    let select: (ClipRow) -> Void
    let insert: (String) -> Void
    let erase: () -> Void
    let moveCursor: (Int) -> Void
    let applyCategory: (CategoryRequest) -> Void
    let adjustHeight: (Int?) -> Void
    let globe: (UIButton) -> Void

    private enum Panel: Equatable { case history, categories, file(ClipRow), clear }
    @State private var panel: Panel = .history
    @AppStorage("ClipboardRecentFiling") private var recentFiling = Data()
    @AppStorage(KeyboardPresentation.hapticsPreference) private var hapticsEnabled = true
    @Environment(\.keyboardFeedback) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { bounds in
            let layout = KeyboardLayout(size: bounds.size)
            let rail = min(56, max(43, bounds.size.width * 0.122))
            VStack(spacing: 0) {
                if let request = presentation.categoryRequest {
                    VStack(spacing: 8) {
                        let existing = session.categories.first { $0.id == request.category.id }
                        if request.operation == .rename, let existing {
                            Text("将「" + existing.name + "」改为「" + request.category.name + "」").font(.headline).lineLimit(3)
                        } else if request.operation == .remove, let existing {
                            Text("删除「" + existing.name + "」").font(.headline).lineLimit(2)
                        } else { Text(request.title).font(.headline).lineLimit(2) }
                        if request.operation == .remove { note("其中的记录将移回「普通」。") }
                        if let message = session.message { note(message) }
                        if !session.fullAccess { note("请在键盘设置中允许完全访问，然后重试。") }
                        Button("应用分类更改") { feedback(); applyCategory(request) }
                            .buttonStyle(.borderedProminent).disabled(!session.loaded || !session.fullAccess)
                            .accessibilityIdentifier("applyCategoryChange")
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if presentation.needsGlobe {
                        SystemGlobe(install: globe).frame(width: rail, height: layout.keyHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if presentation.settings {
                    settings
                    if presentation.needsGlobe {
                        SystemGlobe(install: globe).frame(width: rail, height: layout.keyHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    header.frame(height: layout.headerHeight)
                    HStack(alignment: .top, spacing: layout.columnGap) {
                        content(layout).frame(maxWidth: .infinity, maxHeight: .infinity)
                        commands(layout).frame(width: rail)
                    }.frame(height: layout.rowsHeight)
                    footer(layout).frame(height: layout.keyHeight).padding(.top, layout.rowGap)
                }
            }.padding(.horizontal, layout.sideInset).padding(.bottom, layout.bottomInset)
        }
        .onChange(of: presentation.appearanceID) { _, _ in panel = .history }
        .onChange(of: session.fullAccess) { _, access in if !access { panel = .history } }
        .onChange(of: session.message) { _, message in
            if let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
    }

    @ViewBuilder private var header: some View {
        if case .file(let row) = panel {
            ZStack {
                VStack(spacing: 0) {
                    Text("归类到").font(.subheadline.weight(.medium))
                    Text(verbatim: row.isImage ? "图片" : row.preview).lineLimit(1).font(.caption2).foregroundStyle(.secondary)
                }.padding(.horizontal, 54)
                HStack { Button("取消") { panel = .history }; Spacer() }
            }
        } else {
            HStack(spacing: 0) {
                ScrollViewReader { scroll in
                    ScrollView(.horizontal) {
                        HStack(spacing: 3) {
                            ForEach(session.categories) { category in
                                let current = session.category == category.id
                                Button { feedback(); browse(category) } label: {
                                    Text(verbatim: category.name).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                        .font(.subheadline.weight(current ? .semibold : .regular))
                                        .padding(.horizontal, 8).frame(minWidth: 44, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).foregroundStyle(current ? Color.primary : Color.secondary)
                                    .accessibilityAddTraits(current ? .isSelected : [])
                                    .accessibilityIdentifier("tab-" + (category.id.isEmpty ? "ordinary" : category.id))
                                    .id(category.id)
                            }
                        }
                    }.scrollIndicators(.hidden)
                        .onChange(of: session.category) { _, value in scroll.scrollTo(value, anchor: .center) }
                }
                Button { feedback(); panel = panel == .categories ? .history : .categories } label: {
                    Image(systemName: panel == .categories ? "chevron.up" : "chevron.down")
                        .font(.body.weight(.medium)).frame(width: 44).frame(maxHeight: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(panel == .categories ? "收起分类" : "展开全部分类").accessibilityIdentifier("expandCategories")
            }
        }
    }

    private func browse(_ category: ClipCategory) {
        session.selectCategory(category.id)
        panel = .history
    }

    @ViewBuilder private func content(_ layout: KeyboardLayout) -> some View {
        switch panel {
        case .history:
            if session.rows.isEmpty {
                if let message = session.message { note(message) }
                else if !session.fullAccess { note("打开「允许完全访问」可记录新内容。") }
                else if session.loaded { note("暂无历史记录") }
            } else { history(layout) }
        case .categories: categoryList(nil)
        case .file(let row): categoryList(row)
        case .clear:
            VStack(spacing: 6) {
                Text("清空「普通」里的 \(session.ordinaryCount) 条未置顶记录？")
                    .font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                HStack(spacing: 18) {
                    Button("取消") { panel = .history }.foregroundStyle(.primary).accessibilityIdentifier("cancelClear")
                    Button("清空") { feedback(); session.perform(.clearOrdinary); panel = .history }
                        .foregroundStyle(Color(uiColor: .systemBlue)).accessibilityIdentifier("confirmClear")
                }.buttonStyle(.plain).font(.body.weight(.medium)).controlSize(.large)
            }
        }
    }

    private func categoryList(_ row: ClipRow?) -> some View {
        let recentIDs = (try? JSONDecoder().decode([String].self, from: recentFiling)) ?? []
        let recent = row == nil ? [] : recentIDs.compactMap { id in session.categories.first { $0.id == id && id != session.category } }
        let others = session.categories.filter { group in !recent.contains(group) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if !recent.isEmpty {
                    Text("最近使用").font(.caption).foregroundStyle(.secondary)
                    folderGrid(recent, filing: row)
                }
                folderGrid(others, filing: row)
            }
        }.accessibilityIdentifier("categoryList")
    }

    private func folderGrid(_ categories: [ClipCategory], filing row: ClipRow?) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 85), spacing: 4)], alignment: .leading, spacing: 4) {
            ForEach(categories) { category in
                Button {
                    feedback()
                    if let row {
                        session.perform(.move(row.id, to: category.id))
                        var recent = (try? JSONDecoder().decode([String].self, from: recentFiling)) ?? []
                        recent.removeAll { $0 == category.id }; recent.insert(category.id, at: 0)
                        if let data = try? JSONEncoder().encode(Array(recent.prefix(3))) { recentFiling = data }
                        panel = .history
                    } else { browse(category) }
                } label: {
                    Text(verbatim: category.name).font(.subheadline).multilineTextAlignment(.leading)
                        .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(KeycapStyle()).disabled(row != nil && category.id == session.category)
                    .accessibilityIdentifier("folder-" + (category.id.isEmpty ? "ordinary" : category.id))
            }
        }
    }

    private func requestClear() {
        if session.fullAccess && session.ordinaryCount > 0 { panel = .clear }
    }

    private func commands(_ layout: KeyboardLayout) -> some View {
        VStack(spacing: layout.rowGap) {
            KeyboardKey(label: "清空普通记录", id: "clearHistory", symbol: "trash", action: requestClear)
                .disabled(!session.fullAccess || session.ordinaryCount == 0).frame(height: layout.keyHeight)
            KeyboardKey(label: "撤销", id: "undoHistory", symbol: "arrow.uturn.backward",
                        foreground: session.undoAvailable ? .primary : .secondary) { session.undo(); panel = .history }
                .disabled(!session.fullAccess || !session.undoAvailable || panel == .clear).frame(height: layout.keyHeight)
            KeyboardHoldKey("退格", id: "keyboardBackspace", symbol: "delete.left", holdLabel: "清空普通记录",
                            tap: erase, hold: requestClear).frame(height: layout.keyHeight)
        }
    }

    private func footer(_ layout: KeyboardLayout) -> some View {
        HStack(spacing: layout.columnGap) {
            SystemGlobe(install: globe).frame(width: 2 * layout.smallKey + layout.columnGap)
            KeyboardHoldKey("空格", id: "keyboardSpace", holdLabel: "移动光标", tap: { insert(" ") }, hold: {}, moveCursor: moveCursor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Clipboard")
                        .font(.system(size: 16)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(Color(uiColor: .label)).opacity(presentation.showsInputModeName ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: presentation.showsInputModeName)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .overlay(alignment: .bottomTrailing) {
                    if !presentation.showsInputModeName {
                        Text("剪").font(.system(size: 11)).foregroundStyle(.secondary).padding(.trailing, 5).padding(.bottom, 2)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            let key = presentation.returnKey
            KeyboardKey(label: key.label, id: "keyboardReturn", symbol: key.symbol,
                        fill: key.fill, foreground: key.foreground, fontSize: key.symbol == nil ? 17 : 19) { insert("\n") }
                .disabled(!key.enabled).frame(width: layout.returnWidth)
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
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if session.fullAccess {
                        Button { feedback(); session.perform(.pin(row.id,!row.isPinned)) }
                            label: { Label(row.isPinned ? "取消置顶" : "置顶", systemImage: row.isPinned ? "pin.slash" : "pin.fill") }
                            .tint(.orange)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if session.fullAccess {
                        Button(role: .destructive) { feedback(); session.perform(.remove(row.id)) }
                            label: { Label("删除", systemImage: "trash") }
                        Button { feedback(); panel = .file(row) } label: { Label("归类", systemImage: "folder") }.tint(.blue)
                    }
                }
                .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
                .task { await session.nextPage(after: row) }
            }
        }.listStyle(.plain).listRowSpacing(layout.rowGap).scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0).environment(\.layoutDirection, .leftToRight)
            .contentMargins(.vertical, 0, for: .scrollContent)
    }

    private func note(_ text: String) -> some View { Text(text).font(.subheadline).foregroundStyle(.secondary) }

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
