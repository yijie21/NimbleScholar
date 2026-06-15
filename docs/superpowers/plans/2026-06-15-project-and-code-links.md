# Project & Code (GitHub) Links — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-extract a paper's project-page and open-source (GitHub) links from its PDF + abstract page, show them as buttons on the detail view, allow manual entry, and backfill existing papers in the background with per-item status.

**Architecture:** A pure, tested `LinkExtractor` in `NimbleScholarCore` classifies links from text + HTML anchors. An app-side `LinkFinder` gathers the inputs (PDFKit link annotations/text + a fetched abstract/landing page, and follows a project page to find GitHub). New `Paper` columns store the results; the existing auto-complete loop scans each paper once with a "Finding links…" status. The detail view shows Project/Code buttons or an "Add links…" entry; the Edit sheet gets URL fields.

**Tech Stack:** Swift/SwiftUI, GRDB (migration), SwiftSoup (Core, HTML anchors), PDFKit (app, PDF text/annotations), XCTest.

**Environment note:** `swift test` / `xcodebuild` require macOS + Xcode (run on the user's Mac). No Swift toolchain on the dev host.

**Reference spec:** `docs/superpowers/specs/2026-06-15-project-and-code-links-design.md`

---

## File map

**Create:**
- `NimbleScholarCore/Sources/NimbleScholarCore/Services/LinkExtractor.swift` — pure link classification + HTML anchor parsing
- `NimbleScholarCore/Tests/NimbleScholarCoreTests/LinkExtractorTests.swift` — unit tests
- `NimbleScholarCore/Tests/NimbleScholarCoreTests/ProjectCodeLinksTests.swift` — store round-trip test
- `NimbleScholar/Library/LinkFinder.swift` — app-side PDF + network orchestration

**Modify:**
- `NimbleScholarCore/Sources/NimbleScholarCore/Models/Paper.swift` — add `projectURL`, `codeURL`, `linksScanned`
- `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift` — `v5-links` migration
- `NimbleScholar/Library/LibraryViewModel.swift` — backfill (needsCompletion + complete step 3)
- `NimbleScholar/Library/PaperDetailView.swift` — Project/Code buttons + "Add links…"
- `NimbleScholar/Library/PaperEditSheet.swift` — Project URL + Code URL fields

---

## Task 1: Paper columns + migration

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Models/Paper.swift`
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/ProjectCodeLinksTests.swift`

- [ ] **Step 1: Write the failing test.** Create `ProjectCodeLinksTests.swift`:

```swift
import XCTest
import GRDB
@testable import NimbleScholarCore

final class ProjectCodeLinksTests: XCTestCase {
    func testLinksRoundTripThroughStore() throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        var p = Paper(title: "X")
        p.projectURL = "https://proj.github.io"
        p.codeURL = "https://github.com/a/b"
        p.linksScanned = true
        let saved = try store.create(p)
        let back = try XCTUnwrap(store.paper(id: saved.id!))
        XCTAssertEqual(back.projectURL, "https://proj.github.io")
        XCTAssertEqual(back.codeURL, "https://github.com/a/b")
        XCTAssertTrue(back.linksScanned)
    }
}
```

- [ ] **Step 2: Run it to verify it fails.**

Run: `cd NimbleScholarCore && swift test --filter ProjectCodeLinksTests`
Expected: FAIL — `value of type 'Paper' has no member 'projectURL'`.

- [ ] **Step 3: Add the Paper properties + column mappings.** In `Paper.swift`, add the three stored properties after `isRead` (line ~22):

```swift
    public var isRead: Bool = false
    public var projectURL: String = ""
    public var codeURL: String = ""
    public var linksScanned: Bool = false
    public var createdAt: Int64 = 0
```

Add to the `Columns` enum (after the `isRead = "read"` case):

```swift
        case isRead = "read"
        case projectURL = "project_url", codeURL = "code_url", linksScanned = "links_scanned"
        case createdAt = "created_at", updatedAt = "updated_at"
```

Add the identical cases to the `CodingKeys` enum:

```swift
        case isRead = "read"
        case projectURL = "project_url", codeURL = "code_url", linksScanned = "links_scanned"
        case createdAt = "created_at", updatedAt = "updated_at"
```

- [ ] **Step 4: Add the migration.** In `LibraryStore.swift`, after the `v4-chat` migration block (before `return m`):

```swift
        m.registerMigration("v5-links") { db in
            try db.alter(table: "papers") { t in
                t.add(column: "project_url", .text).notNull().defaults(to: "")
                t.add(column: "code_url", .text).notNull().defaults(to: "")
                t.add(column: "links_scanned", .integer).notNull().defaults(to: 0)
            }
        }
```

- [ ] **Step 5: Run the test to verify it passes.**

Run: `cd NimbleScholarCore && swift test --filter ProjectCodeLinksTests`
Expected: PASS.

- [ ] **Step 6: Run the full core suite to confirm nothing else broke** (the FTS sync triggers only touch title/authors/abstract/summary/venue/doi, so new columns are safe).

Run: `cd NimbleScholarCore && swift test`
Expected: all tests pass.

- [ ] **Step 7: Commit.**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Models/Paper.swift NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift NimbleScholarCore/Tests/NimbleScholarCoreTests/ProjectCodeLinksTests.swift
git commit -m "feat(core): Paper project_url/code_url/links_scanned + v5 migration"
```

---

## Task 2: `LinkExtractor` classification (TDD, pure)

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Services/LinkExtractor.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/LinkExtractorTests.swift`

- [ ] **Step 1: Write the failing tests.** Create `LinkExtractorTests.swift`:

```swift
import XCTest
@testable import NimbleScholarCore

final class LinkExtractorTests: XCTestCase {
    func testFindsGithubInText() {
        let t = "Code is available at https://github.com/facebookresearch/detectron2 for use."
        XCTAssertEqual(LinkExtractor.codeURL(in: t), "https://github.com/facebookresearch/detectron2")
    }
    func testStripsGitSuffixAndPunctuationAndAddsScheme() {
        XCTAssertEqual(LinkExtractor.codeURL(in: "(see github.com/foo/bar.git)."),
                       "https://github.com/foo/bar")
    }
    func testRejectsBareOwnerAndPagesAndReservedOwners() {
        XCTAssertNil(LinkExtractor.codeURL(in: "Visit https://github.com/google here"))   // no repo
        XCTAssertNil(LinkExtractor.codeURL(in: "https://foo.github.io/proj"))             // pages, not code
        XCTAssertNil(LinkExtractor.codeURL(in: "https://github.com/sponsors/foo"))        // reserved owner
    }
    func testProjectFromGithubIOAndCodeTogether() {
        let links = LinkExtractor.extract(text: "Project https://myproj.github.io/site code github.com/me/repo")
        XCTAssertEqual(links.projectURL, "https://myproj.github.io/site")
        XCTAssertEqual(links.codeURL, "https://github.com/me/repo")
    }
    func testProjectFromLabeledAnchorIgnoresArxiv() {
        let anchors = [
            HTMLAnchor(href: "https://arxiv.org/abs/1234.5678", label: "arXiv"),
            HTMLAnchor(href: "https://example.edu/cool-paper", label: "Project Page"),
        ]
        let links = LinkExtractor.extract(text: "", anchors: anchors)
        XCTAssertEqual(links.projectURL, "https://example.edu/cool-paper")
        XCTAssertNil(links.codeURL)
    }
    func testCodeFromAnchorWhenNotInText() {
        let anchors = [HTMLAnchor(href: "https://github.com/a/b", label: "GitHub")]
        XCTAssertEqual(LinkExtractor.extract(text: "", anchors: anchors).codeURL, "https://github.com/a/b")
    }
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `cd NimbleScholarCore && swift test --filter LinkExtractorTests`
Expected: FAIL — `cannot find 'LinkExtractor' in scope`.

- [ ] **Step 3: Implement `LinkExtractor`.** Create `LinkExtractor.swift`:

```swift
import Foundation
import SwiftSoup

public struct HTMLAnchor: Equatable {
    public let href: String
    public let label: String
    public init(href: String, label: String) { self.href = href; self.label = label }
}

public struct ExtractedLinks: Equatable {
    public var projectURL: String?
    public var codeURL: String?
    public init(projectURL: String? = nil, codeURL: String? = nil) {
        self.projectURL = projectURL; self.codeURL = codeURL
    }
}

/// Pure classification of project-page and GitHub links from text + HTML anchors.
public enum LinkExtractor {
    /// github.com/<owner>/<repo> owners that are site features, not user repos.
    private static let reservedOwners: Set<String> = [
        "sponsors", "about", "features", "topics", "orgs", "login", "settings",
        "marketplace", "pulls", "issues", "notifications", "explore", "collections", "apps",
    ]

    // MARK: GitHub (code)

    public static func codeURL(in text: String) -> String? {
        // optional scheme/www; require owner/repo; word boundary so "notgithub.com" doesn't match.
        let pattern = #"(?<![\w.])(?:https?://)?(?:www\.)?github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for m in re.matches(in: text, range: range) {
            guard let r = Range(m.range, in: text) else { continue }
            var url = cleanTrailing(String(text[r]))
            if url.lowercased().hasSuffix(".git") { url = String(url.dropLast(4)) }
            if !url.lowercased().hasPrefix("http") { url = "https://" + url }
            // owner = path component right after github.com/
            let path = url.components(separatedBy: "github.com/").last ?? ""
            let owner = path.components(separatedBy: "/").first?.lowercased() ?? ""
            if reservedOwners.contains(owner) { continue }
            return url
        }
        return nil
    }

    public static func codeURL(inAnchors anchors: [HTMLAnchor]) -> String? {
        for a in anchors { if let u = codeURL(in: a.href) { return u } }
        return nil
    }

    // MARK: Project page (strong signals only)

    public static func projectURL(in text: String, anchors: [HTMLAnchor]) -> String? {
        // 1. an anchor labeled like a project page (and not arXiv/DOI/GitHub).
        if let labelRE = try? NSRegularExpression(
            pattern: #"project\s*(page|website|site)?|home\s*page|website"#, options: [.caseInsensitive]) {
            for a in anchors where isHTTP(a.href) && !isExcludedForProject(a.href) {
                if labelRE.firstMatch(in: a.label, range: NSRange(a.label.startIndex..., in: a.label)) != nil {
                    return cleanTrailing(a.href)
                }
            }
        }
        // 2. a *.github.io URL.
        if let g = firstMatch(#"https?://[A-Za-z0-9-]+\.github\.io[^\s)\]}"'<>]*"#, in: text, anchors: anchors) {
            return cleanTrailing(g)
        }
        // 3. a sites.google.com URL.
        if let s = firstMatch(#"https?://sites\.google\.com[^\s)\]}"'<>]*"#, in: text, anchors: anchors) {
            return cleanTrailing(s)
        }
        return nil
    }

    public static func extract(text: String, anchors: [HTMLAnchor] = []) -> ExtractedLinks {
        ExtractedLinks(
            projectURL: projectURL(in: text, anchors: anchors),
            codeURL: codeURL(in: text) ?? codeURL(inAnchors: anchors)
        )
    }

    // MARK: HTML anchors

    public static func anchors(inHTMLData data: Data) -> [HTMLAnchor] {
        guard let html = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(html),
              let els = try? doc.select("a[href]") else { return [] }
        return els.array().compactMap { el in
            let href = (try? el.attr("href")) ?? ""
            guard !href.isEmpty else { return nil }
            let label = ((try? el.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return HTMLAnchor(href: href, label: label)
        }
    }

    // MARK: Helpers

    private static func isHTTP(_ s: String) -> Bool { s.hasPrefix("http://") || s.hasPrefix("https://") }
    private static func isExcludedForProject(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("arxiv.org") || l.contains("doi.org") || l.contains("github.com")
    }
    private static func cleanTrailing(_ s: String) -> String {
        var x = s
        while let last = x.last, ").,;]>'\"".contains(last) { x.removeLast() }
        return x
    }
    private static func firstMatch(_ pattern: String, in text: String, anchors: [HTMLAnchor]) -> String? {
        let hay = text + "\n" + anchors.map { $0.href }.joined(separator: "\n")
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: hay, range: NSRange(hay.startIndex..., in: hay)),
              let r = Range(m.range, in: hay) else { return nil }
        return String(hay[r])
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `cd NimbleScholarCore && swift test --filter LinkExtractorTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit.**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Services/LinkExtractor.swift NimbleScholarCore/Tests/NimbleScholarCoreTests/LinkExtractorTests.swift
git commit -m "feat(core): LinkExtractor — classify project + GitHub links"
```

---

## Task 3: `anchors(inHTMLData:)` test (SwiftSoup parsing)

**Files:**
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/LinkExtractorTests.swift`

- [ ] **Step 1: Add a failing test** to `LinkExtractorTests.swift` (inside the class):

```swift
    func testAnchorsParsing() {
        let html = """
        <html><body>
          <a href="https://github.com/a/b">Code</a>
          <a href="https://x.github.io">Project Page</a>
        </body></html>
        """
        let anchors = LinkExtractor.anchors(inHTMLData: Data(html.utf8))
        XCTAssertEqual(anchors.count, 2)
        XCTAssertEqual(anchors[0].href, "https://github.com/a/b")
        XCTAssertEqual(anchors[0].label, "Code")
        XCTAssertEqual(anchors[1].label, "Project Page")
    }
```

- [ ] **Step 2: Run it.** (`anchors(inHTMLData:)` already exists from Task 2, so this should pass immediately — it verifies the SwiftSoup parsing contract.)

Run: `cd NimbleScholarCore && swift test --filter LinkExtractorTests/testAnchorsParsing`
Expected: PASS.

- [ ] **Step 3: Commit.**

```bash
git add NimbleScholarCore/Tests/NimbleScholarCoreTests/LinkExtractorTests.swift
git commit -m "test(core): cover LinkExtractor.anchors HTML parsing"
```

---

## Task 4: `LinkFinder` (app: PDF + network)

**Files:**
- Create: `NimbleScholar/Library/LinkFinder.swift`

No unit test (needs PDFKit + network); verified by build + manual run.

- [ ] **Step 1: Create `LinkFinder.swift`.**

```swift
import Foundation
import PDFKit
import NimbleScholarCore

/// Gathers a paper's link candidates and classifies them via `LinkExtractor`.
/// Inputs: the cached PDF's link annotations + text, and the abstract/landing HTML page.
/// If a project page is found but no GitHub link, follows the project page to find one.
enum LinkFinder {
    static func find(for paper: Paper, session: URLSession, followProject: Bool = true) async -> ExtractedLinks {
        let text = pdfText(for: paper)
        let anchors = await pageAnchors(for: paper, session: session)
        var links = LinkExtractor.extract(text: text, anchors: anchors)

        if followProject, let project = links.projectURL, links.codeURL == nil,
           let data = try? await fetch(project, session: session) {
            let projectAnchors = LinkExtractor.anchors(inHTMLData: data)
            let projectText = String(data: data, encoding: .utf8) ?? ""
            links.codeURL = LinkExtractor.codeURL(inAnchors: projectAnchors)
                ?? LinkExtractor.codeURL(in: projectText)
        }
        return links
    }

    /// PDF link-annotation URLs (clean) + page text (fallback), joined into one blob.
    private static func pdfText(for paper: Paper) -> String {
        guard paper.hasLocalPDF,
              let doc = PDFDocument(url: URL(fileURLWithPath: paper.pdfPath)) else { return "" }
        var parts: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            for ann in page.annotations {
                if let urlAction = ann.action as? PDFActionURL, let u = urlAction.url {
                    parts.append(u.absoluteString)
                }
            }
            if let s = page.string { parts.append(s) }
        }
        return parts.joined(separator: "\n")
    }

    private static func pageAnchors(for paper: Paper, session: URLSession) async -> [HTMLAnchor] {
        guard let pageURL = abstractOrLandingURL(for: paper),
              let data = try? await fetch(pageURL, session: session) else { return [] }
        return LinkExtractor.anchors(inHTMLData: data)
    }

    /// arXiv abstract page by id; else the paper's HTML landing page (CVF raw-PDF → /html/).
    private static func abstractOrLandingURL(for paper: Paper) -> String? {
        if let id = ArxivService.extractID(from: paper.url) { return ArxivService.absURL(forID: id) }
        let u = paper.url
        guard !u.isEmpty else { return nil }
        if u.lowercased().hasSuffix(".pdf") {
            guard u.contains("/papers/") else { return nil }
            return u.replacingOccurrences(of: "/papers/", with: "/html/")
                    .replacingOccurrences(of: ".pdf", with: ".html")
        }
        return u
    }

    private static func fetch(_ urlString: String, session: URLSession) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        return data
    }
}
```

- [ ] **Step 2: Verify it builds (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds and launches with no errors referencing `LinkFinder`/`PDFActionURL`. (`NimbleScholar/Library` is already in the XcodeGen sources, so the new file is picked up.)

- [ ] **Step 3: Commit.**

```bash
git add NimbleScholar/Library/LinkFinder.swift
git commit -m "feat(app): LinkFinder — PDF + abstract-page link extraction"
```

---

## Task 5: Backfill in `LibraryViewModel`

**Files:**
- Modify: `NimbleScholar/Library/LibraryViewModel.swift`

- [ ] **Step 1: Extend `needsCompletion` + add `canScanLinks`.** Replace the `needsCompletion(_:)` method (around line 210) with:

```swift
    private func needsCompletion(_ p: Paper) -> Bool {
        if !p.hasLocalPDF { return true }
        if !p.hasFigure, canFetchFigure(p) { return true }
        if !p.linksScanned, canScanLinks(p) { return true }
        return false
    }

    /// We can look for project/code links once there's a PDF to read, an arXiv id, or a
    /// landing page to scrape.
    private func canScanLinks(_ p: Paper) -> Bool {
        p.hasLocalPDF || ArxivService.extractID(from: p.url) != nil || landingPageURL(for: p) != nil
    }
```

- [ ] **Step 2: Add the link-scan step to `complete(_:)`.** In `complete(_:)`, after the PDF block (the `if !cur.hasLocalPDF { … }` block) and before `ActivityCenter.shared.endItem(id)`:

```swift
            // 3. Project / code links (once per paper).
            if !cur.linksScanned, canScanLinks(cur) {
                ActivityCenter.shared.beginItem(id, "Finding links…")
                let links = await LinkFinder.find(for: cur, session: AppEnvironment.shared.networkSession)
                if let project = links.projectURL { cur.projectURL = project }
                if let code = links.codeURL { cur.codeURL = code }
                cur.linksScanned = true
                _ = try? store.update(cur)
            }
```

- [ ] **Step 3: Verify it builds + scans (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds; on launch, existing papers show **"Finding links…"** per item and the bottom "Preparing papers — n/m" bar; each is scanned once (re-launch should not re-scan, since `links_scanned` is now 1).

- [ ] **Step 4: Commit.**

```bash
git add NimbleScholar/Library/LibraryViewModel.swift
git commit -m "feat(app): backfill project/code links in the auto-complete loop"
```

---

## Task 6: Detail view buttons + "Add links…"

**Files:**
- Modify: `NimbleScholar/Library/PaperDetailView.swift`

- [ ] **Step 1: Add a links row.** In `PaperDetailView.body`, insert this **after** the existing button `HStack { … }` (the one with Read/Browser/Edit/Delete, ends around line 35) and before `FlowTags(...)`:

```swift
                if !paper.projectURL.isEmpty || !paper.codeURL.isEmpty {
                    HStack(spacing: 8) {
                        if !paper.projectURL.isEmpty {
                            Button { openLink(paper.projectURL) } label: {
                                Label("Project", systemImage: "globe")
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                        if !paper.codeURL.isEmpty {
                            Button { openLink(paper.codeURL) } label: {
                                Label("Code", systemImage: "chevron.left.forward.slash")
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                } else {
                    Button("Add links…") { vm.editingPaper = paper }
                        .buttonStyle(.borderless).controlSize(.small)
                        .font(.caption)
                }
```

- [ ] **Step 2: Add the `openLink` helper.** Inside `struct PaperDetailView`, after `var body` (e.g. before the closing brace of the struct, around line 46):

```swift
    private func openLink(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
```

- [ ] **Step 3: Verify (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: a paper with a code link shows a **Code** button (opens GitHub); a paper with a project link shows **Project**; a paper with neither shows **"Add links…"** (opens the Edit sheet).

- [ ] **Step 4: Commit.**

```bash
git add NimbleScholar/Library/PaperDetailView.swift
git commit -m "feat(detail): Project/Code link buttons + Add links entry"
```

---

## Task 7: Edit-sheet manual fields

**Files:**
- Modify: `NimbleScholar/Library/PaperEditSheet.swift`

- [ ] **Step 1: Add the fields.** In `PaperEditSheet.body`'s `Form`, after the `TextField("PDF URL", text: $paper.pdfURL)` line:

```swift
                TextField("Project URL", text: $paper.projectURL)
                TextField("Code URL (GitHub)", text: $paper.codeURL)
```

- [ ] **Step 2: Verify (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: the Edit sheet shows **Project URL** and **Code URL** fields; setting them and pressing **Save** persists, and the detail view immediately shows the corresponding buttons.

- [ ] **Step 3: Commit.**

```bash
git add NimbleScholar/Library/PaperEditSheet.swift
git commit -m "feat(edit): manual Project URL / Code URL fields"
```

---

## Self-review notes

- **Spec coverage:** data model + `v5-links` (Task 1); Core `LinkExtractor` classify + anchors (Tasks 2, 3); app `LinkFinder` with PDF annotations/text + abstract page + follow-project (Task 4); backfill in auto-complete with "Finding links…" status (Task 5); detail buttons + "Add links…" (Task 6); Edit-sheet manual fields (Task 7). Testing: Core unit tests (Tasks 1–3) + manual (Tasks 4–7). All spec sections mapped.
- **Type/name consistency:** `ExtractedLinks{projectURL,codeURL}`, `HTMLAnchor{href,label}`, `LinkExtractor.extract/codeURL/projectURL/anchors(inHTMLData:)`, `LinkFinder.find(for:session:followProject:)`, `Paper.projectURL/codeURL/linksScanned`, `canScanLinks` — used identically across tasks.
- **Ordering:** Task 5's `complete()` runs the link scan after the PDF step, so `cur.pdfPath` is set and `LinkFinder` can read PDF text; `linksScanned` is set even on empty results, so the loop terminates and won't re-scan on relaunch.
- **Note (intentional):** line-wrapped URLs in PDF *text* may be missed; PDF link *annotations* (clean URLs) and HTML anchors are the primary, reliable sources — matching the spec.
