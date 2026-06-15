import Foundation
import PDFKit
import NimbleScholarCore

/// Gathers a paper's link candidates and classifies them via `LinkExtractor`.
/// Inputs: the cached PDF's link annotations + text, and the abstract/landing HTML page.
/// If a project page is found but no GitHub link, follows the project page to find one.
enum LinkFinder {
    static func find(for paper: Paper, session: URLSession, followProject: Bool = true) async -> ExtractedLinks {
        let text = pdfText(for: paper)
        let anchors = await pageAnchors(for: paper, session: session)
        var links = LinkExtractor.extract(text: text, anchors: anchors)

        if followProject, let project = links.projectURL, links.codeURL == nil,
           let data = try? await fetch(project, session: session) {
            let projectAnchors = LinkExtractor.anchors(inHTMLData: data)
            let projectText = String(data: data, encoding: .utf8) ?? ""
            links.codeURL = LinkExtractor.codeURL(inAnchors: projectAnchors)
                ?? LinkExtractor.codeURL(in: projectText)
        }
        return links
    }

    /// PDF link-annotation URLs (clean) + page text (fallback), joined into one blob.
    private static func pdfText(for paper: Paper) -> String {
        guard paper.hasLocalPDF,
              let doc = PDFDocument(url: URL(fileURLWithPath: paper.pdfPath)) else { return "" }
        var parts: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            for ann in page.annotations {
                if let urlAction = ann.action as? PDFActionURL, let u = urlAction.url {
                    parts.append(u.absoluteString)
                }
            }
            if let s = page.string { parts.append(s) }
        }
        return parts.joined(separator: "\n")
    }

    private static func pageAnchors(for paper: Paper, session: URLSession) async -> [HTMLAnchor] {
        guard let pageURL = abstractOrLandingURL(for: paper),
              let data = try? await fetch(pageURL, session: session) else { return [] }
        return LinkExtractor.anchors(inHTMLData: data)
    }

    /// arXiv abstract page by id; else the paper's HTML landing page (CVF raw-PDF → /html/).
    private static func abstractOrLandingURL(for paper: Paper) -> String? {
        if let id = ArxivService.extractID(from: paper.url) { return ArxivService.absURL(forID: id) }
        let u = paper.url
        guard !u.isEmpty else { return nil }
        if u.lowercased().hasSuffix(".pdf") {
            guard u.contains("/papers/") else { return nil }
            return u.replacingOccurrences(of: "/papers/", with: "/html/")
                    .replacingOccurrences(of: ".pdf", with: ".html")
        }
        return u
    }

    private static func fetch(_ urlString: String, session: URLSession) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        return data
    }
}
