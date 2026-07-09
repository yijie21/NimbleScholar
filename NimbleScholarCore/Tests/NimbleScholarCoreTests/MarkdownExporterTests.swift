import XCTest
@testable import NimbleScholarCore

final class MarkdownExporterTests: XCTestCase {
    func testExportsTitleMetadataAndAnnotations() {
        var p = Paper(id: 1, title: "Attention Is All You Need")
        p.authors = "Vaswani"; p.year = "2017"
        let rows = [
            AnnotationIndex(id: 1, paperId: 1, page: 3, kind: "highlight", color: "#ffd966",
                            snippet: "self-attention", x: 0, y: 0, width: 0, height: 0, createdAt: 0, updatedAt: 0),
            AnnotationIndex(id: 2, paperId: 1, page: 5, kind: "note", color: "#7cc4ff",
                            snippet: "check this", x: 0, y: 0, width: 0, height: 0, createdAt: 0, updatedAt: 0),
        ]
        let md = MarkdownExporter.export(paper: p, annotations: rows)
        XCTAssertTrue(md.hasPrefix("# Attention Is All You Need"))
        XCTAssertTrue(md.contains("Vaswani"))
        XCTAssertTrue(md.contains("**p.3**"))
        XCTAssertTrue(md.contains("self-attention"))
        XCTAssertTrue(md.contains("check this"))
    }

    func testTagExportListsPapersNewestFirstWithLinks() {
        var a = Paper(id: 1, title: "Zebra Nets")
        a.authors = "Ng"; a.year = "2020"; a.venue = "NeurIPS"
        a.summary = "A study of stripes."; a.url = "https://example.com/zebra"; a.doi = "10.1/zeb"
        var b = Paper(id: 2, title: "Alpha Models")
        b.authors = "Li"; b.year = "2024"; b.venue = "ICML"
        b.projectURL = "https://proj.example.com"; b.codeURL = "https://github.com/x/y"

        let md = MarkdownExporter.export(tag: "vision", papers: [a, b])

        XCTAssertTrue(md.hasPrefix("# Papers tagged “vision”"))
        XCTAssertTrue(md.contains("2 papers"))
        // Newest year first: 2024 (Alpha) before 2020 (Zebra).
        let alpha = md.range(of: "Alpha Models")
        let zebra = md.range(of: "Zebra Nets")
        XCTAssertNotNil(alpha); XCTAssertNotNil(zebra)
        XCTAssertTrue(alpha!.lowerBound < zebra!.lowerBound)
        XCTAssertTrue(md.contains("## 1. Alpha Models"))
        XCTAssertTrue(md.contains("## 2. Zebra Nets"))
        // Metadata, summary, and links render.
        XCTAssertTrue(md.contains("Ng · 2020 · NeurIPS"))
        XCTAssertTrue(md.contains("> A study of stripes."))
        XCTAssertTrue(md.contains("[Page](https://example.com/zebra)"))
        XCTAssertTrue(md.contains("[DOI](https://doi.org/10.1/zeb)"))
        XCTAssertTrue(md.contains("[Project](https://proj.example.com)"))
        XCTAssertTrue(md.contains("[Code](https://github.com/x/y)"))
    }

    func testTagExportHandlesNoLinksAndNoSummary() {
        var p = Paper(id: 1, title: "Bare Paper")
        p.authors = "Solo"; p.year = "2019"
        let md = MarkdownExporter.export(tag: "misc", papers: [p])
        XCTAssertTrue(md.contains("## 1. Bare Paper"))
        XCTAssertTrue(md.contains("Solo · 2019"))
        XCTAssertFalse(md.contains("**Links:**"))
        XCTAssertFalse(md.contains(">"))   // no summary blockquote
    }

    func testTagExportEmptyList() {
        let md = MarkdownExporter.export(tag: "empty", papers: [])
        XCTAssertTrue(md.contains("# Papers tagged “empty”"))
        XCTAssertTrue(md.contains("No papers carry this tag."))
    }
}
