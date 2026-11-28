import Foundation

enum HistoryAction {
    case move(String, to: String), pin(String, Bool), remove(String), clearOrdinary
}

enum CategoryError: LocalizedError {
    case emptyName, duplicateName, changed
    var errorDescription: String? {
        switch self {
        case .emptyName: return "请输入分类名称。"
        case .duplicateName: return "已有同名分类。"
        case .changed: return "此分类已经变更，请检查名称后重试。"
        }
    }
}

extension HistoryStore {
    struct CategoryPage {
        let categories: [ClipCategory]
        let selected: String
        let rows: [ClipRow]
        let canUndo: Bool
        let ordinaryCount: Int
    }

    func categoryPage(since revision: Int, category: String, limit: Int) throws -> (HistoryState, CategoryPage?) {
        try db.transaction(readOnly: true) {
            let state = try self.state()
            guard state.revision > revision else { return (state, nil) }
            let groups = try categories()
            let selected = groups.contains { $0.id == category } ? category : ClipCategory.ordinary.id
            let snapshot = try CategoryPage(categories: groups, selected: selected,
                                           rows: page(limit: limit, category: selected),
                                           canUndo: undoDepth() > 0, ordinaryCount: ordinaryUnpinnedCount())
            return (state, snapshot)
        }
    }

    func categories() throws -> [ClipCategory] {
        guard supportsCategories else { return [.ordinary] }
        return [.ordinary] + (try db.query("SELECT id,name FROM categories ORDER BY rowid") {
            ClipCategory(id: $0.text(0), name: $0.text(1))
        })
    }

    @discardableResult
    func saveCategory(id: String? = nil, name: String, inserting: Bool = false) throws -> ClipCategory {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !name.isEmpty else { throw CategoryError.emptyName }
        let category = ClipCategory(id: id ?? UUID().uuidString, name: name)
        guard category.id != ClipCategory.ordinary.id else { throw CategoryError.duplicateName }
        try db.transaction {
            let duplicate = try db.query("SELECT 1 FROM categories WHERE name=? AND id<>?", [.text(name),.text(category.id)]) { $0.integer(0) }
            guard name != ClipCategory.ordinary.name, duplicate.isEmpty else { throw CategoryError.duplicateName }
            if id == nil || inserting {
                let existing = try db.query("SELECT name FROM categories WHERE id=?", [.text(category.id)]) { $0.text(0) }.first
                if let existing {
                    guard existing == name else { throw CategoryError.changed }
                    return
                }
                try db.execute("INSERT INTO categories(id,name) VALUES(?,?)",[.text(category.id),.text(name)])
            }
            else if try db.execute("UPDATE categories SET name=? WHERE id=?",[.text(name),.text(category.id)]) == 0 { throw HistoryError.missing }
            try bumpRevision()
        }
        return category
    }

    func applyCategory(_ request: CategoryRequest) throws {
        switch request.operation {
        case .add, .rename:
            try saveCategory(id: request.category.id, name: request.category.name, inserting: request.operation == .add)
        case .remove: try deleteCategory(request.category.id, expectedName: request.category.name)
        }
    }

    func deleteCategory(_ id: String, expectedName: String? = nil) throws {
        guard id != ClipCategory.ordinary.id else { return }
        try db.transaction {
            if let expectedName, let actual = try db.query("SELECT name FROM categories WHERE id=?", [.text(id)], map: { $0.text(0) }).first,
               actual != expectedName { throw CategoryError.changed }
            // Cascading membership deletion returns every member to ordinary history.
            if try db.execute("DELETE FROM categories WHERE id=?",[.text(id)]) > 0 { try bumpRevision() }
        }
    }

    func ordinaryUnpinnedCount() throws -> Int {
        guard supportsCategories else { return 0 }
        return try db.query("SELECT COUNT(*) FROM clips WHERE id NOT IN (SELECT id FROM pins) AND id NOT IN (SELECT id FROM filing)") { $0.integer(0) }.first ?? 0
    }

    func undoDepth() throws -> Int {
        guard writable else { return 0 }
        return try db.query("SELECT COALESCE(MAX(step),0) FROM undo_rows") { $0.integer(0) }.first ?? 0
    }

    func discardUndo() throws {
        if writable { try db.execute("DELETE FROM undo_rows") }
    }

