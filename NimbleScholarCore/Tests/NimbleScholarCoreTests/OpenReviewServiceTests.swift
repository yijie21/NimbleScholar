import XCTest
@testable import NimbleScholarCore

final class OpenReviewServiceTests: XCTestCase {
    func fixture(_ filename: String) throws -> Data {
        let parts = filename.split(separator: ".")
        let ext = String(parts.last!)
        let base = parts.dropLast().joined(separator: ".")
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures"),
            "Missing fixture \(filename)"
        )
        return try Data(contentsOf: url)
    }

    // MARK: - ID extraction

    func testExtractIDFromForumURL() {
        XCTAssertEqual(OpenReviewService.extractID(from: "https://openreview.net/forum?id=aVh9KRZdRk"),
                       "aVh9KRZdRk")
    }

    func testExtractIDFromPdfURL() {
        XCTAssertEqual(OpenReviewService.extractID(from: "https://openreview.net/pdf?id=BJJsrmfCZ"),
                       "BJJsrmfCZ")
    }

    func testExtractIDPrefersIdOverNoteId() {
        // noteId points at a review comment; the paper is the forum's root note.
        let url = "https://openreview.net/forum?id=aVh9KRZdRk&noteId=xYz123"
        XCTAssertEqual(OpenReviewService.extractID(from: url), "aVh9KRZdRk")
    }

    func testExtractIDRejectsOtherHosts() {
        XCTAssertNil(OpenReviewService.extractID(from: "https://arxiv.org/abs/2606.01234"))
        XCTAssertNil(OpenReviewService.extractID(from: "https://example.com/forum?id=abc"))
        XCTAssertNil(OpenReviewService.extractID(from: "https://openreview.net/group?q=x"))
    }

    // MARK: - Notes API parsing

    func testParseV1Notes() throws {
        let meta = try XCTUnwrap(
            OpenReviewService.parseNotes(try fixture("openreview_v1.json"), id: "BJJsrmfCZ"))
        XCTAssertEqual(meta.title, "Automatic differentiation in PyTorch")
        XCTAssertEqual(meta.authors, "Adam Paszke, Sam Gross, Soumith Chintala")
        XCTAssertTrue(meta.abstract.contains("automatic differentiation module"))
        XCTAssertEqual(meta.year, "2017")   // from cdate (no venue on v1 notes)
        XCTAssertEqual(meta.pdfURL, "https://openreview.net/pdf?id=BJJsrmfCZ")
    }

    func testParseV2NotesUnwrapsValueWrappers() throws {
        let meta = try XCTUnwrap(
            OpenReviewService.parseNotes(try fixture("openreview_v2.json"), id: "aVh9KRZdRk"))
        XCTAssertEqual(meta.title, "Vision-Language Models are Zero-Shot Reward Models")
        XCTAssertEqual(meta.authors, "Juan Rocamonde, Victoriano Montesinos")
        XCTAssertEqual(meta.year, "2024")   // from the venue string, not the timestamps
        XCTAssertEqual(meta.pdfURL, "https://openreview.net/pdf?id=aVh9KRZdRk")
    }

    func testParseNotesPicksRootNoteNotAReviewReply() throws {
        // The v1 fixture lists a review reply BEFORE the root note.
        let meta = try XCTUnwrap(
            OpenReviewService.parseNotes(try fixture("openreview_v1.json"), id: "BJJsrmfCZ"))
        XCTAssertEqual(meta.title, "Automatic differentiation in PyTorch")
    }

    func testParseNotesReturnsNilForEmptyResponse() {
        let empty = Data(#"{"notes":[],"count":0}"#.utf8)
        XCTAssertNil(OpenReviewService.parseNotes(empty, id: "xyz"))
    }
}
