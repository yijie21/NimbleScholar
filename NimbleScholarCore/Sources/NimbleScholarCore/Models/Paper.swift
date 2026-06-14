import Foundation
import GRDB

public struct Paper: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var title: String
    public var authors: String = ""
    public var year: String = ""
    public var venue: String = ""
    public var doi: String = ""
    public var url: String = ""
    public var pdfURL: String = ""
    public var pdfPath: String = ""
    public var summary: String = ""
    public var teaserURL: String = ""
    public var pipelineURL: String = ""
    public var abstract: String = ""
    public var notes: String = ""
    public var source: String = ""
    public var isRead: Bool = false
    public var createdAt: Int64 = 0
    public var updatedAt: Int64 = 0

    public static let databaseTableName = "papers"

    enum Columns: String, ColumnExpression {
        case id, title, authors, year, venue, doi, url
        case pdfURL = "pdf_url", pdfPath = "pdf_path", summary
        case teaserURL = "teaser_url", pipelineURL = "pipeline_url"
        case abstract, notes, source
        case isRead = "read"
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    // Map Swift camelCase properties to snake_case columns for GRDB row coding.
    enum CodingKeys: String, CodingKey {
        case id, title, authors, year, venue, doi, url
        case pdfURL = "pdf_url", pdfPath = "pdf_path", summary
        case teaserURL = "teaser_url", pipelineURL = "pipeline_url"
        case abstract, notes, source
        case isRead = "read"
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    public init(id: Int64? = nil, title: String) {
        self.id = id
        self.title = title
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
