import Foundation
import GRDB

/// Saved-link persistence: CRUD, an independent tag vocabulary, and a change observation. Mirrors
/// the paper store APIs but against `links` / `link_tags` / `link_tag_map`, so link tags and paper
/// tags stay completely separate.
extension LibraryStore {
    private func nowTS() -> Int64 { Int64(Date().timeIntervalSince1970) }

    // MARK: Reads

    public func allLinks() throws -> [SavedLink] {
        try dbQueue.read { try SavedLink.order(SavedLink.Columns.updatedAt.desc).fetchAll($0) }
    }

    public func link(id: Int64) throws -> SavedLink? {
        try dbQueue.read { try SavedLink.fetchOne($0, key: id) }
    }

    /// An existing link with the same URL (used to dedupe captures instead of inserting twice).
    public func existingLink(forURL url: String) throws -> SavedLink? {
        try dbQueue.read { try SavedLink.fetchOne($0, sql: "SELECT * FROM links WHERE url = ? LIMIT 1", arguments: [url]) }
    }

    /// Links matching an optional free-text query (title/url/description LIKE) and/or an exact tag.
    public func searchLinks(query: String?, tag: String?) throws -> [SavedLink] {
        try dbQueue.read { db in
            var sql = "SELECT links.* FROM links"
            var args = [DatabaseValueConvertible]()
            var wheres = [String]()
            if let tag, !tag.isEmpty {
                sql += " JOIN link_tag_map m ON m.link_id = links.id JOIN link_tags t ON t.id = m.tag_id"
                wheres.append("t.name = ?"); args.append(tag)
            }
            if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                let like = "%\(query.trimmingCharacters(in: .whitespaces))%"
                wheres.append("(links.title LIKE ? OR links.url LIKE ? OR links.description LIKE ?)")
                args.append(contentsOf: [like, like, like])
            }
            if !wheres.isEmpty { sql += " WHERE " + wheres.joined(separator: " AND ") }
            sql += " ORDER BY links.updated_at DESC"
            return try SavedLink.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Links with no tags (for the "Untagged" filter).
    public func untaggedLinks(query: String?) throws -> [SavedLink] {
        try dbQueue.read { db in
            var sql = "SELECT links.* FROM links WHERE links.id NOT IN (SELECT link_id FROM link_tag_map)"
            var args = [DatabaseValueConvertible]()
            if let q = query, !q.trimmingCharacters(in: .whitespaces).isEmpty {
                let like = "%\(q.trimmingCharacters(in: .whitespaces))%"
                sql += " AND (links.title LIKE ? OR links.url LIKE ? OR links.description LIKE ?)"
                args.append(contentsOf: [like, like, like])
            }
            sql += " ORDER BY links.updated_at DESC"
            return try SavedLink.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    public func linkTagCounts() throws -> [TagCount] {
        try dbQueue.read { try TagSQL.counts($0, .links) }
    }

    public func allTagsByLink() throws -> [Int64: [String]] {
        try dbQueue.read { try TagSQL.allByOwner($0, .links) }
    }

    public func tags(forLink id: Int64) throws -> [String] {
        try dbQueue.read { try TagSQL.tags($0, .links, ownerID: id) }
    }

    // MARK: Writes

    @discardableResult
    public func createLink(_ link: SavedLink) throws -> SavedLink {
        var l = link
        let ts = nowTS(); l.createdAt = ts; l.updatedAt = ts
        try dbQueue.write { try l.insert($0) }
        return l
    }

    @discardableResult
    public func updateLink(_ link: SavedLink) throws -> SavedLink {
        var l = link; l.updatedAt = nowTS()
        try dbQueue.write { try l.update($0) }
        return l
    }

    public func deleteLink(id: Int64) throws {
        _ = try dbQueue.write { try SavedLink.deleteOne($0, key: id) }
    }

    public func setLinkTags(linkID: Int64, tags rawTags: [String]) throws {
        let names = TagNormalizer.normalize(rawTags)
        // bumpUpdatedAt: link change-observation tracks MAX(links.updated_at), so touch the row.
        try dbQueue.write { try TagSQL.setTags($0, .links, ownerID: linkID, names: names, bumpUpdatedAt: true) }
    }

    public func renameLinkTag(_ old: String, to new: String) throws {
        guard let n = TagNormalizer.normalize(new).first else { return }
        try dbQueue.write { try TagSQL.rename($0, .links, old: old, new: n) }
    }

    public func deleteLinkTag(_ name: String) throws {
        try dbQueue.write { try TagSQL.delete($0, .links, name: name) }
    }

    // MARK: Change observation

    /// Calls `onChange` (on the main queue) whenever links or their tags change — including captures
    /// from the embedded server — so the Links grid refreshes live. Hold the returned token.
    public func observeLinkChanges(_ onChange: @escaping () -> Void) -> ObservationToken {
        let observation = ValueObservation.tracking { db -> [Int64] in
            let links = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM links") ?? 0
            let maps = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM link_tag_map") ?? 0
            let touched = try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(updated_at), 0) FROM links") ?? 0
            return [links, maps, touched]
        }
        let cancellable = observation.start(
            in: dbQueue,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { _ in onChange() }
        )
        return ObservationToken(cancellable)
    }
}
