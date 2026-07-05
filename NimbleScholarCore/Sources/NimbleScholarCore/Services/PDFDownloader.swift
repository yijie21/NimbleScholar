import Foundation

public struct PDFDownloader {
    public let session: URLSession
    /// Tried when `session` fails or returns non-PDF bytes (e.g. a bot-check page served
    /// to the proxy's datacenter IP): a session that connects directly, without a proxy.
    public let fallbackSession: URLSession?
    public let cacheDir: URL
    public init(session: URLSession = .shared, fallbackSession: URLSession? = nil, cacheDir: URL) {
        self.session = session; self.fallbackSession = fallbackSession; self.cacheDir = cacheDir
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
        // A manually imported/attached PDF lives at an explicit `pdfPath`. Honor it (when the file
        // is really there) so the reader opens local PDFs instead of trying to re-download them.
        if !overwrite, !paper.pdfPath.isEmpty {
            let stored = URL(fileURLWithPath: paper.pdfPath)
            if FileManager.default.fileExists(atPath: stored.path) { return stored }
        }
        let dest = cacheDir.appendingPathComponent(Self.safeName(for: paper))
        if !overwrite, FileManager.default.fileExists(atPath: dest.path) { return dest }
        let urlString = !paper.pdfURL.isEmpty ? paper.pdfURL
            : (ArxivService.normalizedPDFURL(absOrID: paper.url) ?? paper.url)
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let data = try await fetchPDFData(from: url)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try data.write(to: dest)
        return dest
    }

    /// Fetch real PDF bytes: primary session first, then the no-proxy fallback.
    private func fetchPDFData(from url: URL) async throws -> Data {
        if let (data, _) = try? await session.data(from: url), Self.looksLikePDF(data) {
            return data
        }
        if let fallback = fallbackSession {
            let (data, _) = try await fallback.data(from: url)
            if Self.looksLikePDF(data) { return data }
        }
        throw URLError(.cannotParseResponse)
    }
}
