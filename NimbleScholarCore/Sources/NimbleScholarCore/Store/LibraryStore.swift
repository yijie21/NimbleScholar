import Foundation
import GRDB

public final class LibraryStore {
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
            try db.create(virtualTable: "papers_fts", options: [.ifNotExists], using: FTS5()) { t in
                t.synchronize(withTable: "papers")
                t.column("title"); t.column("authors"); t.column("abstract")
                t.column("summary"); t.column("venue"); t.column("doi")
            }
        }
        return m
    }

    // MARK: - Reads

    public func allPapers() throws -> [Paper] {
        try dbQueue.read { try Paper.order(Paper.Columns.updatedAt.desc).fetchAll($0) }
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

    /// Turn a raw user query into a prefix FTS query: `transformer mod` -> `transformer* mod*`
    static func ftsQuery(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace)
            .map { $0.replacingOccurrences(of: "\"", with: "") + "*" }
            .joined(separator: " ")
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
}
