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

    func testCaptureUpdatesExistingArxivPaperInsteadOfDuplicating() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let handler = CaptureHandler(store: store) { _ in
            var m = PaperMetadata(); m.title = "First"; return m
        }
        var p = CapturePayload(); p.url = "https://arxiv.org/abs/2606.01234"; p.tags = "a"
        let first = try await handler.capture(p)
        try store.setTags(paperID: first.id!, tags: ["a", "keep-me"])

        var p2 = CapturePayload(); p2.url = "https://arxiv.org/pdf/2606.01234"
        let handler2 = CaptureHandler(store: store) { _ in
            var m = PaperMetadata(); m.title = "Updated"; return m
        }
        let second = try await handler2.capture(p2)

        XCTAssertEqual(second.id, first.id)                // same row, not a copy
        XCTAssertEqual(try store.allPapers().count, 1)
        XCTAssertEqual(second.title, "Updated")            // metadata merged
        XCTAssertEqual(Set(try store.tags(forPaper: first.id!)), ["a", "keep-me"])  // tags preserved
    }

    func testRelativePdfUrlIsResolvedAgainstPageURL() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let handler = CaptureHandler(store: store) { _ in PaperMetadata() }
        var p = CapturePayload()
        p.url = "https://openaccess.thecvf.com/content/CVPR2023/html/Foo_Paper.html"
        p.pdf_url = "/content/CVPR2023/papers/Foo_Paper.pdf"   // relative, as some sites emit
        let saved = try await handler.capture(p)
        XCTAssertEqual(saved.pdfURL, "https://openaccess.thecvf.com/content/CVPR2023/papers/Foo_Paper.pdf")
    }

    func testDirectPdfUrlSkipsResolve() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        // If resolve ran, this abstract would be pulled in; it must not be (URL is a .pdf).
        let handler = CaptureHandler(store: store) { _ in
            var m = PaperMetadata(); m.abstract = "FROM RESOLVE"; return m
        }
        var p = CapturePayload()
        p.url = "https://openaccess.thecvf.com/content/ICCV2021/papers/Kwon_H2O_paper.pdf"
        p.title = "Kwon H2O"
        p.pdf_url = p.url
        let saved = try await handler.capture(p)
        XCTAssertEqual(saved.abstract, "")     // resolve skipped for direct PDF URLs
        XCTAssertEqual(saved.pdfURL, p.url)
        XCTAssertEqual(saved.title, "Kwon H2O")
    }
}
