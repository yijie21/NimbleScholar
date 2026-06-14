import Foundation
import SwiftSoup

public struct PaperMetadata {
    public var title = ""
    public var authors = ""
    public var year = ""
    public var doi = ""
    public var abstract = ""
    public var pdfURL = ""
    public var teaserURL = ""
    public init() {}
}

public enum MetadataService {
    /// Parse arXiv API Atom XML with a tiny streaming XML parser.
    public static func parseArxivAtom(_ data: Data) throws -> PaperMetadata {
        final class Delegate: NSObject, XMLParserDelegate {
            var element = ""
            var inEntry = false               // only read fields inside <entry>, not the feed-level <title>
            var title = "", summary = "", published = ""
            var authors = [String]()
            var inAuthor = false, authorName = ""
            func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?,
                        qualifiedName: String?, attributes a: [String: String]) {
                element = e
                if e == "entry" { inEntry = true }
                if e == "author", inEntry { inAuthor = true; authorName = "" }
            }
            func parser(_ p: XMLParser, foundCharacters s: String) {
                guard inEntry else { return }
                switch element {
                case "title": title += s
                case "summary": summary += s
                case "published": published += s
                case "name" where inAuthor: authorName += s
                default: break
                }
            }
            func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
                if e == "author", inAuthor {
                    authors.append(authorName.trimmingCharacters(in: .whitespacesAndNewlines))
                    inAuthor = false
                }
                if e == "entry" { inEntry = false }
                element = ""
            }
        }
        let parser = XMLParser(data: data)
        let d = Delegate(); parser.delegate = d; parser.parse()
        var meta = PaperMetadata()
        meta.title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.abstract = d.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.authors = d.authors.filter { !$0.isEmpty }.joined(separator: ", ")
        meta.year = String(d.published.prefix(4))
        return meta
    }

    /// Parse generic publisher pages via citation_* and og: meta tags.
    public static func parseGenericMeta(_ data: Data) throws -> PaperMetadata {
        let html = String(decoding: data, as: UTF8.self)
        let doc = try SwiftSoup.parse(html)
        func meta(_ names: [String]) throws -> String {
            for n in names {
                if let el = try doc.select("meta[name=\(n)], meta[property=\(n)]").first() {
                    let c = try el.attr("content")
                    if !c.isEmpty { return c }
                }
            }
            return ""
        }
        var m = PaperMetadata()
        m.title = try meta(["citation_title", "og:title"])
        if m.title.isEmpty { m.title = try doc.title() }
        m.authors = try doc.select("meta[name=citation_author]")
            .map { try $0.attr("content") }.filter { !$0.isEmpty }.joined(separator: ", ")
        m.doi = try meta(["citation_doi"])
        m.abstract = try meta(["description", "og:description"])
        m.pdfURL = try meta(["citation_pdf_url"])
        m.teaserURL = try meta(["og:image", "twitter:image"])
        return m
    }
}
