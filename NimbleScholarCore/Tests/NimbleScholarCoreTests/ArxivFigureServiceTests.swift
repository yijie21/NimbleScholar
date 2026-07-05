import XCTest
@testable import NimbleScholarCore

final class ArxivFigureServiceTests: XCTestCase {
    private let base = URL(string: "https://arxiv.org/html/2606.01234v1/")!

    func testResolvesRelativeFigureURLAgainstBase() {
        let html = """
        <html><body>
          <figure><img src="logo.png" alt="logo"><figcaption>arXiv logo</figcaption></figure>
          <figure><img src="x1.png" alt="teaser"><figcaption>Figure 1: Teaser of our results</figcaption></figure>
          <figure><img src="x3.png" alt=""><figcaption>Figure 3: The pipeline of our method</figcaption></figure>
        </body></html>
        """
        let r = ArxivFigureService.parse(html: html, baseURL: base)
        XCTAssertEqual(r.teaser, "https://arxiv.org/html/2606.01234v1/x1.png")
        XCTAssertEqual(r.pipeline, "https://arxiv.org/html/2606.01234v1/x3.png")
    }

    func testResolvesRelativeURLWhenBaseHasNoTrailingSlash() {
        // arXiv serves the page at …/html/<id> (no slash); figures must still resolve
        // under the <id> directory, not drop it.
        let noSlash = URL(string: "https://arxiv.org/html/2606.01234v1")!
        let html = """
        <figure><img src="x1.png" alt="teaser"><figcaption>Figure 1: Teaser</figcaption></figure>
        """
        let r = ArxivFigureService.parse(html: html, baseURL: noSlash)
        XCTAssertEqual(r.teaser, "https://arxiv.org/html/2606.01234v1/x1.png")
    }

    func testFallsBackToOgImageWhenNoFigures() {
        let html = """
        <html><head>
          <meta property="og:image" content="/content/ICCV2021/teaser/abc.jpg">
        </head><body><p>No figures here.</p></body></html>
        """
        let page = URL(string: "https://openaccess.thecvf.com/content/ICCV2021/html/Paper.html")!
        let r = ArxivFigureService.parse(html: html, baseURL: page)
        XCTAssertEqual(r.teaser, "https://openaccess.thecvf.com/content/ICCV2021/teaser/abc.jpg")
    }

    func testRealFigureWinsOverOgImage() {
        let html = """
        <html><head><meta property="og:image" content="https://x/card.png"></head>
        <body><figure><img src="https://x/fig1.png" alt="teaser"><figcaption>Figure 1</figcaption></figure></body></html>
        """
        let r = ArxivFigureService.parse(html: html, baseURL: base)
        XCTAssertEqual(r.teaser, "https://x/fig1.png")
    }

    func testAbsoluteFigureURLPreserved() {
        let html = """
        <figure><img src="https://cdn.example.com/teaser.png" alt="overview"><figcaption>Overview</figcaption></figure>
        """
        let r = ArxivFigureService.parse(html: html, baseURL: base)
        XCTAssertEqual(r.teaser, "https://cdn.example.com/teaser.png")
    }

    func testLinkedArxivIDFoundOnCVFStylePage() {
        // CVF abstract pages have no figures but link the paper's arXiv version.
        let html = """
        <html><body>
        [<a href="/content/CVPR2024/papers/Yin_paper.pdf">pdf</a>]
        [<a href="http://arxiv.org/abs/2312.11557">arXiv</a>]
        </body></html>
        """
        XCTAssertEqual(ArxivFigureService.linkedArxivID(inHTML: html), "2312.11557")
        XCTAssertNil(ArxivFigureService.linkedArxivID(inHTML: "<html><body>no links</body></html>"))
    }
}
