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

    func testCaptureUpdatesExistingOpenReviewPaperInsteadOfDuplicating() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let handler = CaptureHandler(store: store) { _ in
            var m = PaperMetadata(); m.title = "OpenReview Paper"; return m
        }
        var p = CapturePayload(); p.url = "https://openreview.net/forum?id=aVh9KRZdRk"
        let first = try await handler.capture(p)

        var p2 = CapturePayload(); p2.url = "https://openreview.net/pdf?id=aVh9KRZdRk"
        let second = try await handler.capture(p2)

        XCTAssertEqual(second.id, first.id)                // same row, not a copy
        XCTAssertEqual(try store.allPapers().count, 1)
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

    func testReportsIssueWhenMetadataCannotBeFetched() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        var reported: [String] = []
        // Resolver fails (e.g. arXiv unreachable without a proxy).
        let handler = CaptureHandler(
            store: store,
            resolve: { _ in throw URLError(.cannotConnectToHost) },
            reportIssue: { reported.append($0) }
        )
        var p = CapturePayload(); p.url = "https://arxiv.org/abs/2606.01234"
        let saved = try await handler.capture(p)

        XCTAssertEqual(saved.title, p.url)          // title fell back to the URL
        XCTAssertEqual(reported.count, 1)           // and the user was told why
        XCTAssertTrue(reported[0].contains("2606.01234"))
    }

    func testNoIssueReportedWhenTitleResolves() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        var reported: [String] = []
        let handler = CaptureHandler(
            store: store,
            resolve: { _ in var m = PaperMetadata(); m.title = "Real Title"; return m },
            reportIssue: { reported.append($0) }
        )
        var p = CapturePayload(); p.url = "https://arxiv.org/abs/2606.01234"
        _ = try await handler.capture(p)
        XCTAssertTrue(reported.isEmpty)             // metadata fine ⇒ no notification
    }

    func testDirectPdfUrlSkipsResolve() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        // If resolve ran, this abstract would be pulled in; it must not be (URL is a .pdf
        // with no known HTML landing page).
        let handler = CaptureHandler(store: store) { _ in
            var m = PaperMetadata(); m.abstract = "FROM RESOLVE"; return m
        }
        var p = CapturePayload()
        p.url = "https://example.com/papers/some_paper.pdf"
        p.title = "Some Paper"
        p.pdf_url = p.url
        let saved = try await handler.capture(p)
        XCTAssertEqual(saved.abstract, "")     // resolve skipped for direct PDF URLs
        XCTAssertEqual(saved.pdfURL, p.url)
        XCTAssertEqual(saved.title, "Some Paper")
    }

    func testCVFPdfUrlResolvesViaAbstractPage() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        // A CVF raw-PDF capture must resolve metadata from the paper's abstract page,
        // not skip resolution (and not download the PDF).
        var resolvedURLs: [String] = []
        let handler = CaptureHandler(store: store) { url in
            resolvedURLs.append(url)
            var m = PaperMetadata()
            m.title = "SAI3D"; m.year = "2024"; m.abstract = "From the abstract page"
            return m
        }
        var p = CapturePayload()
        p.url = "https://openaccess.thecvf.com/content/CVPR2024/papers/Yin_SAI3D_CVPR_2024_paper.pdf"
        p.pdf_url = p.url
        let saved = try await handler.capture(p)
        XCTAssertEqual(resolvedURLs,
                       ["https://openaccess.thecvf.com/content/CVPR2024/html/Yin_SAI3D_CVPR_2024_paper.html"])
        XCTAssertEqual(saved.title, "SAI3D")
        XCTAssertEqual(saved.abstract, "From the abstract page")
        XCTAssertEqual(saved.pdfURL, p.url)
    }

    func testPlaceholderPayloadTeaserIsDropped() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let handler = CaptureHandler(store: store) { _ in
            var m = PaperMetadata(); m.title = "Paper"; return m
        }
        var p = CapturePayload()
        p.url = "https://openreview.net/forum?id=aVh9KRZdRk"
        // What the browser extension sends for OpenReview pages: the site logo as og:image.
        p.teaser_url = "https://openreview.net/images/openreview_logo_512.png"
        let saved = try await handler.capture(p)
        XCTAssertEqual(saved.teaserURL, "")    // logo rejected; enrichment/PDF fallback fills in
    }

    func testFigureSourceSelection() {
        // arXiv URL → arXiv id.
        XCTAssertEqual(
            CaptureHandler.figureSource(payloadURL: "https://arxiv.org/abs/2606.01234", metaArxivID: ""),
            .arxiv(id: "2606.01234"))
        // CVF page with a harvested arXiv id → arXiv (its HTML has the real figures).
        XCTAssertEqual(
            CaptureHandler.figureSource(
                payloadURL: "https://openaccess.thecvf.com/content/CVPR2024/html/Yin_paper.html",
                metaArxivID: "2312.11557"),
            .arxiv(id: "2312.11557"))
        // CVF page without an arXiv version → its own landing page.
        XCTAssertEqual(
            CaptureHandler.figureSource(
                payloadURL: "https://openaccess.thecvf.com/content/CVPR2024/html/Yin_paper.html",
                metaArxivID: ""),
            .page(url: "https://openaccess.thecvf.com/content/CVPR2024/html/Yin_paper.html"))
        // CVF raw PDF → mapped abstract page.
        XCTAssertEqual(
            CaptureHandler.figureSource(
                payloadURL: "https://openaccess.thecvf.com/content/CVPR2024/papers/Yin_paper.pdf",
                metaArxivID: ""),
            .page(url: "https://openaccess.thecvf.com/content/CVPR2024/html/Yin_paper.html"))
        // OpenReview → no scrapeable source (browser check); PDF extraction handles the card.
        XCTAssertNil(CaptureHandler.figureSource(
            payloadURL: "https://openreview.net/forum?id=aVh9KRZdRk", metaArxivID: ""))
        // A random PDF elsewhere → nothing to scrape.
        XCTAssertNil(CaptureHandler.figureSource(
            payloadURL: "https://example.com/some.pdf", metaArxivID: ""))
    }
}
