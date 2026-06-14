import GRDB

/// A normalized (lowercased) tag name. One row in `tags`; orphaned tags are pruned by the store.
public struct Tag: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var name: String
    public static let databaseTableName = "tags"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
    public init(id: Int64? = nil, name: String) { self.id = id; self.name = name }
}

/// The many-to-many join between papers and tags.
public struct PaperTag: Codable, FetchableRecord, PersistableRecord {
    public var paperId: Int64
    public var tagId: Int64
    public static let databaseTableName = "paper_tags"
    enum CodingKeys: String, CodingKey { case paperId = "paper_id", tagId = "tag_id" }
}

/// A tag plus how many papers currently use it (for the sidebar).
public struct TagCount: Codable, Hashable, FetchableRecord {
    public var name: String
    public var count: Int
}
