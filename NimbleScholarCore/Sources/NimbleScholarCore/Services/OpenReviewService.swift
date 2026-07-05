import Foundation

/// OpenReview papers (openreview.net). The website is a JS app behind a browser check, so
/// scraping its HTML never works from URLSession — metadata comes from the public notes API
/// instead: api2.openreview.net (venues ≥ ~2023) with api.openreview.net (v1) as fallback.
public enum OpenReviewService {
    /// Extract the note id from an OpenReview URL:
    /// `…/forum?id=X`, `…/pdf?id=X`, `…/attachment?id=X&name=…` (query `id` wins over `noteId`,
    /// which points at a review comment — the paper is the forum's root note).
    public static func extractID(from text: String) -> String? {
        guard text.lowercased().contains("openreview.net"),
              let comps = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let id = comps.queryItems?.first(where: { $0.name == "id" })?.value,
              !id.isEmpty else { return nil }
        return id
    }

    public static func forumURL(forID id: String) -> String { "https://openreview.net/forum?id=\(id)" }
    public static func pdfURL(forID id: String) -> String { "https://openreview.net/pdf?id=\(id)" }

    /// Notes API endpoints to try in order: v2 first (current venues), then v1 (pre-2023).
    public static func apiURLs(forID id: String) -> [URL] {
        let q = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return [
            URL(string: "https://api2.openreview.net/notes?forum=\(q)")!,
            URL(string: "https://api.openreview.net/notes?forum=\(q)")!,
        ]
    }

    /// Parse a `/notes?forum=` response (either API generation) into PaperMetadata.
    /// Returns nil when the response has no usable root note (e.g. v1 for a v2-only paper).
    public static func parseNotes(_ data: Data, id: String) -> PaperMetadata? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let notes = json["notes"] as? [[String: Any]], !notes.isEmpty else { return nil }
        // The paper is the forum's root note (replies/reviews share the same forum id).
        let note = notes.first { ($0["id"] as? String) == id }
            ?? notes.first { ($0["id"] as? String) == ($0["forum"] as? String) }
            ?? notes[0]
        guard let content = note["content"] as? [String: Any] else { return nil }

        // API v2 wraps every field as {"value": …}; v1 stores the value directly.
        func field(_ name: String) -> Any? {
            guard let raw = content[name] else { return nil }
            if let wrapped = raw as? [String: Any], let v = wrapped["value"] { return v }
            return raw
        }
        func string(_ name: String) -> String {
            (field(name) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        var m = PaperMetadata()
        m.title = string("title")
        m.abstract = string("abstract")
        if let list = field("authors") as? [String] {
            m.authors = list.filter { !$0.isEmpty }.joined(separator: ", ")
        } else {
            m.authors = string("authors")
        }
        m.year = MetadataService.year(in: string("venue"))
        if m.year.isEmpty, let stamp = (note["pdate"] ?? note["cdate"]) as? Double {
            let date = Date(timeIntervalSince1970: stamp / 1000)
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC") ?? .current
            m.year = String(cal.component(.year, from: date))
        }
        m.pdfURL = pdfURL(forID: id)
        guard !m.title.isEmpty else { return nil }
        return m
    }
}
