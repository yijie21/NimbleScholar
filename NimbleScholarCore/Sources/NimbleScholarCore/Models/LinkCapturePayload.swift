/// The JSON body the browser extension POSTs to `/api/capture-link` to save a webpage / GitHub
/// link. Field names are snake_case to match the extension; only `url` is required.
public struct LinkCapturePayload: Codable {
    public var url: String = ""
    public var title: String?
    public var image_url: String?
    public var description: String?
    public var source: String?
    public var tags: String?     // comma/semicolon separated

    public init() {}
}