    func organize(_ action: HistoryAction, now: Date = Date()) throws {
        try db.transaction {
            let step = try undoDepth() + 1
            switch action {
            case .move(let id, let destination):
                let fields: [SQLValue] = [.integer(step), .text(id), .text(destination)]
                guard try db.execute("""
                    INSERT INTO undo_rows(step,kind,id,category) SELECT ?,'move',c.id,f.category
                    FROM clips c LEFT JOIN filing f ON f.id=c.id WHERE c.id=? AND COALESCE(f.category,'')<>?
                    """, fields) > 0 else { return }
                if destination == ClipCategory.ordinary.id { try db.execute("DELETE FROM filing WHERE id=?",[.text(id)]) }
                else { try db.execute("INSERT OR REPLACE INTO filing(id,category) VALUES(?,?)",[.text(id),.text(destination)]) }
            case .pin(let id, let enabled):
                guard try db.execute("""
                    INSERT INTO undo_rows(step,kind,id,pinned) SELECT ?,'pin',c.id,p.pinned
                    FROM clips c LEFT JOIN pins p ON p.id=c.id WHERE c.id=? AND (p.id IS NOT NULL)<>?
                    """, [.integer(step),.text(id),.integer(enabled ? 1 : 0)]) > 0 else { return }
                if enabled { try db.execute("INSERT INTO pins(id,pinned) VALUES(?,?)",[.text(id),.real(now.timeIntervalSince1970)]) }
                else { try db.execute("DELETE FROM pins WHERE id=?",[.text(id)]) }
            case .remove, .clearOrdinary:
                var values: [SQLValue] = [.integer(step)]
                let predicate: String
                if case .remove(let id) = action { predicate = "c.id=?"; values.append(.text(id)) }
                else { predicate = "p.id IS NULL AND f.id IS NULL" }
                guard try db.execute("""
                    INSERT INTO undo_rows(step,kind,id,category,pinned,content_key,preview,is_image,created,updated,uti,body,thumb)
                    SELECT ?,'delete',c.id,f.category,p.pinned,c.content_key,c.preview,c.is_image,c.created,c.updated,b.uti,b.body,b.thumb
                    FROM clips c JOIN bodies b ON b.id=c.id LEFT JOIN pins p ON p.id=c.id LEFT JOIN filing f ON f.id=c.id
                    WHERE \(predicate)
                    """,values) > 0 else { return }
                try db.execute("DELETE FROM clips WHERE id IN (SELECT id FROM undo_rows WHERE step=?)",[.integer(step)])
            }
            try bumpRevision()
        }
    }

    func undoOrganization() throws {
        try db.transaction {
            let step = try undoDepth()
            guard step > 0 else { return }
            let values: [SQLValue] = [.integer(step)]
            let kind = try db.query("SELECT kind FROM undo_rows WHERE step=? LIMIT 1",values) { $0.text(0) }.first
            if kind == "delete" {
                // A genuine subsequent copy of the same content wins its newer identity and timestamp.
                try db.execute("""
                    INSERT OR IGNORE INTO clips(id,content_key,preview,is_image,created,updated)
                    SELECT id,content_key,preview,is_image,created,updated FROM undo_rows WHERE step=?
                    """,values)
                try db.execute("""
                    INSERT OR IGNORE INTO bodies(id,uti,body,thumb) SELECT u.id,u.uti,u.body,u.thumb
                    FROM undo_rows u JOIN clips c ON c.id=u.id WHERE u.step=?
                    """,values)
            }
            if kind == "move" { try db.execute("DELETE FROM filing WHERE id IN (SELECT id FROM undo_rows WHERE step=?)",values) }
            if kind == "move" || kind == "delete" {
                try db.execute("""
                    INSERT OR IGNORE INTO filing(id,category) SELECT u.id,u.category FROM undo_rows u
                    JOIN clips c ON c.id=u.id JOIN categories g ON g.id=u.category WHERE u.step=?
                    """,values)
            }
            if kind == "pin" { try db.execute("DELETE FROM pins WHERE id IN (SELECT id FROM undo_rows WHERE step=?)",values) }
            if kind == "pin" || kind == "delete" {
                try db.execute("""
                    INSERT OR IGNORE INTO pins(id,pinned) SELECT u.id,u.pinned FROM undo_rows u
                    JOIN clips c ON c.id=u.id WHERE u.step=? AND u.pinned IS NOT NULL
                    """,values)
            }
            try db.execute("DELETE FROM undo_rows WHERE step=?",values)
            try bumpRevision()
        }
    }
}
