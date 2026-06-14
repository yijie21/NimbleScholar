/// The JSON body the browser extension / bookmarklet POSTs to `/api/capture`.
/// Field names are snake_case to match the extension; only `url` is required.
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
