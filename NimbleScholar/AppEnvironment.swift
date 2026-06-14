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
    /// Non-nil if on-disk store setup failed; shown as a banner + logged. Indicates
    /// the app is running on an in-memory fallback store (nothing persists).
    let startupError: String?

    /// Where data lives: ~/Library/Application Support/Nimble Scholar/
    /// (Sandboxed apps get the container-relative equivalent.)
    private init() {
        var err: String?

        // Try the on-disk store; if it fails, log the real error everywhere we can
        // and fall back to in-memory so the app still launches for diagnosis.
        let resolvedStore: LibraryStore
        do {
            resolvedStore = try LibraryStore.makeDefault()
        } catch {
            let msg = "LibraryStore.makeDefault failed: \(error)"
            err = msg
            NSLog("‼️ NimbleScholar: %@", msg)
            print("‼️ NimbleScholar: \(msg)")
            try? msg.write(toFile: "/tmp/nimblescholar-startup.log", atomically: true, encoding: .utf8)
            resolvedStore = (try? LibraryStore.makeInMemory()) ?? { fatalError("in-memory store failed: \(error)") }()
        }
        self.store = resolvedStore
        self.startupError = err

        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        self.downloader = PDFDownloader(
            cacheDir: support.appendingPathComponent("Nimble Scholar/storage/pdfs", isDirectory: true))

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
        // Port comes from Settings (@AppStorage "capturePort"); default 8781.
        let saved = UserDefaults.standard.integer(forKey: "capturePort")
        let port = UInt16(saved > 0 ? saved : 8781)
        let server = CaptureServer(port: port, handler: handler)
        self.captureServer = server
        Task {
            do { try await server.run() }
            catch {
                NSLog("‼️ NimbleScholar: capture server stopped: %@", "\(error)")
                print("‼️ NimbleScholar: capture server stopped: \(error)")
            }
        }
    }
}
