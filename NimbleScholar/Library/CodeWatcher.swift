import Foundation
import NimbleScholarCore

/// Watches papers without confirmed code and notifies when a real GitHub repo appears.
/// Single instance owned by AppEnvironment; sweeps on launch, every 24h, and on demand.
@MainActor
final class CodeWatcher {
    private let store: LibraryStore
    private let session: URLSession
    private var timer: Timer?
    private var running = false

    private static let sweepKey = "lastCodeWatchSweep"
    private static let reconciledKey = "codeWatchReconciled"

    init(store: LibraryStore, session: URLSession) {
        self.store = store
        self.session = session
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            Task { await self?.sweep(force: false) }
        }
        Task { await sweep(force: false) }
    }

    func sweep(force: Bool) async {
        guard !running else { return }
        if !force, !shouldSweep() { return }
        running = true
        defer { running = false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.sweepKey)
        ActivityCenter.shared.begin("Checking for code…")
        defer { ActivityCenter.shared.end() }

        let reconciled = UserDefaults.standard.bool(forKey: Self.reconciledKey)
        let papers = (try? store.allPapers()) ?? []
        var rateLimited = false

        for var p in papers {
            guard p.id != nil, isWatchable(p) else { continue }

            if !p.codeURL.isEmpty {
                // Re-check a known candidate repo.
                switch await GitHubRepoChecker.check(p.codeURL, session: session) {
                case .released:
                    p.codeReady = true; _ = try? store.update(p)
                    if reconciled { notifyReleased(p) }
                case .notReleased, .error:
                    break
                case .rateLimited:
                    rateLimited = true
                }
            } else {
                // Discover a candidate, then check it.
                var changed = false
                let links = await LinkFinder.find(for: p, session: session)
                if let project = links.projectURL, p.projectURL.isEmpty { p.projectURL = project; changed = true }
                if let code = links.codeURL {
                    p.codeURL = code; changed = true
                    let status = await GitHubRepoChecker.check(code, session: session)
                    if status == .released { p.codeReady = true }
                    if status == .rateLimited { rateLimited = true }
                    _ = try? store.update(p)
                    if status == .released, reconciled { notifyReleased(p) }
                } else if changed {
                    _ = try? store.update(p)
                }
            }
            if rateLimited { break }
        }

        if !rateLimited { UserDefaults.standard.set(true, forKey: Self.reconciledKey) }
    }

    /// Re-check papers whose code link we currently trust, and demote any that turn out to
    /// be empty/placeholder repos back to "watching". Manual (⋯ menu) — does one pass with
    /// batch + per-item progress; stops early if rate-limited (re-run to continue).
    func revalidate() async {
        guard !running else { return }
        running = true
        defer { running = false }
        let targets = ((try? store.allPapers()) ?? []).filter { $0.codeReady && !$0.codeURL.isEmpty }
        guard !targets.isEmpty else { return }
        ActivityCenter.shared.beginBatch("Re-validating code links", total: targets.count)
        defer { ActivityCenter.shared.endBatch() }
        for var p in targets {
            ActivityCenter.shared.beginItem(p.id, "Checking repo…")
            let status = await GitHubRepoChecker.check(p.codeURL, session: session)
            if status == .notReleased {
                p.codeReady = false          // empty/placeholder → back to watching
                _ = try? store.update(p)
            }
            ActivityCenter.shared.endItem(p.id)
            ActivityCenter.shared.stepBatch()
            if status == .rateLimited { break }
        }
    }

    /// Not yet confirmed code, and there's something to check (a candidate, a project page,
    /// or a URL we can scrape). Local-only PDFs (no URL) aren't watched.
    private func isWatchable(_ p: Paper) -> Bool {
        !p.codeReady && (!p.codeURL.isEmpty || !p.projectURL.isEmpty || !p.url.isEmpty)
    }

    private func shouldSweep() -> Bool {
        let last = UserDefaults.standard.double(forKey: Self.sweepKey)   // 0 if unset
        return Date().timeIntervalSince1970 - last > 20 * 3600
    }

    private func notifyReleased(_ p: Paper) {
        Notifier.notify(title: "Code released",
                        body: p.title.isEmpty ? p.codeURL : p.title,
                        url: p.codeURL)
    }
}
