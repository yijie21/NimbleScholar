import Foundation
import SwiftSoup

public struct HTMLAnchor: Equatable {
    public let href: String
    public let label: String
    public init(href: String, label: String) { self.href = href; self.label = label }
}

public struct ExtractedLinks: Equatable {
    public var projectURL: String?
    public var codeURL: String?
    public init(projectURL: String? = nil, codeURL: String? = nil) {
        self.projectURL = projectURL; self.codeURL = codeURL
    }
}

/// Pure classification of project-page and GitHub links from text + HTML anchors.
public enum LinkExtractor {
    /// github.com/<owner>/<repo> owners that are site features, not user repos.
    private static let reservedOwners: Set<String> = [
        "sponsors", "about", "features", "topics", "orgs", "login", "settings",
        "marketplace", "pulls", "issues", "notifications", "explore", "collections", "apps",
    ]

    // MARK: GitHub (code)

    public static func codeURL(in text: String) -> String? {
        // optional scheme/www; require owner/repo; word boundary so "notgithub.com" doesn't match.
        let pattern = #"(?<![\w.])(?:https?://)?(?:www\.)?github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for m in re.matches(in: text, range: range) {
            guard let r = Range(m.range, in: text) else { continue }
            var url = cleanTrailing(String(text[r]))
            if url.lowercased().hasSuffix(".git") { url = String(url.dropLast(4)) }
            if !url.lowercased().hasPrefix("http") { url = "https://" + url }
            // owner = path component right after github.com/
            let path = url.components(separatedBy: "github.com/").last ?? ""
            let owner = path.components(separatedBy: "/").first?.lowercased() ?? ""
            if reservedOwners.contains(owner) { continue }
            return url
        }
        return nil
    }

    public static func codeURL(inAnchors anchors: [HTMLAnchor]) -> String? {
        for a in anchors { if let u = codeURL(in: a.href) { return u } }
        return nil
    }

    // MARK: Project page (strong signals only)

    public static func projectURL(in text: String, anchors: [HTMLAnchor]) -> String? {
        // 1. an anchor labeled like a project page (and not arXiv/DOI/GitHub).
        if let labelRE = try? NSRegularExpression(
            pattern: #"project\s*(page|website|site)?|home\s*page|website"#, options: [.caseInsensitive]) {
            for a in anchors where isHTTP(a.href) && !isExcludedForProject(a.href) {
                if labelRE.firstMatch(in: a.label, range: NSRange(a.label.startIndex..., in: a.label)) != nil {
                    return cleanTrailing(a.href)
                }
            }
        }
        // 2. a *.github.io URL.
        if let g = firstMatch(#"https?://[A-Za-z0-9-]+\.github\.io[^\s)\]}"'<>]*"#, in: text, anchors: anchors) {
            return cleanTrailing(g)
        }
        // 3. a sites.google.com URL.
        if let s = firstMatch(#"https?://sites\.google\.com[^\s)\]}"'<>]*"#, in: text, anchors: anchors) {
            return cleanTrailing(s)
        }
        return nil
    }

    public static func extract(text: String, anchors: [HTMLAnchor] = []) -> ExtractedLinks {
        ExtractedLinks(
            projectURL: projectURL(in: text, anchors: anchors),
            codeURL: codeURL(in: text) ?? codeURL(inAnchors: anchors)
        )
    }

    // MARK: HTML anchors

    public static func anchors(inHTMLData data: Data) -> [HTMLAnchor] {
        guard let html = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(html),
              let els = try? doc.select("a[href]") else { return [] }
        return els.array().compactMap { el in
            let href = (try? el.attr("href")) ?? ""
            guard !href.isEmpty else { return nil }
            let label = ((try? el.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return HTMLAnchor(href: href, label: label)
        }
    }

    // MARK: Helpers

    private static func isHTTP(_ s: String) -> Bool { s.hasPrefix("http://") || s.hasPrefix("https://") }
    private static func isExcludedForProject(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("arxiv.org") || l.contains("doi.org") || l.contains("github.com")
    }
    private static func cleanTrailing(_ s: String) -> String {
        var x = s
        while let last = x.last, ").,;]>'\"".contains(last) { x.removeLast() }
        return x
    }
    private static func firstMatch(_ pattern: String, in text: String, anchors: [HTMLAnchor]) -> String? {
        let hay = text + "\n" + anchors.map { $0.href }.joined(separator: "\n")
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: hay, range: NSRange(hay.startIndex..., in: hay)),
              let r = Range(m.range, in: hay) else { return nil }
        return String(hay[r])
    }
}
