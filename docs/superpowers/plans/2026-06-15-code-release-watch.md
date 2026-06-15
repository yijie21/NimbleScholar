# Watch for Code Release — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notify the user when a watched paper's code is finally open-sourced — detecting real GitHub repos vs empty/README-only placeholders — and open the repo when the notification is clicked.

**Architecture:** A new `code_ready` flag distinguishes a confirmed code repo from a found-but-placeholder one. A tested Core `GitHubRepo` helper decides "released" from a repo's root file list; an app `GitHubRepoChecker` calls the GitHub contents API. A `@MainActor CodeWatcher` (owned by `AppEnvironment`, started from the library view) sweeps code-less papers on launch + every 24h + on demand, reusing `LinkFinder` to discover links, and notifies via an extended `Notifier`. The first full sweep reconciles existing links silently.

**Tech Stack:** Swift/SwiftUI, GRDB (migration), GitHub REST API (contents endpoint), UserNotifications, XCTest. Builds on Milestone 4 (`LinkFinder`/`LinkExtractor`) and Milestone 3 (`Notifier`).

**Environment note:** `swift test` / `xcodebuild` require macOS + Xcode (run on the user's Mac).

**Reference spec:** `docs/superpowers/specs/2026-06-15-code-release-watch-design.md`

---

## File map

**Create:**
- `NimbleScholarCore/Sources/NimbleScholarCore/Services/GitHubRepo.swift` — pure owner/repo parse + released?
- `NimbleScholarCore/Tests/NimbleScholarCoreTests/GitHubRepoTests.swift` — unit tests
- `NimbleScholarCore/Tests/NimbleScholarCoreTests/CodeReadyTests.swift` — store round-trip
- `NimbleScholar/Library/GitHubRepoChecker.swift` — GitHub contents API call
- `NimbleScholar/Library/CodeWatcher.swift` — sweep orchestration

**Modify:**
- `NimbleScholarCore/Sources/NimbleScholarCore/Models/Paper.swift` — `codeReady`
- `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift` — `v6-code-ready` migration
- `NimbleScholar/App/Notifier.swift` — `url` userInfo + center delegate
- `NimbleScholar/AppEnvironment.swift` — own + start `CodeWatcher`
- `NimbleScholar/App/NimbleScholarApp.swift` — start the watcher on library appear
- `NimbleScholar/Library/PaperDetailView.swift` — Code button gated on `codeReady` + watching caption
- `NimbleScholar/Library/PaperEditSheet.swift` — set `codeReady` on manual save
- `NimbleScholar/Library/LibraryContentView.swift` — "Check for code now" menu item

---

## Task 1: `Paper.codeReady` + migration

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Models/Paper.swift`
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/CodeReadyTests.swift`

- [ ] **Step 1: Write the failing test.** Create `CodeReadyTests.swift`:

```swift
import XCTest
import GRDB
@testable import NimbleScholarCore

final class CodeReadyTests: XCTestCase {
    func testCodeReadyRoundTrips() throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        var p = Paper(title: "X")
        p.codeURL = "https://github.com/a/b"
        p.codeReady = true
        let saved = try store.create(p)
        XCTAssertTrue(try XCTUnwrap(store.paper(id: saved.id!)).codeReady)
    }
    func testCodeReadyDefaultsFalse() throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let saved = try store.create(Paper(title: "Y"))
        XCTAssertFalse(try XCTUnwrap(store.paper(id: saved.id!)).codeReady)
    }
}
```

- [ ] **Step 2: Run it to verify it fails.**

Run: `cd NimbleScholarCore && swift test --filter CodeReadyTests`
Expected: FAIL — `value of type 'Paper' has no member 'codeReady'`.

- [ ] **Step 3: Add the property + column mappings.** In `Paper.swift`, add the property after `linksScanned`:

```swift
    public var linksScanned: Bool = false
    public var codeReady: Bool = false
    public var createdAt: Int64 = 0
```

Add to the `Columns` enum after the links case:

```swift
        case projectURL = "project_url", codeURL = "code_url", linksScanned = "links_scanned"
        case codeReady = "code_ready"
        case createdAt = "created_at", updatedAt = "updated_at"
```

Add the identical case to `CodingKeys`:

```swift
        case projectURL = "project_url", codeURL = "code_url", linksScanned = "links_scanned"
        case codeReady = "code_ready"
        case createdAt = "created_at", updatedAt = "updated_at"
```

- [ ] **Step 4: Add the migration.** In `LibraryStore.swift`, after the `v5-links` block (before `return m`):

```swift
        m.registerMigration("v6-code-ready") { db in
            try db.alter(table: "papers") { t in
                t.add(column: "code_ready", .integer).notNull().defaults(to: 0)
            }
        }
```

- [ ] **Step 5: Run the test to verify it passes.**

Run: `cd NimbleScholarCore && swift test --filter CodeReadyTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit.**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Models/Paper.swift NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift NimbleScholarCore/Tests/NimbleScholarCoreTests/CodeReadyTests.swift
git commit -m "feat(core): Paper.code_ready + v6 migration"
```

---

## Task 2: Core `GitHubRepo` (TDD, pure)

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Services/GitHubRepo.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/GitHubRepoTests.swift`

- [ ] **Step 1: Write the failing tests.** Create `GitHubRepoTests.swift`:

```swift
import XCTest
@testable import NimbleScholarCore

final class GitHubRepoTests: XCTestCase {
    func testOwnerRepoWithScheme() {
        let r = GitHubRepo.ownerRepo(from: "https://github.com/facebookresearch/detectron2")
        XCTAssertEqual(r?.owner, "facebookresearch")
        XCTAssertEqual(r?.repo, "detectron2")
    }
    func testOwnerRepoStripsGitAndExtraPath() {
        XCTAssertEqual(GitHubRepo.ownerRepo(from: "github.com/a/b.git")?.repo, "b")
        XCTAssertEqual(GitHubRepo.ownerRepo(from: "https://github.com/a/b/tree/main")?.repo, "b")
    }
    func testOwnerRepoRejectsNonRepo() {
        XCTAssertNil(GitHubRepo.ownerRepo(from: "https://example.com/a/b"))
        XCTAssertNil(GitHubRepo.ownerRepo(from: "https://github.com/onlyowner"))
    }
    func testReleasedWhenRealFilesPresent() {
        XCTAssertTrue(GitHubRepo.isReleased(rootEntryNames: ["README.md", "train.py", "src"]))
    }
    func testNotReleasedForDocsOnlyOrEmpty() {
        XCTAssertFalse(GitHubRepo.isReleased(rootEntryNames: ["README.md", "LICENSE", ".gitignore"]))
        XCTAssertFalse(GitHubRepo.isReleased(rootEntryNames: ["README.md"]))
        XCTAssertFalse(GitHubRepo.isReleased(rootEntryNames: []))
    }
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `cd NimbleScholarCore && swift test --filter GitHubRepoTests`
Expected: FAIL — `cannot find 'GitHubRepo' in scope`.

- [ ] **Step 3: Implement `GitHubRepo`.** Create `GitHubRepo.swift`:

```swift
import Foundation

/// Pure helpers for reasoning about a GitHub repo URL and its release state.
public enum GitHubRepo {
    /// Parse "…github.com/<owner>/<repo>…" → (owner, repo). nil if there's no owner/repo.
    public static func ownerRepo(from url: String) -> (owner: String, repo: String)? {
        guard let range = url.range(of: "github.com/", options: .caseInsensitive) else { return nil }
        let comps = url[range.upperBound...]
            .split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard comps.count >= 2 else { return nil }
        var repo = comps[1]
        if repo.lowercased().hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        return (comps[0], repo)
    }

    private static let docStems: Set<String> = [
        "readme", "license", "licence", "contributing", "code_of_conduct",
        "citation", "changelog", "authors", "notice",
    ]
    private static let docExact: Set<String> = [".gitignore", ".gitattributes", ".github"]

    /// Given the names of a repo's root entries, is there real content beyond docs/meta files?
    /// An empty list (empty repo) or docs-only list is treated as not released.
    public static func isReleased(rootEntryNames names: [String]) -> Bool {
        for name in names {
            let lower = name.lowercased()
            if docExact.contains(lower) { continue }
            let stem = lower.split(separator: ".").first.map(String.init) ?? lower
            if docStems.contains(stem) { continue }
            return true
        }
        return false
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `cd NimbleScholarCore && swift test --filter GitHubRepoTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit.**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Services/GitHubRepo.swift NimbleScholarCore/Tests/NimbleScholarCoreTests/GitHubRepoTests.swift
git commit -m "feat(core): GitHubRepo — owner/repo parse + released? predicate"
```

---

## Task 3: App `GitHubRepoChecker`

**Files:**
- Create: `NimbleScholar/Library/GitHubRepoChecker.swift`

No unit test (network); verified by build + the watcher's manual test.

- [ ] **Step 1: Create `GitHubRepoChecker.swift`.**

```swift
import Foundation
import NimbleScholarCore

enum RepoStatus: Equatable { case released, notReleased, rateLimited, error }

/// Checks a GitHub repo's release state via the contents API.
/// Unauthenticated (60 req/hr); `.rateLimited` lets the caller stop and resume later.
enum GitHubRepoChecker {
    static func check(_ codeURL: String, session: URLSession) async -> RepoStatus {
        guard let (owner, repo) = GitHubRepo.ownerRepo(from: codeURL),
              let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents") else {
            return .error
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("NimbleScholar", forHTTPHeaderField: "User-Agent")  // GitHub rejects no-UA
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else { return .error }
        switch http.statusCode {
        case 404: return .notReleased                  // empty repo or missing
        case 403: return .rateLimited
        case 200:
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return .error
            }
            let names = arr.compactMap { $0["name"] as? String }
            return GitHubRepo.isReleased(rootEntryNames: names) ? .released : .notReleased
        default:
            return .error
        }
    }
}
```

- [ ] **Step 2: Verify it builds (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds with no errors referencing `GitHubRepoChecker`/`RepoStatus`.

- [ ] **Step 3: Commit.**

```bash
git add NimbleScholar/Library/GitHubRepoChecker.swift
git commit -m "feat(app): GitHubRepoChecker — repo released? via contents API"
```

---

## Task 4: Actionable notifications

**Files:**
- Modify: `NimbleScholar/App/Notifier.swift`

- [ ] **Step 1: Replace `Notifier.swift`** with the URL-carrying version + a delegate:

```swift
import Foundation
import UserNotifications
import AppKit

/// Thin wrapper over macOS user notifications. Surfaces capture problems and
/// code-release events; tapping a notification with a `url` opens it.
enum Notifier {
    private static let delegate = NotifierDelegate()

    /// Ask once (at launch) for permission and install the tap-to-open delegate.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().delegate = delegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String, url: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let url { content.userInfo = ["url": url] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Shows banners while the app is foreground and opens a notification's `url` on tap.
final class NotifierDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let urlString = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: urlString) else { return }
        await MainActor.run { NSWorkspace.shared.open(url) }
    }
}
```

(The existing `Notifier.notify(title:body:)` call site in `AppEnvironment.makeCaptureHandler` still compiles — `url` defaults to nil.)

- [ ] **Step 2: Verify it builds (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds; capture-issue notifications still work; no `url` errors.

- [ ] **Step 3: Commit.**

```bash
git add NimbleScholar/App/Notifier.swift
git commit -m "feat(app): notifications carry a URL + open it on tap"
```

---

## Task 5: `CodeWatcher` + wiring

**Files:**
- Create: `NimbleScholar/Library/CodeWatcher.swift`
- Modify: `NimbleScholar/AppEnvironment.swift`
- Modify: `NimbleScholar/App/NimbleScholarApp.swift`

- [ ] **Step 1: Create `CodeWatcher.swift`.**

```swift
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
```

- [ ] **Step 2: Own + expose it in `AppEnvironment`.** In `AppEnvironment.swift`, add a stored property after `let updater = UpdaterController()`:

```swift
    /// Watches papers for a code release (see CodeWatcher). Started from the library view.
    var codeWatcher: CodeWatcher?
