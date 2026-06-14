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
}
