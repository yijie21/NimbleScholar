import XCTest
@testable import NimbleScholarCore

final class LinkExtractorTests: XCTestCase {
    func testFindsGithubInText() {
        let t = "Code is available at https://github.com/facebookresearch/detectron2 for use."
        XCTAssertEqual(LinkExtractor.codeURL(in: t), "https://github.com/facebookresearch/detectron2")
    }
    func testStripsGitSuffixAndPunctuationAndAddsScheme() {
        XCTAssertEqual(LinkExtractor.codeURL(in: "(see github.com/foo/bar.git)."),
                       "https://github.com/foo/bar")
    }
    func testRejectsBareOwnerAndPagesAndReservedOwners() {
        XCTAssertNil(LinkExtractor.codeURL(in: "Visit https://github.com/google here"))   // no repo
        XCTAssertNil(LinkExtractor.codeURL(in: "https://foo.github.io/proj"))             // pages, not code
        XCTAssertNil(LinkExtractor.codeURL(in: "https://github.com/sponsors/foo"))        // reserved owner
    }
    func testProjectFromGithubIOAndCodeTogether() {
        let links = LinkExtractor.extract(text: "Project https://myproj.github.io/site code github.com/me/repo")
        XCTAssertEqual(links.projectURL, "https://myproj.github.io/site")
        XCTAssertEqual(links.codeURL, "https://github.com/me/repo")
    }
    func testProjectFromLabeledAnchorIgnoresArxiv() {
        let anchors = [
            HTMLAnchor(href: "https://arxiv.org/abs/1234.5678", label: "arXiv"),
            HTMLAnchor(href: "https://example.edu/cool-paper", label: "Project Page"),
        ]
        let links = LinkExtractor.extract(text: "", anchors: anchors)
        XCTAssertEqual(links.projectURL, "https://example.edu/cool-paper")
        XCTAssertNil(links.codeURL)
    }
    func testCodeFromAnchorWhenNotInText() {
        let anchors = [HTMLAnchor(href: "https://github.com/a/b", label: "GitHub")]
        XCTAssertEqual(LinkExtractor.extract(text: "", anchors: anchors).codeURL, "https://github.com/a/b")
    }
    func testAnchorsParsing() {
        let html = """
        <html><body>
          <a href="https://github.com/a/b">Code</a>
          <a href="https://x.github.io">Project Page</a>
        </body></html>
        """
        let anchors = LinkExtractor.anchors(inHTMLData: Data(html.utf8))
        XCTAssertEqual(anchors.count, 2)
        XCTAssertEqual(anchors[0].href, "https://github.com/a/b")
        XCTAssertEqual(anchors[0].label, "Code")
        XCTAssertEqual(anchors[1].label, "Project Page")
    }
}
