import XCTest
@testable import NimbleScholarCore

final class PDFDownloaderTests: XCTestCase {
    func testLooksLikePDF() {
        XCTAssertTrue(PDFDownloader.looksLikePDF(Data("%PDF-1.7\n...".utf8)))
        XCTAssertFalse(PDFDownloader.looksLikePDF(Data("<html>".utf8)))
    }
}
