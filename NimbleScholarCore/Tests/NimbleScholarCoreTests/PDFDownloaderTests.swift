import XCTest
@testable import NimbleScholarCore

final class PDFDownloaderTests: XCTestCase {
    func testLooksLikePDF() {
        XCTAssertTrue(PDFDownloader.looksLikePDF(Data("%PDF-1.7\n...".utf8)))
        XCTAssertFalse(PDFDownloader.looksLikePDF(Data("<html>".utf8)))
    }

    /// A paper with an explicit local pdfPath resolves to that file without any network access.
    func testEnsureLocalPDFHonorsExistingPdfPath() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nimble-pdf-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let local = tmp.appendingPathComponent("attached.pdf")
        try Data("%PDF-1.7\n".utf8).write(to: local)

        var paper = Paper(title: "Local only")     // no url / pdfURL → no network fallback exists
        paper.pdfPath = local.path

        let downloader = PDFDownloader(cacheDir: tmp.appendingPathComponent("cache"))
        let resolved = try await downloader.ensureLocalPDF(for: paper)
        XCTAssertEqual(resolved.path, local.path)
    }
}
