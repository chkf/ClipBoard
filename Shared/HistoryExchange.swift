import Foundation

struct HistoryVersion: Codable, Equatable {
    let id: String
    let revision: Int
}

struct HistoryReceipt: Codable {
    let local: HistoryVersion
    let received: HistoryVersion?
}

extension HistoryStore {
    func receipt() throws -> HistoryReceipt {
        guard let result = try db.query("""
            SELECT identity,revision,peer,seen FROM replica CROSS JOIN state
            """, map: { row in
                HistoryReceipt(local: HistoryVersion(id: row.text(0), revision: row.integer(1)),
                               received: row.isNull(2) ? nil : HistoryVersion(id: row.text(2), revision: row.integer(3)))
            }).first else { throw HistoryError.missing }
        return result
    }

    // VACUUM INTO takes a consistent, compact snapshot and excludes deleted payloads.
    func exportHistory(to url: URL) throws {
        guard privateDirectory != nil else { throw HistoryError.sharedContainer }
        try db.execute("VACUUM INTO ?", [.text(url.path)])
    }

    func mergeHistory(from url: URL, expectedID: String, fromMainApp: Bool, now: Date = Date()) throws {
        guard privateDirectory != nil, !readOnly else { throw HistoryError.sharedContainer }
        try db.execute("ATTACH DATABASE ? AS incoming", [.text(url.path)])
        defer { _ = try? db.execute("DETACH DATABASE incoming") }
        try db.transaction {
            let peer = try db.query("SELECT identity,revision FROM incoming.replica CROSS JOIN incoming.state") {
                HistoryVersion(id: $0.text(0), revision: $0.integer(1))
            }.first
            guard let peer, peer.id == expectedID else { throw HistoryError.unreadable }
            let previous = try receipt()
            if let prior = previous.received, prior.id == peer.id, prior.revision >= peer.revision { return }
            var changed = try db.execute("""
                UPDATE replica SET cleared=(SELECT cleared FROM incoming.replica)
                WHERE cleared<(SELECT cleared FROM incoming.replica)
                """)
            changed += try db.execute("""
                INSERT INTO removed SELECT content_key,deleted FROM incoming.removed
                WHERE deleted>(SELECT cleared FROM replica)
                ON CONFLICT(content_key) DO UPDATE SET deleted=excluded.deleted WHERE excluded.deleted>removed.deleted
                """)
            changed += try db.execute("""
                DELETE FROM clips WHERE updated<=(SELECT cleared FROM replica)
                OR EXISTS(SELECT 1 FROM removed WHERE removed.content_key=clips.content_key AND removed.deleted>=clips.updated)
                """)
            if fromMainApp {
                changed += try db.execute("""
                    UPDATE state SET (days,auto_switch)=(SELECT days,auto_switch FROM incoming.state)
                    WHERE (days,auto_switch)<>(SELECT days,auto_switch FROM incoming.state)
                    """)
            } else {
                changed += try db.execute("UPDATE state SET configured=1 WHERE configured=0")
            }
            let cutoff = now.timeIntervalSince1970 - Double(try state().settings.retention) * 86_400
            changed += try db.execute("DELETE FROM clips WHERE updated<=?", [.real(cutoff)])
            changed += try db.execute("""
                INSERT INTO clips(id,content_key,preview,is_image,created,updated)
                SELECT s.id,s.content_key,s.preview,s.is_image,s.created,s.updated FROM incoming.clips s
                WHERE s.updated>max(?,(SELECT cleared FROM replica))
                AND NOT EXISTS(SELECT 1 FROM removed WHERE content_key=s.content_key AND deleted>=s.updated)
                ON CONFLICT(content_key) DO UPDATE SET updated=max(clips.updated,excluded.updated),
                    created=min(clips.created,excluded.created)
                WHERE excluded.updated>clips.updated OR excluded.created<clips.created
                """, [.real(cutoff)])
            changed += try db.execute("""
                INSERT INTO bodies(id,uti,body,thumb)
                SELECT d.id,b.uti,b.body,b.thumb FROM incoming.clips s
                JOIN clips d ON d.content_key=s.content_key JOIN incoming.bodies b ON b.id=s.id
                WHERE NOT EXISTS(SELECT 1 FROM bodies WHERE id=d.id)
                """)
            try db.execute("DELETE FROM removed WHERE deleted<=max((SELECT cleared FROM replica),?)",
                           [.real(now.timeIntervalSince1970 - 90 * 86_400)])
            try db.execute("UPDATE replica SET peer=?,seen=?", [.text(peer.id), .integer(peer.revision)])
            if changed > 0 { try db.execute("UPDATE state SET revision=revision+1") }
        }
    }
}
