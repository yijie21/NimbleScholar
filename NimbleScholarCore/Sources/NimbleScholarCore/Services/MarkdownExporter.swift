import Foundation

/// Render a paper and its highlights/notes as a Markdown document.
public enum MarkdownExporter {
    public static func export(paper: Paper, annotations: [AnnotationIndex]) -> String {
        var out = "# \(paper.title)\n\n"
        let meta = [paper.authors, paper.venue, paper.year].filter { !$0.isEmpty }.joined(separator: " · ")
        if !meta.isEmpty { out += "_\(meta)_\n\n" }
        if !paper.url.isEmpty { out += "<\(paper.url)>\n\n" }
        if !paper.summary.isEmpty { out += "> \(paper.summary)\n\n" }
        out += "## Annotations\n\n"
        if annotations.isEmpty {
            out += "_No annotations._\n"
        } else {
            for a in annotations.sorted(by: { $0.page < $1.page }) {
                let label = a.kind == "note" ? "📝" : "🖍"
                out += "- \(label) **p.\(a.page)** — \(a.snippet)\n"
            }
        }
        return out
    }
}
