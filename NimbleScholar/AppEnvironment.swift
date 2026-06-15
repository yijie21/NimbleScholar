import Foundation
import NimbleScholarCore

/// Default values registered into UserDefaults at launch, so a fresh install behaves
/// correctly before the user opens Settings. The download proxy is ON by default: the
/// app's URLSession only honors macOS *System* proxy settings (not shell env vars), so
/// on networks that require a local proxy it must be enabled to reach arXiv. Set
/// `proxyPort` to your local proxy's port.
enum AppDefaults {
    static let proxyEnabled = true
    static let proxyHost = "127.0.0.1"
    static let proxyPort = 7892   // local proxy port
}

/// App-wide singleton: owns the store, the PDF cache location, and the capture server.
/// One instance for the whole app so the UI and the capture server share the same store.
/// Not @MainActor: the store (GRDB) is internally synchronized, so view models can read
/// `AppEnvironment.shared.store` from their initializers without crossing actors.
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let store: LibraryStore
    let downloader: PDFDownloader
    let figures: ArxivFigureService
    /// URLSession used for ALL downloads (PDFs, figures, metadata). Routes through the
    /// user's configured proxy when enabled in Settings (restart to apply changes).
    let networkSession: URLSession
    var captureServer: CaptureServer?
    /// Non-nil if on-disk store setup failed; shown as a banner + logged. Indicates
    /// the app is running on an in-memory fallback store (nothing persists).
    let startupError: String?
    /// Sparkle-based auto-updater (see UpdaterController). Created on the main thread
    /// when `AppEnvironment.shared` is first realized by the app's @StateObject.
    let updater = UpdaterController()

    /// Where data lives: ~/Library/Application Support/Nimble Scholar/
    /// (Sandboxed apps get the container-relative equivalent.)
    private init() {
        AppEnvironment.registerDefaults()
        Notifier.requestAuthorization()
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

        let session = AppEnvironment.makeNetworkSession()
        self.networkSession = session
        self.figures = ArxivFigureService(session: session)

        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        self.downloader = PDFDownloader(
            session: session,
            cacheDir: support.appendingPathComponent("Nimble Scholar/storage/pdfs", isDirectory: true))

        startCaptureServer()
    }

    /// Seed UserDefaults so a fresh install has the proxy on with sane host/port before
    /// the user ever opens Settings. Explicit user values always override these.
    private static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            "proxyEnabled": AppDefaults.proxyEnabled,
            "proxyHost": AppDefaults.proxyHost,
            "proxyPort": AppDefaults.proxyPort,
        ])
    }

    /// A capture handler wired to this environment, with metadata problems surfaced as a
    /// macOS notification. Shared by the capture server and the in-app Capture sheet.
    func makeCaptureHandler() -> CaptureHandler {
        CaptureHandler(
            store: store,
            resolve: { url in try await AppEnvironment.resolveMetadata(for: url) },
            fetchFigures: AppEnvironment.fetchArxivFigures,
            reportIssue: { message in
                NSLog("‼️ NimbleScholar capture: %@", message)
                Notifier.notify(title: "Capture issue", body: message)
            }
        )
    }

    /// Build the shared download session, honoring the proxy configured in Settings.
    private static func makeNetworkSession() -> URLSession {
        let d = UserDefaults.standard
        let config = URLSessionConfiguration.default
        let host = d.string(forKey: "proxyHost") ?? ""
        let port = d.integer(forKey: "proxyPort")
        if d.bool(forKey: "proxyEnabled"), !host.isEmpty, port > 0 {
            config.connectionProxyDictionary = [
                "HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port,
                "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port,
            ]
        }
        return URLSession(configuration: config)
    }

    /// Resolve metadata for a URL: arXiv API first, generic <meta> fallback.
    static func resolveMetadata(for url: String) async throws -> PaperMetadata {
        let session = AppEnvironment.shared.networkSession
        if let id = ArxivService.extractID(from: url) {
            let (data, _) = try await session.data(from: ArxivService.apiURL(forID: id))
            return try MetadataService.parseArxivAtom(data)
        }
        guard let u = URL(string: url) else { return PaperMetadata() }
        let (data, _) = try await session.data(from: u)
        return try MetadataService.parseGenericMeta(data)
    }

    /// arXiv figure scrape (by id) used to enrich captured papers with a teaser image.
    static func fetchArxivFigures(_ id: String) async throws -> FigureChooser.Result {
        try await AppEnvironment.shared.figures.figures(forID: id)
    }

    /// Figure scrape from a non-arXiv paper's HTML landing page (CVF, publishers, …).
    static func fetchPageFigures(_ pageURL: String) async throws -> FigureChooser.Result {
        try await AppEnvironment.shared.figures.figures(forPageURL: pageURL)
    }

    private func startCaptureServer() {
        let handler = makeCaptureHandler()
        // Port comes from Settings (@AppStorage "capturePort"); default 8781.
        // If it's taken, walk forward until we find a free one, and log which we bound.
        let saved = UserDefaults.standard.integer(forKey: "capturePort")
        let base = UInt16(saved > 0 ? saved : 8917)
        Task {
            for offset: UInt16 in 0..<20 {
                let port = base &+ offset
                let server = CaptureServer(port: port, handler: handler)
                let listen = Task {
                    try? await server.waitUntilListening()
                    NSLog("‼️ NimbleScholar: capture server LISTENING on http://127.0.0.1:%u", UInt(port))
                    print("‼️ NimbleScholar: capture server LISTENING on http://127.0.0.1:\(port)")
                    // Write the bound port so the launch script (and the user) can find it,
                    // since a bundle launched via `open` doesn't print to the terminal.
                    try? "\(port)".write(toFile: "/tmp/nimblescholar-port.txt", atomically: true, encoding: .utf8)
                }
                do {
                    try await server.run()   // serves until stopped; throws immediately on bind failure
                    listen.cancel()
                    return
                } catch {
                    listen.cancel()
                    NSLog("‼️ NimbleScholar: port %u busy; trying %u", UInt(port), UInt(port &+ 1))
                    continue
                }
            }
            NSLog("‼️ NimbleScholar: no free capture port in range")
        }
    }
}