```

Add a start method (place it next to `makeCaptureHandler()`):

```swift
    /// Create + start the code watcher once (idempotent). Called on the main thread when
    /// the library window appears.
    @MainActor
    func startCodeWatcherIfNeeded() {
        guard codeWatcher == nil else { return }
        let watcher = CodeWatcher(store: store, session: networkSession)
        codeWatcher = watcher
        watcher.start()
    }
```

- [ ] **Step 3: Start it from the library window.** In `NimbleScholar/App/NimbleScholarApp.swift`, change the first `WindowGroup`'s content:

```swift
        WindowGroup("Nimble Scholar") {
            LibraryContentView()
                .environmentObject(env)
                .onAppear { env.startCodeWatcherIfNeeded() }
        }
```

- [ ] **Step 4: Verify it builds + sweeps (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds; on launch the status bar briefly shows "Checking for code…"; the first sweep is silent (sets `codeWatchReconciled`). No crashes.

- [ ] **Step 5: Commit.**

```bash
git add NimbleScholar/Library/CodeWatcher.swift NimbleScholar/AppEnvironment.swift NimbleScholar/App/NimbleScholarApp.swift
git commit -m "feat(app): CodeWatcher — sweep for code releases, notify on new ones"
```

---

## Task 6: UI — gated Code button, watching caption, manual sweep, edit override

**Files:**
- Modify: `NimbleScholar/Library/PaperDetailView.swift`
- Modify: `NimbleScholar/Library/PaperEditSheet.swift`
- Modify: `NimbleScholar/Library/LibraryContentView.swift`

- [ ] **Step 1: Gate the Code button + add a watching caption.** In `PaperDetailView.swift`, replace the whole links block (the `if !paper.projectURL.isEmpty || !paper.codeURL.isEmpty { … } else { Button("Add links…") … }`) with:

```swift
                VStack(alignment: .leading, spacing: 6) {
                    if !paper.projectURL.isEmpty || hasReadyCode {
                        HStack(spacing: 8) {
                            if !paper.projectURL.isEmpty {
                                Button { openLink(paper.projectURL) } label: {
                                    Label("Project", systemImage: "globe")
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                            if hasReadyCode {
                                Button { openLink(paper.codeURL) } label: {
                                    Label { Text("Code") } icon: {
                                        Image("GitHubMark").renderingMode(.template)
                                    }
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                    if isWatchingCode {
                        Label("Watching for code release", systemImage: "hourglass")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if paper.projectURL.isEmpty && paper.codeURL.isEmpty {
                        Button("Add links…") { vm.editingPaper = paper }
                            .buttonStyle(.borderless).controlSize(.small)
                            .font(.caption)
                    }
                }
```

- [ ] **Step 2: Add the computed helpers.** In `struct PaperDetailView`, next to `openLink` (after `var body`):

```swift
    private var hasReadyCode: Bool { !paper.codeURL.isEmpty && paper.codeReady }
    /// No confirmed code yet, but there's a source we keep re-checking.
    private var isWatchingCode: Bool {
        !hasReadyCode && (!paper.url.isEmpty || !paper.projectURL.isEmpty || !paper.codeURL.isEmpty)
    }
```

- [ ] **Step 3: Manual override in the Edit sheet.** In `PaperEditSheet.swift`, change the Save button so a manually entered code link shows immediately:

```swift
                Button("Save") {
                    paper.codeReady = !paper.codeURL.isEmpty
                    vm.save(paper)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
```

- [ ] **Step 4: Add "Check for code now" to the ⋯ menu.** In `LibraryContentView.swift`, inside the Actions `Menu`, after the `Button("Re-fetch all figures") { … }` line:

```swift
                    Button("Check for code now") {
                        Task { await AppEnvironment.shared.codeWatcher?.sweep(force: true) }
                    }
```

- [ ] **Step 5: Verify (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: a paper with a real repo shows the **Code** button; one with only a project page (or no code yet) shows **"⏳ Watching for code release"**; ⋯ menu has **Check for code now**; entering a Code URL in Edit + Save shows the Code button immediately.

- [ ] **Step 6: Run the full core suite** (nothing in Core changed behaviorally beyond additions, but confirm).

Run: `cd NimbleScholarCore && swift test`
Expected: all tests pass.

- [ ] **Step 7: Commit.**

```bash
git add NimbleScholar/Library/PaperDetailView.swift NimbleScholar/Library/PaperEditSheet.swift NimbleScholar/Library/LibraryContentView.swift
git commit -m "feat(ui): gated Code button + watching caption + Check for code now"
```

---

## Manual end-to-end test (macOS)

- [ ] Edit a watched paper, set its **Code URL** to a real repo (e.g. `https://github.com/facebookresearch/detectron2`) → after Save it shows the **Code** button.
- [ ] Set another paper's Code URL to an **empty** repo and clear `code_ready` (or use a placeholder repo with only a README), run **Check for code now** → it stays **"Watching for code release"**, no Code button.
- [ ] Point one at a repo that has real files → **Check for code now** → it flips to a Code button and (after the first reconciled sweep) posts a **"Code released"** notification; clicking the notification opens the repo.
- [ ] Confirm the **first** sweep after upgrade posts no notifications (reconciliation), and relaunching doesn't re-sweep within 20h.

---

## Self-review notes

- **Spec coverage:** `code_ready` + `v6` (Task 1); Core readiness predicate + parse (Task 2); GitHub API checker with rate-limit status (Task 3); actionable notification + delegate (Task 4); `CodeWatcher` sweep (launch/24h/manual), silent first-sweep reconciliation, discovery via `LinkFinder` (Task 5); UI gating + watching caption + manual menu + edit override (Task 6). Testing: Core unit (Tasks 1, 2) + manual (3–6). All spec sections mapped.
- **Type/name consistency:** `Paper.codeReady`; `GitHubRepo.ownerRepo(from:)`/`isReleased(rootEntryNames:)`; `RepoStatus{released,notReleased,rateLimited,error}`; `GitHubRepoChecker.check(_:session:)`; `CodeWatcher.sweep(force:)`/`start()`/`isWatchable`; `Notifier.notify(title:body:url:)`; `AppEnvironment.codeWatcher`/`startCodeWatcherIfNeeded()` — consistent across tasks.
- **Reconciliation:** `codeWatchReconciled` is set only after a sweep finishes without `.rateLimited`, so the first (silent) reconciliation completes across multiple sweeps if rate-limited, and notifications begin only afterward. `notifyReleased` is gated on `reconciled` in both the re-check and discovery branches.
- **Concurrency:** `CodeWatcher` is `@MainActor`, created/started from the library view's `onAppear` (main thread), avoiding the actor-isolated-init problem; network/`LinkFinder`/`GitHubRepoChecker` awaits hop off-main and back.
