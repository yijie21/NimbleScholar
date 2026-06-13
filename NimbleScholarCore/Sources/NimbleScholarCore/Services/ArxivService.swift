import Foundation

public enum ArxivService {
    /// Matches 2606.01234 or 2606.01234v3 when the string is an arXiv URL,
    /// an `arXiv:` reference, or a bare id.
    public static func extractID(from text: String) -> String? {
        let pattern = #"(\d{4}\.\d{4,5}(v\d+)?)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        let id = String(text[r])
        let lower = text.lowercased()
        if lower.contains("arxiv") || lower.contains("/abs/") || lower.contains("/pdf/") || isBareID(text) {
            return id
        }
        return nil
    }

    private static func isBareID(_ s: String) -> Bool {
        (try? NSRegularExpression(pattern: #"^\s*\d{4}\.\d{4,5}(v\d+)?\s*$"#))?
            .firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    public static func normalizedPDFURL(absOrID: String) -> String? {
        guard let id = extractID(from: absOrID) else { return nil }
        return "https://arxiv.org/pdf/\(id)"
    }

    public static func absURL(forID id: String) -> String { "https://arxiv.org/abs/\(id)" }
    public static func htmlURL(forID id: String) -> String { "https://arxiv.org/html/\(id)" }
    public static func apiURL(forID id: String) -> URL {
        URL(string: "https://export.arxiv.org/api/query?id_list=\(id)")!
    }
}
