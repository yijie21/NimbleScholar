import Foundation

public enum BibTeXExporter {
    public static func export(_ papers: [Paper]) -> String {
        papers.map(entry).joined(separator: "\n\n") + "\n"
    }

    static func entry(_ p: Paper) -> String {
        var lines = ["@article{\(citeKey(p)),"]
        func field(_ k: String, _ v: String) { if !v.isEmpty { lines.append("  \(k) = {\(v)},") } }
        field("title", p.title)
        field("author", p.authors)
        field("year", p.year)
        field("journal", p.venue)
        field("doi", p.doi)
        field("url", p.url)
        if lines.last?.hasSuffix(",") == true { lines[lines.count - 1].removeLast() }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    static func citeKey(_ p: Paper) -> String {
        let lastName = p.authors.split(separator: ",").first
            .map { $0.split(separator: " ").first.map(String.init) ?? String($0) } ?? "anon"
        let surname = lastName.lowercased().filter { $0.isLetter }
        return "\(surname.isEmpty ? "anon" : surname)\(p.year)"
    }
}
