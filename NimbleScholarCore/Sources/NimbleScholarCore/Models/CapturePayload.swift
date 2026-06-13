public struct CapturePayload: Codable {
    public var url: String = ""
    public var title: String?
    public var authors: String?
    public var doi: String?
    public var pdf_url: String?
    public var teaser_url: String?
    public var abstract: String?
    public var source: String?
    public var tags: String?     // comma/semicolon separated, like today

    public init() {}
}
