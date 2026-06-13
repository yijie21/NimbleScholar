import Foundation
import NimbleScholarCore

/// App-wide singleton: owns the store, the PDF cache location, and the capture server.
/// One instance for the whole app so the UI and the capture server share the same store.
/// Not @MainActor: the store (GRDB) is internally synchronized, so view models can read
/// `AppEnvironment.shared.store` from their initializers without crossing actors.
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let store: LibraryStore
    let downloader: PDFDownloader
    let figures = ArxivFigureService()
    var captureServer: CaptureServer?

    /// Where data lives: ~/Library/Application Support/Nimble Scholar/
    /// (Sandboxed apps get the container-relative equivalent.)
    private init() {
        self.store = try! LibraryStore.makeDefault()
        let support = try! FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let cache = support.appendingPathComponent("Nimble Scholar/storage/pdfs", isDirectory: true)
        self.downloader = PDFDownloader(cacheDir: cache)
        startCaptureServer()
    }

    /// Resolve metadata for a URL: arXiv API first, generic <meta> fallback.
    static func resolveMetadata(for url: String) async throws -> PaperMetadata {
        if let id = ArxivService.extractID(from: url) {
            let (data, _) = try await URLSession.shared.data(from: ArxivService.apiURL(forID: id))
            return try MetadataService.parseArxivAtom(data)
        }
        guard let u = URL(string: url) else { return PaperMetadata() }
        let (data, _) = try await URLSession.shared.data(from: u)
        return try MetadataService.parseGenericMeta(data)
    }

    private func startCaptureServer() {
        let handler = CaptureHandler(store: store) { url in
            try await AppEnvironment.resolveMetadata(for: url)
        }
        let server = CaptureServer(port: 8765, handler: handler)
        self.captureServer = server
        Task { try? await server.run() }
    }
}
