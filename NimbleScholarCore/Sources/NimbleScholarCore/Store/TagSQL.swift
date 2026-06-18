import Foundation
import GRDB

/// Names of the three tables that back one tag vocabulary. Papers and links each have their own
/// (kept separate), but the SQL is identical modulo these names — so it lives once in `TagSQL`.
struct TagTables {
    let tags: String       // tag-name table:      "tags" / "link_tags"
    let map: String        // owner↔tag join:       "paper_tags" / "link_tag_map"
    let owner: String      // owner FK column:      "paper_id" / "link_id"
    let entity: String     // owning row table:     "papers" / "links"

    static let papers = TagTables(tags: "tags", map: "paper_tags", owner: "paper_id", entity: "papers")
    static let links  = TagTables(tags: "link_tags", map: "link_tag_map", owner: "link_id", entity: "links")
}

/// The shared tag-vocabulary SQL, parameterized by `TagTables`. All identifiers are compile-time
/// constants from `TagTables`, never user input, so string interpolation here is injection-safe.
enum TagSQL {
    static func counts(_ db: Database, _ s: TagTables) throws -> [TagCount] {
        try TagCount.fetchAll(db, sql: """
            SELECT t.name AS name, COUNT(m.\(s.owner)) AS count
            FROM \(s.tags) t JOIN \(s.map) m ON m.tag_id = t.id
            GROUP BY t.id ORDER BY t.name
        """)
    }

    static func allByOwner(_ db: Database, _ s: TagTables) throws -> [Int64: [String]] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT m.\(s.owner) AS oid, t.name AS name
            FROM \(s.map) m JOIN \(s.tags) t ON t.id = m.tag_id
            ORDER BY t.name
        """)
        var map: [Int64: [String]] = [:]
        for row in rows {
            let oid: Int64 = row["oid"]
            map[oid, default: []].append(row["name"])
        }
        return map
    }

    static func tags(_ db: Database, _ s: TagTables, ownerID: Int64) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT t.name FROM \(s.tags) t
            JOIN \(s.map) m ON m.tag_id = t.id
            WHERE m.\(s.owner) = ? ORDER BY t.name
        """, arguments: [ownerID])
    }

    /// Replace an owner's tags with `names`. `bumpUpdatedAt` touches the owning row so a change
    /// observation that tracks `MAX(updated_at)` still fires even when the tag count is unchanged.
    static func setTags(_ db: Database, _ s: TagTables, ownerID: Int64, names: [String], bumpUpdatedAt: Bool) throws {
        try db.execute(sql: "DELETE FROM \(s.map) WHERE \(s.owner) = ?", arguments: [ownerID])
        for name in names {
            try db.execute(sql: "INSERT OR IGNORE INTO \(s.tags)(name) VALUES (?)", arguments: [name])
            let tagID = try Int64.fetchOne(db, sql: "SELECT id FROM \(s.tags) WHERE name = ?", arguments: [name])!
            try db.execute(sql: "INSERT OR IGNORE INTO \(s.map)(\(s.owner), tag_id) VALUES (?, ?)",
                           arguments: [ownerID, tagID])
        }
        if bumpUpdatedAt {
            try db.execute(sql: "UPDATE \(s.entity) SET updated_at = ? WHERE id = ?",
                           arguments: [Int64(Date().timeIntervalSince1970), ownerID])
        }
        // Prune now-orphaned tag names so the sidebar stays clean.
        try db.execute(sql: "DELETE FROM \(s.tags) WHERE id NOT IN (SELECT DISTINCT tag_id FROM \(s.map))")
    }

    static func rename(_ db: Database, _ s: TagTables, old: String, new: String) throws {
        try db.execute(sql: "INSERT OR IGNORE INTO \(s.tags)(name) VALUES (?)", arguments: [new])
        let newID = try Int64.fetchOne(db, sql: "SELECT id FROM \(s.tags) WHERE name = ?", arguments: [new])!
        guard let oldID = try Int64.fetchOne(db, sql: "SELECT id FROM \(s.tags) WHERE name = ?", arguments: [old]),
              oldID != newID else { return }
        try db.execute(sql: "UPDATE OR IGNORE \(s.map) SET tag_id = ? WHERE tag_id = ?", arguments: [newID, oldID])
        try db.execute(sql: "DELETE FROM \(s.map) WHERE tag_id = ?", arguments: [oldID])
        try db.execute(sql: "DELETE FROM \(s.tags) WHERE id = ?", arguments: [oldID])
    }

    static func delete(_ db: Database, _ s: TagTables, name: String) throws {
        try db.execute(sql: "DELETE FROM \(s.map) WHERE tag_id IN (SELECT id FROM \(s.tags) WHERE name = ?)", arguments: [name])
        try db.execute(sql: "DELETE FROM \(s.tags) WHERE name = ?", arguments: [name])
    }
}
