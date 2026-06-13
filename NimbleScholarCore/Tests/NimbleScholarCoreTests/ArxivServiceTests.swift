import XCTest
@testable import NimbleScholarCore

final class ArxivServiceTests: XCTestCase {
    func testExtractID() {
        XCTAssertEqual(ArxivService.extractID(from: "https://arxiv.org/abs/2606.01234"), "2606.01234")
        XCTAssertEqual(ArxivService.extractID(from: "https://arxiv.org/pdf/2606.01234v2"), "2606.01234v2")
        XCTAssertEqual(ArxivService.extractID(from: "arXiv:2606.01234"), "2606.01234")
        XCTAssertNil(ArxivService.extractID(from: "https://example.com/paper"))
    }

    func testPDFURLFromAbs() {
        XCTAssertEqual(ArxivService.normalizedPDFURL(absOrID: "https://arxiv.org/abs/2606.01234"),
                       "https://arxiv.org/pdf/2606.01234")
        XCTAssertEqual(ArxivService.normalizedPDFURL(absOrID: "2606.01234"),
                       "https://arxiv.org/pdf/2606.01234")
    }
}
