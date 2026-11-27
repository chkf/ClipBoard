import Foundation

struct ClipCategory: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    static let ordinary = ClipCategory(id: "", name: "普通")
    static let initial = [ClipCategory(id: "work", name: "工作"), ClipCategory(id: "frequent", name: "常用")]
}

/// A user-confirmed category change in the containing app's dedicated input field.
/// Only the request identifier is acknowledged. No history is returned to a text client.
struct CategoryRequest: Codable, Equatable, Identifiable {
    enum Operation: String, Codable { case add, rename, remove }
    let id: UUID
    let operation: Operation
    let category: ClipCategory
    static let context = "Clipboard.Keyboard.Category.v1"
    var input: String {
        guard let bytes = try? JSONEncoder().encode(self) else { return "" }
        return Self.context + ":" + bytes.base64EncodedString()
    }
    var receipt: String { Self.context + ".done." + id.uuidString }
    var title: String {
        switch operation {
        case .add: return "新建「" + category.name + "」"
        case .rename: return "改名为「" + category.name + "」"
        case .remove: return "删除「" + category.name + "」"
        }
    }
    static func decode(_ text: String?) -> Self? {
        let prefix = context + ":"
        guard let text, text.hasPrefix(prefix),
              let data = Data(base64Encoded: String(text.dropFirst(prefix.count))),
              let request = try? JSONDecoder().decode(Self.self, from: data),
              !request.category.id.isEmpty, !request.category.name.isEmpty else { return nil }
        return request
    }
}
