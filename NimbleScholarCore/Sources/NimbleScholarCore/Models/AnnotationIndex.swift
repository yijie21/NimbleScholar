import GRDB

public struct AnnotationIndex: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var paperId: Int64
    public var page: Int
    public var kind: String          // "highlight" | "note"
    public var color: String         // hex
    public var snippet: String       // text content for the list/search
    public var x: Double             // normalized 0..1 bounds
    public var y: Double
    public var width: Double
    public var height: Double
    public var createdAt: Int64
    public var updatedAt: Int64

    public static let databaseTableName = "pdf_annotations"

    enum CodingKeys: String, CodingKey {
        case id, page, kind, color, snippet, x, y, width, height
        case paperId = "paper_id", createdAt = "created_at", updatedAt = "updated_at"
    }

    public init(id: Int64?, paperId: Int64, page: Int, kind: String, color: String,
                snippet: String, x: Double, y: Double, width: Double, height: Double,
                createdAt: Int64, updatedAt: Int64) {
        self.id = id; self.paperId = paperId; self.page = page; self.kind = kind
        self.color = color; self.snippet = snippet
        self.x = x; self.y = y; self.width = width; self.height = height
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
