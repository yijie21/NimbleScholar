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

    /// Render every paper carrying `tag` as a compact Markdown reading list — one entry per
    /// paper with its metadata, one-line summary, and links (no abstracts). Meant to be handed
    /// to an AI model as the starting point for a literature investigation. Papers are ordered
    /// newest-year-first, ties broken by title.
    public static func export(tag: String, papers: [Paper]) -> String {
        let ordered = papers.sorted {
            if $0.year != $1.year { return $0.year > $1.year }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        var out = "# Papers tagged “\(tag)”\n\n"
        out += "_\(ordered.count) paper\(ordered.count == 1 ? "" : "s") · exported from Nimble Scholar._\n\n"
        if ordered.isEmpty {
            out += "_No papers carry this tag._\n"
            return out
        }
        for (i, p) in ordered.enumerated() {
            out += "## \(i + 1). \(p.title)\n\n"
            let meta = [p.authors, p.year, p.venue].filter { !$0.isEmpty }.joined(separator: " · ")
            if !meta.isEmpty { out += "\(meta)\n\n" }
            if !p.summary.isEmpty { out += "> \(p.summary)\n\n" }
            let links = linkFields(p)
            if !links.isEmpty {
                out += "**Links:** " + links.joined(separator: " · ") + "\n\n"
            }
        }
        return out
    }

    /// Markdown link fragments for whichever of a paper's URLs are present.
    private static func linkFields(_ p: Paper) -> [String] {
        var links: [String] = []
        if !p.url.isEmpty { links.append("[Page](\(p.url))") }
        if !p.doi.isEmpty { links.append("[DOI](https://doi.org/\(p.doi))") }
        if !p.projectURL.isEmpty { links.append("[Project](\(p.projectURL))") }
        if !p.codeURL.isEmpty { links.append("[Code](\(p.codeURL))") }
        return links
    }
}
