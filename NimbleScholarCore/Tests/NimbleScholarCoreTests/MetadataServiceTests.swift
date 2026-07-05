import XCTest
@testable import NimbleScholarCore

final class MetadataServiceTests: XCTestCase {
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

    func testParseArxivAtom() throws {
        let meta = try MetadataService.parseArxivAtom(try fixture("arxiv_atom.xml"))
        XCTAssertEqual(meta.title, "Deep Residual Learning for Image Recognition")
        XCTAssertEqual(meta.authors, "Kaiming He, Xiangyu Zhang")
        XCTAssertEqual(meta.year, "2015")
        XCTAssertTrue(meta.abstract.contains("residual learning"))
    }

    func testParseGenericMeta() throws {
        let meta = try MetadataService.parseGenericMeta(try fixture("generic_meta.html"))
        XCTAssertEqual(meta.title, "A Generic Paper Title")
        XCTAssertEqual(meta.authors, "Jane Smith, Wei Chen")
        XCTAssertEqual(meta.doi, "10.1000/xyz")
        XCTAssertEqual(meta.abstract, "An abstract here.")
    }

    func testParseCVFPage() throws {
        let meta = try MetadataService.parseGenericMeta(try fixture("cvf_paper.html"))
        XCTAssertEqual(meta.title, "SAI3D: Segment Any Instance in 3D Scenes")
        XCTAssertEqual(meta.authors, "Yin, Yingda, Liu, Yuzheng, Chen, Baoquan")
        XCTAssertEqual(meta.year, "2024")                      // citation_publication_date
        XCTAssertTrue(meta.abstract.contains("zero-shot 3D instance segmentation"))  // #abstract div
        XCTAssertTrue(meta.pdfURL.hasSuffix("Yin_SAI3D_Segment_Any_Instance_in_3D_Scenes_CVPR_2024_paper.pdf"))
        XCTAssertEqual(meta.arxivID, "2312.11557")             // Related Material → [arXiv]
    }

    func testLogoOgImageIsNotUsedAsTeaser() throws {
        let html = """
        <html><head>
        <meta name="citation_title" content="Some Paper">
        <meta property="og:image" content="https://openreview.net/images/openreview_logo_512.png">
        </head><body></body></html>
        """
        let meta = try MetadataService.parseGenericMeta(Data(html.utf8))
        XCTAssertEqual(meta.title, "Some Paper")
        XCTAssertEqual(meta.teaserURL, "")
    }

    func testYearExtraction() {
        XCTAssertEqual(MetadataService.year(in: "2024"), "2024")
        XCTAssertEqual(MetadataService.year(in: "2024/06/17"), "2024")
        XCTAssertEqual(MetadataService.year(in: "ICLR 2024 Poster"), "2024")
        XCTAssertEqual(MetadataService.year(in: ""), "")
        XCTAssertEqual(MetadataService.year(in: "no year here"), "")
    }

    func testCVFLandingURLMapping() {
        XCTAssertEqual(
            MetadataService.cvfLandingURL(
                forPDF: "https://openaccess.thecvf.com/content/CVPR2024/papers/Yin_SAI3D_CVPR_2024_paper.pdf"),
            "https://openaccess.thecvf.com/content/CVPR2024/html/Yin_SAI3D_CVPR_2024_paper.html")
        // Workshop papers follow the same layout one level deeper.
        XCTAssertEqual(
            MetadataService.cvfLandingURL(
                forPDF: "https://openaccess.thecvf.com/content/ICCV2023W/XYZ/papers/Foo_Bar_paper.pdf"),
            "https://openaccess.thecvf.com/content/ICCV2023W/XYZ/html/Foo_Bar_paper.html")
        XCTAssertNil(MetadataService.cvfLandingURL(forPDF: "https://example.com/papers/foo.pdf"))
        XCTAssertNil(MetadataService.cvfLandingURL(forPDF: "https://openaccess.thecvf.com/content/CVPR2024/html/x.html"))
    }
}
