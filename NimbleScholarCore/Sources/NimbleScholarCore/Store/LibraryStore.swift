import Foundation
import GRDB

/// Thread-safe (GRDB `DatabaseQueue` serializes access), so it's safe to use from background tasks.
public final class LibraryStore: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }

    /// On-disk store at ~/Library/Application Support/Nimble Scholar/paper_app.sqlite3
    public static func makeDefault() throws -> LibraryStore {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Nimble Scholar", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Distinct filename so we never collide with the old Python prototype's
        // `paper_app.sqlite3` (which has the same table names but no GRDB migration
        // bookkeeping, causing "table papers already exists").
        let dbURL = dir.appendingPathComponent("nimblescholar.sqlite3")
        return try LibraryStore(dbQueue: try DatabaseQueue(path: dbURL.path))
    }

    /// In-memory store (used as a fallback if on-disk setup fails).
    public static func makeInMemory() throws -> LibraryStore {
        try LibraryStore(dbQueue: DatabaseQueue())
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "papers", options: [.ifNotExists]) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                for col in ["authors", "year", "venue", "doi", "url", "pdf_url", "pdf_path",
                            "summary", "teaser_url", "pipeline_url", "abstract", "notes", "source"] {
                    t.column(col, .text).notNull().defaults(to: "")
                }
                t.column("created_at", .integer).notNull()
                t.column("updated_at", .integer).notNull()
            }
            try db.create(table: "tags", options: [.ifNotExists]) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
            }
            try db.create(table: "paper_tags", options: [.ifNotExists]) { t in
                t.column("paper_id", .integer).notNull()
                    .references("papers", onDelete: .cascade)
                t.column("tag_id", .integer).notNull()
                    .references("tags", onDelete: .cascade)
                t.primaryKey(["paper_id", "tag_id"])
            }
            try db.create(table: "pdf_annotations", options: [.ifNotExists]) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("paper_id", .integer).notNull()
                    .references("papers", onDelete: .cascade)
                t.column("page", .integer).notNull()
                t.column("kind", .text).notNull().defaults(to: "highlight")
                t.column("color", .text).notNull().defaults(to: "#ffd966")
                t.column("snippet", .text).notNull().defaults(to: "")
                t.column("x", .double).notNull().defaults(to: 0)
                t.column("y", .double).notNull().defaults(to: 0)
                t.column("width", .double).notNull().defaults(to: 0)
                t.column("height", .double).notNull().defaults(to: 0)
                t.column("created_at", .integer).notNull()
                t.column("updated_at", .integer).notNull()
            }
        }
        m.registerMigration("v2-fts") { db in
            try db.create(virtualTable: "papers_fts", using: FTS5()) { t in
                t.synchronize(withTable: "papers")
                t.column("title"); t.column("authors"); t.column("abstract")
                t.column("summary"); t.column("venue"); t.column("doi")
            }
        }
        m.registerMigration("v3-read") { db in
            try db.alter(table: "papers") { t in
                t.add(column: "read", .integer).notNull().defaults(to: 0)
            }
        }
        m.registerMigration("v4-chat") { db in
            try db.create(table: "chat_messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("paper_id", .integer).notNull().references("papers", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("created_at", .integer).notNull()
            }
        }
        m.registerMigration("v5-links") { db in
            try db.alter(table: "papers") { t in
                t.add(column: "project_url", .text).notNull().defaults(to: "")
                t.add(column: "code_url", .text).notNull().defaults(to: "")
                t.add(column: "links_scanned", .integer).notNull().defaults(to: 0)
            }
        }
        m.registerMigration("v6-code-ready") { db in
            try db.alter(table: "papers") { t in
                t.add(column: "code_ready", .integer).notNull().defaults(to: 0)
            }
        }
        return m
    }

    // MARK: - Reads

    public func allPapers() throws -> [Paper] {
        try dbQueue.read { try Paper.order(Paper.Columns.updatedAt.desc).fetchAll($0) }
    }

    /// Fetch one paper by primary key, or nil if it doesn't exist.
    public func paper(id: Int64) throws -> Paper? {
        try dbQueue.read { try Paper.fetchOne($0, key: id) }
    }

    /// Find an existing paper that a capture URL would duplicate: by arXiv id (matched against
    /// url/pdf_url/doi, version-insensitive) or by exact URL. Used for duplicate detection.
    public func existingPaper(forCaptureURL url: String) throws -> Paper? {
        try dbQueue.read { db -> Paper? in
            if let id = ArxivService.extractID(from: url) {
                let bare = id.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
                if let p = try Paper.fetchOne(db, sql: """
                    SELECT * FROM papers WHERE url LIKE ? OR pdf_url LIKE ? OR doi LIKE ? LIMIT 1
                """, arguments: ["%\(bare)%", "%\(bare)%", "%\(bare)%"]) { return p }
            }
            return try Paper.fetchOne(db, sql: "SELECT * FROM papers WHERE url = ? LIMIT 1", arguments: [url])
        }
    }

    public func tagCounts() throws -> [TagCount] {
        try dbQueue.read { db in
            try TagCount.fetchAll(db, sql: """
                SELECT t.name AS name, COUNT(pt.paper_id) AS count
                FROM tags t JOIN paper_tags pt ON pt.tag_id = t.id
                GROUP BY t.id ORDER BY t.name
            """)
        }
    }

    public func searchPapers(query: String?, tag: String?) throws -> [Paper] {
        try dbQueue.read { db in
            var sql = "SELECT papers.* FROM papers"
            var args = [DatabaseValueConvertible]()
            var wheres = [String]()
            if let tag, !tag.isEmpty {
                sql += """
                 JOIN paper_tags pt ON pt.paper_id = papers.id
                 JOIN tags t ON t.id = pt.tag_id
                """
                wheres.append("t.name = ?"); args.append(tag)
            }
            if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                wheres.append("papers.id IN (SELECT rowid FROM papers_fts WHERE papers_fts MATCH ?)")
                args.append(Self.ftsQuery(query))
            }
            if !wheres.isEmpty { sql += " WHERE " + wheres.joined(separator: " AND ") }
            sql += " ORDER BY papers.updated_at DESC"
            return try Paper.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Turn a raw user query into a safe prefix FTS query. Each token becomes a
    /// double-quoted FTS string literal with a trailing `*`, so punctuation and FTS
    /// operators can never be interpreted as syntax: `c++ mod` -> `"c++"* "mod"*`.
    static func ftsQuery(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace)
            .map { token -> String in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }
            .joined(separator: " ")
    }

    /// Papers with no tags (for the "Untagged" smart filter).
    public func untaggedPapers(query: String?) throws -> [Paper] {
        try dbQueue.read { db in
            var sql = "SELECT papers.* FROM papers WHERE papers.id NOT IN (SELECT paper_id FROM paper_tags)"
            var args = [DatabaseValueConvertible]()
            if let q = query, !q.trimmingCharacters(in: .whitespaces).isEmpty {
                sql += " AND papers.id IN (SELECT rowid FROM papers_fts WHERE papers_fts MATCH ?)"
                args.append(Self.ftsQuery(q))
            }
            sql += " ORDER BY papers.updated_at DESC"
            return try Paper.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    public func renameTag(_ old: String, to new: String) throws {
        let names = TagNormalizer.normalize(new)
        guard let n = names.first else { return }
        try dbQueue.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO tags(name) VALUES (?)", arguments: [n])
            let newID = try Int64.fetchOne(db, sql: "SELECT id FROM tags WHERE name = ?", arguments: [n])!
            guard let oldID = try Int64.fetchOne(db, sql: "SELECT id FROM tags WHERE name = ?", arguments: [old]),
                  oldID != newID else { return }
            try db.execute(sql: "UPDATE OR IGNORE paper_tags SET tag_id = ? WHERE tag_id = ?", arguments: [newID, oldID])
            try db.execute(sql: "DELETE FROM paper_tags WHERE tag_id = ?", arguments: [oldID])
            try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [oldID])
        }
    }

    public func deleteTag(_ name: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM paper_tags WHERE tag_id IN (SELECT id FROM tags WHERE name = ?)", arguments: [name])
            try db.execute(sql: "DELETE FROM tags WHERE name = ?", arguments: [name])
        }
    }

    /// All paper→tags in a single query (avoids N+1 lookups when rendering the library).
    public func allTagsByPaper() throws -> [Int64: [String]] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT pt.paper_id AS pid, t.name AS name
                FROM paper_tags pt JOIN tags t ON t.id = pt.tag_id
                ORDER BY t.name
            """)
            var map: [Int64: [String]] = [:]
            for row in rows {
                let pid: Int64 = row["pid"]
                map[pid, default: []].append(row["name"])
            }
            return map
        }
    }

    public func tags(forPaper id: Int64) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT t.name FROM tags t
                JOIN paper_tags pt ON pt.tag_id = t.id
                WHERE pt.paper_id = ? ORDER BY t.name
            """, arguments: [id])
        }
    }

    // MARK: - Writes

    private func now() -> Int64 { Int64(Date().timeIntervalSince1970) }

    @discardableResult
    public func create(_ paper: Paper) throws -> Paper {
        var p = paper
        let ts = now(); p.createdAt = ts; p.updatedAt = ts
        try dbQueue.write { try p.insert($0) }
        return p
    }

    @discardableResult
    public func update(_ paper: Paper) throws -> Paper {
        var p = paper; p.updatedAt = now()
        try dbQueue.write { try p.update($0) }
        return p
    }

    public func deletePaper(id: Int64) throws {
        _ = try dbQueue.write { try Paper.deleteOne($0, key: id) }
    }

    /// Mark a paper read/unread.
    public func setRead(paperID: Int64, read: Bool) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE papers SET read = ?, updated_at = ? WHERE id = ?",
                           arguments: [read ? 1 : 0, Int64(Date().timeIntervalSince1970), paperID])
        }
    }

    public func setTags(paperID: Int64, tags rawTags: [String]) throws {
        let names = TagNormalizer.normalize(rawTags)
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM paper_tags WHERE paper_id = ?", arguments: [paperID])
            for name in names {
                try db.execute(sql: "INSERT OR IGNORE INTO tags(name) VALUES (?)", arguments: [name])
                let tagID = try Int64.fetchOne(db, sql: "SELECT id FROM tags WHERE name = ?", arguments: [name])!
                try db.execute(sql: "INSERT OR IGNORE INTO paper_tags(paper_id, tag_id) VALUES (?, ?)",
                               arguments: [paperID, tagID])
            }
            // prune now-orphaned tags so the sidebar stays clean
            try db.execute(sql: """
                DELETE FROM tags WHERE id NOT IN (SELECT DISTINCT tag_id FROM paper_tags)
            """)
        }
    }

    // MARK: - Annotation index

    @discardableResult
    public func upsertAnnotation(_ a: inout AnnotationIndex) throws -> AnnotationIndex {
        let ts = now()
        if a.createdAt == 0 { a.createdAt = ts }
        a.updatedAt = ts
        try dbQueue.write { try a.save($0) }
        return a
    }

    public func annotations(forPaper id: Int64) throws -> [AnnotationIndex] {
        try dbQueue.read { db in
            try AnnotationIndex
                .filter(sql: "paper_id = ?", arguments: [id])
                .order(sql: "page ASC, created_at ASC")
                .fetchAll(db)
        }
    }

    public func deleteAnnotation(id: Int64) throws {
        _ = try dbQueue.write { try AnnotationIndex.deleteOne($0, key: id) }
    }

    // MARK: - Chat history

    /// A paper's saved AI-chat messages, oldest first.
    public func chatMessages(forPaper id: Int64) throws -> [ChatMessage] {
        try dbQueue.read { db in
            try ChatMessage
                .filter(sql: "paper_id = ?", arguments: [id])
                .order(sql: "created_at ASC, id ASC")
                .fetchAll(db)
        }
    }

    /// Append a message; stamps `created_at` if unset and returns the saved row (with id).
    @discardableResult
    public func appendChatMessage(_ message: ChatMessage) throws -> ChatMessage {
        var m = message
        if m.createdAt == 0 { m.createdAt = Int64(Date().timeIntervalSince1970) }
        try dbQueue.write { try m.insert($0) }
        return m
    }

    /// Delete a paper's whole conversation.
    public func clearChat(paperID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM chat_messages WHERE paper_id = ?", arguments: [paperID])
        }
    }

    // MARK: - Change observation

    /// Calls `onChange` (on the main queue) whenever papers/tags/annotations change —
    /// including writes from the capture server — so the UI can refresh live.
    /// Hold the returned token; cancellation stops the observation.
    public func observeChanges(_ onChange: @escaping () -> Void) -> ObservationToken {
        let observation = ValueObservation.tracking { db -> [Int64] in
            let papers = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM papers") ?? 0
            let links = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM paper_tags") ?? 0
            let annos = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM pdf_annotations") ?? 0
            // MAX(updated_at) makes edits (not just inserts/deletes) trigger a refresh.
            let touched = try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(updated_at), 0) FROM papers") ?? 0
            return [papers, links, annos, touched]
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

/// Opaque cancellation handle so callers don't need to import GRDB.
public final class ObservationToken {
    private let cancellable: AnyDatabaseCancellable
    init(_ cancellable: AnyDatabaseCancellable) { self.cancellable = cancellable }
    public func cancel() { cancellable.cancel() }
}
