import SwiftUI

@MainActor
private final class CategorySettings: ObservableObject {
    private struct Saved: Codable {
        var groups = ClipCategory.initial
        var queue: [CategoryRequest] = []
    }
    private let key = "Clipboard.CategorySettings.v1"
    @Published private var saved: Saved
    @Published var error: String?
    @Published var busy = false
    private var shared: HistoryStore?
    var groups: [ClipCategory] {
        var result = saved.groups
        for change in saved.queue { Self.reflect(change, in: &result) }
        return result
    }
    var pending: CategoryRequest? { saved.queue.first }

    init() {
        saved = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
    }
    func open() async {
        guard let container = try? HistoryContainer.url() else { return }
        do {
            let connection = try HistoryStore(directory: container.appendingPathComponent("History", isDirectory: true))
            let groups = try await connection.categories()
            shared = connection
            saved.groups = groups.filter { $0 != .ordinary }
            persist()
        } catch { self.error = error.localizedDescription }
    }
    func stage(_ category: ClipCategory, operation: CategoryRequest.Operation) throws -> CategoryRequest {
        let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        if operation != .remove {
            guard !name.isEmpty else { throw CategoryError.emptyName }
            guard name != ClipCategory.ordinary.name, !groups.contains(where: { $0.id != category.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CategoryError.duplicateName
            }
        }
        let request = CategoryRequest(id: UUID(), operation: operation, category: ClipCategory(id: category.id, name: name))
        saved.queue.append(request); persist()
        return saved.queue[0]
    }
    func applyIfShared() async throws -> Bool {
        guard let shared else { return false }
        busy = true
        defer { busy = false }
        while let next = pending {
            try await shared.applyCategory(next)
            finish(next)
        }
        return true
    }
    func finish(_ request: CategoryRequest) {
        guard pending?.id == request.id else { return }
        Self.reflect(request, in: &saved.groups)
        saved.queue.removeFirst(); persist()
    }
    private static func reflect(_ request: CategoryRequest, in groups: inout [ClipCategory]) {
        if request.operation == .remove { groups.removeAll { $0.id == request.category.id } }
        else if let index = groups.firstIndex(where: { $0.id == request.category.id }) { groups[index] = request.category }
        else { groups.append(request.category) }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct CategoryManagement: View {
    private struct Editor: Identifiable {
        let id = UUID()
        let category: ClipCategory
        let operation: CategoryRequest.Operation
    }
    @StateObject private var catalog = CategorySettings()
    @State private var editor: Editor?
    @State private var name = ""
    @State private var transfer: CategoryRequest?
    @State private var error: String?

    var body: some View {
        List {
            if let pending = catalog.pending {
                Button("继续保存分类更改") { edit(pending.category, pending.operation); transfer = pending }
            }
            if let message = catalog.error { Text(verbatim: message).foregroundStyle(.secondary) }
            Text("普通").foregroundStyle(.secondary)
            ForEach(catalog.groups) { group in
                Button { edit(group, .rename) } label: {
                    Text(verbatim: group.name).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("manage-" + group.id)
                .swipeActions {
                    Button("删除", role: .destructive) { edit(group, .remove) }
                }
            }
        }.navigationTitle("分类管理")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("新建分类", systemImage: "plus") { edit(ClipCategory(id: UUID().uuidString, name: ""), .add) }
                        .accessibilityIdentifier("addCategory")
                }
            }
            .task { await catalog.open() }
            .sheet(item: $editor) { item in
                NavigationStack {
                    if let transfer {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("点键盘上的「应用分类更改」。如果显示其他输入法，请用地球键选择 Clipboard。")
                                .foregroundStyle(.secondary)
                            TrialInput(settings: false, request: transfer, acknowledged: {
                                catalog.finish(transfer)
                                if let next = catalog.pending { self.transfer = next } else { editor = nil }
                            }).id(transfer.id).frame(height: 1).accessibilityHidden(true)
                            Spacer()
                        }.padding().navigationTitle("保存到键盘")
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回") { editor = nil } } }
                    } else {
                        Form {
                            if item.operation == .remove {
                                Text("删除「\(item.category.name)」后，其中的记录会移回「普通」。")
                            } else {
                                TextField("分类名称", text: $name).accessibilityIdentifier("categoryName")
                            }
                            if let error { Text(verbatim: error).foregroundStyle(.red) }
                        }.navigationTitle(item.operation == .remove ? "删除分类" : item.operation == .add ? "新建分类" : "重命名")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) { Button("取消") { editor = nil } }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(item.operation == .remove ? "删除" : "保存") { save(item) }
                                        .disabled(catalog.busy || (item.operation != .remove && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                                        .accessibilityIdentifier("saveCategory")
                                }
                            }
                    }
                }.navigationBarTitleDisplayMode(.inline).presentationDetents([.large])
            }
    }
    private func edit(_ category: ClipCategory, _ operation: CategoryRequest.Operation) {
        name = category.name; error = nil; transfer = nil
        editor = Editor(category: category, operation: operation)
    }
    private func save(_ item: Editor) {
        Task { @MainActor in
            do {
                let request = try catalog.stage(ClipCategory(id: item.category.id, name: name), operation: item.operation)
                if try await catalog.applyIfShared() { editor = nil }
                else { transfer = request }
            } catch { self.error = error.localizedDescription }
        }
    }
}
