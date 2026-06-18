import Foundation
import GRDB

/// A saved webpage / GitHub link: a bookmark with a card figure and its own tags (kept entirely
/// separate from paper tags). One row in `links`.
public struct SavedLink: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var url: String
    public var title: String = ""
    public var detail: String = ""        // free-text description (column `description`)
    public var imageURL: String = ""      // og:image / preview figure (remote)
    public var imagePath: String = ""     // cached local copy of the figure, if any
    public var source: String = ""        // "github" | "web"
    public var createdAt: Int64 = 0
    public var updatedAt: Int64 = 0

    public static let databaseTableName = "links"

    enum Columns: String, ColumnExpression {
        case id, url, title
        case detail = "description"
        case imageURL = "image_url", imagePath = "image_path", source
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id, url, title
        case detail = "description"
        case imageURL = "image_url", imagePath = "image_path", source
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    public init(id: Int64? = nil, url: String) {
        self.id = id
        self.url = url
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// The host shown on the card (e.g. "github.com"), or the raw URL if it doesn't parse.
    public var host: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
    }

    /// A link that points at a GitHub repository (drives the card's fallback glyph + `source`).
    public var isGitHub: Bool {
        (URL(string: url)?.host ?? "").lowercased().hasSuffix("github.com")
    }
}
