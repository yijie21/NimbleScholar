import XCTest
@testable import NimbleScholarCore

final class BibTeXExporterTests: XCTestCase {
    func testExportsEntryWithKeyAndFields() {
        var p = Paper(id: 1, title: "Attention Is All You Need")
        p.authors = "Vaswani, Ashish"; p.year = "2017"; p.venue = "NeurIPS"
        let bib = BibTeXExporter.export([p])
        XCTAssertTrue(bib.contains("@article{vaswani2017"))
        XCTAssertTrue(bib.contains("title = {Attention Is All You Need}"))
        XCTAssertTrue(bib.contains("year = {2017}"))
    }
}
