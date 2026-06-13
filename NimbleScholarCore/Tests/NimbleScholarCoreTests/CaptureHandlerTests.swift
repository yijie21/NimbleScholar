import XCTest
import GRDB
@testable import NimbleScholarCore

final class CaptureHandlerTests: XCTestCase {
    func testCaptureCreatesPaperWithTagsAndMetadataMerge() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        // Resolver returns metadata for the URL (stubbed — no network).
        let handler = CaptureHandler(store: store) { _ in
            var m = PaperMetadata()
            m.title = "Resolved Title"; m.authors = "A. Author"; m.year = "2026"
            m.abstract = "resolved abstract"
            return m
        }
        var payload = CapturePayload()
        payload.url = "https://arxiv.org/abs/2606.01234"
        payload.tags = "to-read, vla"
        let paper = try await handler.capture(payload)

        XCTAssertEqual(paper.title, "Resolved Title")
        XCTAssertEqual(paper.pdfURL, "https://arxiv.org/pdf/2606.01234")
        XCTAssertEqual(Set(try store.tags(forPaper: paper.id!)), ["to-read", "vla"])
        XCTAssertEqual(try store.allPapers().count, 1)
    }
}
