import Foundation
import SwiftSoup

/// Scrapes a paper's HTML rendering for a teaser/pipeline figure so a card can show a real
/// figure (small, fast) instead of rendering the whole first PDF page. Sources, in order:
///   • arXiv: `arxiv.org/html/<id>`, then `ar5iv.org/html/<id>` (covers far more papers)
///   • any other paper: its landing HTML page (`<figure>` images, then `og:image`)
public struct ArxivFigureService {
    public let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    /// arXiv figures by id: try the official HTML, then ar5iv as a fallback.
    public func figures(forID id: String) async throws -> FigureChooser.Result {
        let bare = id.contains("v") ? String(id.prefix(while: { $0 != "v" })) : id
        let pages = [
            "https://arxiv.org/html/\(id)",
            "https://ar5iv.org/html/\(bare)",
        ]
        for page in pages {
            if let r = try? await scrape(pageURL: page).result, r.teaser != nil || r.pipeline != nil {
                return r
            }
        }
        return .init(teaser: nil, pipeline: nil)
    }

    /// Figures from an arbitrary paper landing page (CVF, publisher pages, etc.). Pages like
    /// CVF's abstract page carry no figures at all but do link the paper's arXiv version —
    /// when the page itself yields nothing, follow that link and scrape the arXiv HTML.
    /// (Link-following lives ONLY here, not in `scrape`, so it can't recurse: arXiv's own
    /// HTML pages also link to `arxiv.org/abs/…`.)
    public func figures(forPageURL page: String) async throws -> FigureChooser.Result {
        let (result, html) = try await scrape(pageURL: page)
        if result.teaser == nil, result.pipeline == nil, let id = Self.linkedArxivID(inHTML: html) {
            return try await figures(forID: id)
        }
        return result
    }

    /// Fetch one page and pick figures from it (no link-following).
    private func scrape(pageURL page: String) async throws -> (result: FigureChooser.Result, html: String) {
        guard let url = URL(string: page) else { return (.init(teaser: nil, pipeline: nil), "") }
        let (data, resp) = try await session.data(from: url)
        let base = resp.url ?? url
        let html = String(decoding: data, as: UTF8.self)
        return (Self.parse(html: html, baseURL: base), html)
    }

    /// arXiv id of the first `arxiv.org/abs/…` link on a page (CVF "Related Material"), if any.
    static func linkedArxivID(inHTML html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html),
              let link = try? doc.select("a[href*=arxiv.org/abs/]").first(),
              let href = try? link.attr("href") else { return nil }
        return ArxivService.extractID(from: href)
    }

    /// arXiv/ar5iv serve the HTML at `…/html/<id>` (no trailing slash) but reference figures
    /// relatively (`x1.png`), which must resolve to `…/html/<id>/x1.png`. Standard URL
    /// resolution would drop the `<id>` segment (treating it as a file). Unless the page URL
    /// ends in a real web-page extension, we treat it as a directory and append a slash.
    /// (An arXiv id like `2606.01234v1` contains a dot but is NOT a file, so a plain
    /// "has a dot" check would be wrong — we match known page extensions instead.)
    private static let pageExtensions: Set<String> = ["html", "htm", "xhtml", "shtml", "php", "asp", "aspx", "jsp", "pdf"]
    static func normalizedBase(_ url: URL) -> URL {
        if url.absoluteString.hasSuffix("/") { return url }
        let ext = url.pathExtension.lowercased()
        if pageExtensions.contains(ext) { return url }            // a real page file
        return URL(string: url.absoluteString + "/") ?? url       // treat as a directory
    }

    /// Parse `<figure>`/`<img>` (relative URLs resolved against `baseURL`) plus an
    /// `og:image`/`twitter:image` teaser candidate, then pick teaser + pipeline.
    static func parse(html: String, baseURL: URL) -> FigureChooser.Result {
        let base = normalizedBase(baseURL)
        guard let doc = try? SwiftSoup.parse(html, base.absoluteString) else {
            return .init(teaser: nil, pipeline: nil)
        }
        var figs: [Figure] = (try? doc.select("figure").array().compactMap { fig -> Figure? in
            guard let img = try? fig.select("img").first() else { return nil }
            let src = ((try? img.absUrl("src")) ?? "").isEmpty ? ((try? img.attr("src")) ?? "")
                                                              : ((try? img.absUrl("src")) ?? "")
            guard !src.isEmpty else { return nil }
            let alt = (try? img.attr("alt")) ?? ""
            let cap = (try? fig.select("figcaption").text()) ?? ""
            return Figure(url: src, alt: alt, caption: cap)
        }) ?? []
        // Social-card image as a last-resort teaser candidate (appended last so real figures win).
        if let og = try? doc.select("meta[property=og:image], meta[name=twitter:image]").first() {
            let abs = ((try? og.absUrl("content")) ?? "").isEmpty ? ((try? og.attr("content")) ?? "")
                                                                 : ((try? og.absUrl("content")) ?? "")
            if !abs.isEmpty { figs.append(Figure(url: abs, alt: "social card", caption: "")) }
        }
        return FigureChooser.choose(from: figs)
    }
}
