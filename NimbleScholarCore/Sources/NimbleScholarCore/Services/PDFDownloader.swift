import Foundation

public struct PDFDownloader {
    public let session: URLSession
    public let cacheDir: URL
    public init(session: URLSession = .shared, cacheDir: URL) {
        self.session = session; self.cacheDir = cacheDir
    }

    public static func looksLikePDF(_ data: Data) -> Bool {
        data.starts(with: Array("%PDF".utf8))
    }

    public static func safeName(for paper: Paper) -> String {
        let raw = ArxivService.extractID(from: paper.url) ?? paper.title
        let base = raw.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(String(base).prefix(80)) + ".pdf"
    }

    /// Downloads to cacheDir if not present; returns the local file path.
    public func ensureLocalPDF(for paper: Paper, overwrite: Bool = false) async throws -> URL {
        let dest = cacheDir.appendingPathComponent(Self.safeName(for: paper))
        if !overwrite, FileManager.default.fileExists(atPath: dest.path) { return dest }
        let urlString = !paper.pdfURL.isEmpty ? paper.pdfURL
            : (ArxivService.normalizedPDFURL(absOrID: paper.url) ?? paper.url)
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        guard Self.looksLikePDF(data) else { throw URLError(.cannotParseResponse) }
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try data.write(to: dest)
        return dest
    }
}
