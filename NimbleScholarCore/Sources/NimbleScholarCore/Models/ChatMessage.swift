import GRDB

/// One message in a paper's persisted AI-chat conversation. `role` is "user" or "assistant".
public struct ChatMessage: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var paperId: Int64
    public var role: String
    public var content: String
    public var createdAt: Int64

    public static let databaseTableName = "chat_messages"

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case paperId = "paper_id"
        case createdAt = "created_at"
    }

    public init(id: Int64? = nil, paperId: Int64, role: String, content: String, createdAt: Int64 = 0) {
        self.id = id; self.paperId = paperId; self.role = role; self.content = content; self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
