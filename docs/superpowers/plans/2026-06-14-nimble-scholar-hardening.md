# Nimble Scholar Hardening & Completion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the existing Nimble Scholar macOS app — fix bugs, optimize performance, add the missing paper-manager features, remove dead code, and document it — across four phases.

**Architecture:** Unchanged: a tested `NimbleScholarCore` SwiftPM package (models, GRDB store, services, capture server) + a SwiftUI/PDFKit app target. New *logic* goes into the core and is covered by `swift test`; UI changes are verified by building & running on the Mac.

**Tech Stack:** Swift 5.9+, SwiftUI, PDFKit, GRDB.swift, FlyingFox, SwiftSoup, XCTest. macOS 14+.

---

## Environment & conventions

- **Core tests run on the Mac:** `cd NimbleScholarCore && swift test`. The Linux dev box can author but not build Swift.
- **UI verification (labeled `VERIFY ON MAC`):** `pkill -9 -f 'MacOS/NimbleScholar'; bash scripts/mac_bootstrap.sh full run`.
- Each phase is a batch; keep `main` green. Migrations are additive.
- Commit trailer convention omitted here for brevity; add your standard co-author trailer.

## File map (what changes)

```
NimbleScholarCore/Sources/NimbleScholarCore/
  Store/LibraryStore.swift        # FTS sanitize, paper(id:), paper(arxivID:), allTagsByPaper(),
                                  #   read column + setRead, annotation reconcile helpers, backup/restore store half
  Models/Paper.swift              # add isRead ("read") column
  Capture/CaptureHandler.swift    # duplicate detection (update existing)
  Services/MarkdownExporter.swift # NEW — annotations → markdown
Tests/NimbleScholarCoreTests/...  # new tests per task

NimbleScholar/ (app)
  NimbleScholarApp.swift, BootCheckView.swift   # DELETE (dead)
  Reader/AnnotationController.swift              # deleteIndexed(), reconcile
  Reader/InspectorPanel.swift                    # consistent delete
  Reader/ReaderViewModel.swift                   # paper(id:), reconcile on load, markRead, export
  Library/LibraryViewModel.swift                 # batched tag map, read filter, dup feedback, multi-select, import, backup
  Library/*View.swift                            # tag map, read dot, empty states, shortcuts, multi-select
  Library/PaperContextMenu.swift                 # Reveal/Open/Re-fetch/Mark read/Export md
  Library/ThumbnailCache.swift                   # disk cap + prewarm
  App/NimbleScholarApp.swift                     # commands/shortcuts, import handling
docs/ARCHITECTURE.md              # NEW
scripts/mac_bootstrap.sh          # drop obsolete c-mode source set
```

---

# PHASE 1 — Correctness & cleanup

### Task 1: Remove dead code

**Files:**
- Delete: `NimbleScholar/NimbleScholarApp.swift`, `NimbleScholar/BootCheckView.swift`
- Delete: `NimbleScholarCore/Sources/NimbleScholarCore/Placeholder.swift`
- Modify: `NimbleScholarCore/Tests/NimbleScholarCoreTests/SmokeTests.swift`
- Modify: `scripts/mac_bootstrap.sh`

- [ ] **Step 1: Replace the version stub with a real namespace constant**

Create `NimbleScholarCore/Sources/NimbleScholarCore/Version.swift`:

```swift
public enum NimbleScholar {
    public static let coreVersion = "1.0.0"
}
```

Then delete `Placeholder.swift`:

```bash
git rm NimbleScholarCore/Sources/NimbleScholarCore/Placeholder.swift
```

- [ ] **Step 2: Fix the smoke test to match**

Replace `SmokeTests.swift` body:

```swift
import XCTest
@testable import NimbleScholarCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertEqual(NimbleScholar.coreVersion, "1.0.0")
    }
}
```

- [ ] **Step 3: Delete the dead boot files**

```bash
git rm NimbleScholar/NimbleScholarApp.swift NimbleScholar/BootCheckView.swift
```

- [ ] **Step 4: Drop the obsolete `c` source set from the bootstrap script**

In `scripts/mac_bootstrap.sh`, replace the mode branch:

```bash
if [[ "$MODE" == "c" ]]; then
  SOURCES='      - NimbleScholar/AppEnvironment.swift
      - NimbleScholar/NimbleScholarApp.swift
      - NimbleScholar/BootCheckView.swift'
else
```

with:

```bash
if [[ "$MODE" == "c" ]]; then
  echo "!! 'c' (boot-check) mode was removed; use 'full'." >&2; exit 1
else
```

- [ ] **Step 5: Run core tests**

Run: `cd NimbleScholarCore && swift test --filter SmokeTests`
Expected: PASS.

- [ ] **Step 6: VERIFY ON MAC**

`bash scripts/mac_bootstrap.sh full run` — app still builds & launches (the deleted files weren't in the `full` source set, so this just confirms nothing referenced them).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "chore: remove dead boot files + version stub; harden bootstrap"
```

### Task 2: Sanitize FTS search queries

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift:118-123`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/LibraryStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `LibraryStoreTests.swift`:

```swift
extension LibraryStoreTests {
    func testFtsQueryEscapesSpecialCharacters() {
        // Tokens are wrapped in double quotes (FTS string literals) with a prefix *,
        // so operators/punctuation can never be parsed as FTS syntax.
        XCTAssertEqual(LibraryStore.ftsQuery("attention"), "\"attention\"*")
        XCTAssertEqual(LibraryStore.ftsQuery("c++ models"), "\"c++\"* \"models\"*")
        XCTAssertEqual(LibraryStore.ftsQuery("deep: learning"), "\"deep:\"* \"learning\"*")
        XCTAssertEqual(LibraryStore.ftsQuery("  "), "")
    }

    func testSearchWithSpecialCharsDoesNotThrowOrCrash() throws {
        let store = try makeStore()
        _ = try store.create(Paper(title: "C++ and AT&T systems"))
        // Must not throw and must not return spuriously empty for a real prefix.
        XCTAssertNoThrow(try store.searchPapers(query: "c++", tag: nil))
        XCTAssertNoThrow(try store.searchPapers(query: "deep:", tag: nil))
        XCTAssertEqual(try store.searchPapers(query: "system", tag: nil).count, 1)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter testFtsQueryEscapesSpecialCharacters`
Expected: FAIL (current output is `attention*`, not `"attention"*`).

- [ ] **Step 3: Implement sanitized FTS query**

Replace `ftsQuery` in `LibraryStore.swift`:

```swift
    /// Turn a raw user query into a safe prefix FTS query. Each token becomes a
    /// double-quoted FTS string literal with a trailing `*`, so punctuation and FTS
    /// operators can never be interpreted as syntax: `c++ mod` -> `"c++"* "mod"*`.
    static func ftsQuery(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace)
            .map { token -> String in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }
            .joined(separator: " ")
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter LibraryStoreTests`
Expected: PASS (all store tests).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "fix: sanitize FTS search queries so special characters never break search"
```

### Task 3: `paper(id:)` lookup (no full-table scan)

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/LibraryStoreTests.swift`
- Modify: `NimbleScholar/Reader/ReaderViewModel.swift`

- [ ] **Step 1: Write the failing test**

Append to `LibraryStoreTests.swift`:

```swift
extension LibraryStoreTests {
    func testPaperByID() throws {
        let store = try makeStore()
        let saved = try store.create(Paper(title: "Findable"))
        XCTAssertEqual(try store.paper(id: saved.id!)?.title, "Findable")
        XCTAssertNil(try store.paper(id: 999_999))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter testPaperByID`
Expected: FAIL — `paper(id:)` not found.

- [ ] **Step 3: Implement `paper(id:)`**

Add to `LibraryStore` (near `allPapers()`):

```swift
    public func paper(id: Int64) throws -> Paper? {
        try dbQueue.read { try Paper.fetchOne($0, key: id) }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter testPaperByID`
Expected: PASS.

- [ ] **Step 5: Use it in the reader (no scan)**

In `NimbleScholar/Reader/ReaderViewModel.swift`, replace the init:

```swift
    init(paperID: Int64?) {
        let resolved = paperID.flatMap { try? AppEnvironment.shared.store.paper(id: $0) }
        self.paper = resolved ?? Paper(title: "Unknown paper")
    }
```

- [ ] **Step 6: VERIFY ON MAC**

Build & run; open a paper in the reader — opens the correct paper (now via id lookup).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "perf/fix: add paper(id:) and use it in the reader instead of scanning all papers"
```

### Task 4: Consistent annotation deletion + reconcile

**Files:**
- Modify: `NimbleScholar/Reader/AnnotationController.swift`
- Modify: `NimbleScholar/Reader/InspectorPanel.swift:58-63`
- Modify: `NimbleScholar/Reader/ReaderViewModel.swift`

> Bug: deleting an annotation from the inspector list removed only the DB index row, leaving the
> highlight in the PDF. Fix: a single helper that removes the matching `PDFAnnotation` + the index
> row, and a reconcile on load that drops orphaned index rows.

- [ ] **Step 1: Add `deleteIndexed` + `reconcile` to AnnotationController**

In `AnnotationController.swift`, add inside the struct (after `deleteAnnotation(_:on:pdfView:)`):

```swift
    /// Delete an annotation chosen from the inspector list: find the matching PDFAnnotation
    /// on its page (nearest by normalized origin), remove it from the file, and drop the row.
    func deleteIndexed(_ row: AnnotationIndex, pdfView: PDFView) {
        if let page = pdfView.document?.page(at: row.page - 1) {
            let pageRect = page.bounds(for: .mediaBox)
            if pageRect.width > 0, pageRect.height > 0 {
                let tx = CGFloat(row.x) * pageRect.width
                let ty = CGFloat(row.y) * pageRect.height
                let match = page.annotations.min { a, b in
                    hypot(a.bounds.minX - tx, a.bounds.minY - ty) < hypot(b.bounds.minX - tx, b.bounds.minY - ty)
                }
                if let match { page.removeAnnotation(match); vm.scheduleSave() }
            }
        }
        if let id = row.id { try? vm.store.deleteAnnotation(id: id) }
        vm.refreshAnnotations()
    }

    /// Drop index rows whose page no longer has any annotation near them (file is source of truth).
    func reconcile(pdfView: PDFView) {
        guard let pid = vm.paper.id, let doc = pdfView.document else { return }
        for row in (try? vm.store.annotations(forPaper: pid)) ?? [] {
            guard let page = doc.page(at: row.page - 1) else { continue }
            let pageRect = page.bounds(for: .mediaBox)
            guard pageRect.width > 0 else { continue }
            let tx = CGFloat(row.x) * pageRect.width, ty = CGFloat(row.y) * pageRect.height
            let near = page.annotations.contains { hypot($0.bounds.minX - tx, $0.bounds.minY - ty) < 8 }
            if !near, let id = row.id { try? vm.store.deleteAnnotation(id: id) }
        }
        vm.refreshAnnotations()
    }
```

- [ ] **Step 2: Make the inspector delete use it**

In `InspectorPanel.swift`, replace the `.swipeActions` block (lines ~58-63):

```swift
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        AnnotationController(vm: vm).deleteIndexed(a, pdfView: pdfView)
                    }
                }
```

- [ ] **Step 3: Reconcile once after the reader loads**

In `ReaderViewModel.swift`, the reader window calls `await vm.load()`. After the document is set,
the view needs the `pdfView` to reconcile. In `NimbleScholar/Reader/ReaderWindow.swift`, change the
`PDFKitView` `onReady` to also reconcile once:

```swift
                    PDFKitView(document: doc, displayMode: $displayMode, vm: vm) { pv in
                        self.pdfView = pv
                        AnnotationController(vm: vm).reconcile(pdfView: pv)
                    }
```

- [ ] **Step 4: VERIFY ON MAC**

Build & run. Open a PDF, add two highlights. Delete one **from the inspector list** → it disappears
from both the list **and** the page. Close & reopen the reader → the remaining highlight is still
there and the list matches the page (no ghosts).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "fix: inspector annotation delete removes it from the PDF too; reconcile index on load"
```

### Task 5: Empty states

**Files:**
- Create: `NimbleScholar/Library/EmptyLibraryView.swift`
- Modify: `NimbleScholar/Library/RowsView.swift`, `GalleryView.swift`

- [ ] **Step 1: Create a reusable empty state**

Create `NimbleScholar/Library/EmptyLibraryView.swift`:

```swift
import SwiftUI

struct EmptyLibraryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No papers", systemImage: "books.vertical")
        } description: {
            Text("Capture a paper from the toolbar, drag a PDF in, or use the browser extension.")
        }
    }
}
```

- [ ] **Step 2: Show it in Rows when empty**

In `RowsView.swift`, wrap the `ScrollView` content:

```swift
    var body: some View {
        if vm.papers.isEmpty {
            EmptyLibraryView()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    // ... existing ForEach unchanged ...
                }
                .padding(20)
            }
        }
    }
```

- [ ] **Step 3: Show it in Gallery when empty**

In `GalleryView.swift`, the same guard:

```swift
    var body: some View {
        if vm.papers.isEmpty {
            EmptyLibraryView()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    // ... existing ForEach unchanged ...
                }
                .padding(20)
            }
        }
    }
```

- [ ] **Step 4: VERIFY ON MAC**

Build & run with an empty library (or a tag filter that matches nothing) → friendly empty state in
Rows and Gallery. Three-pane already shows "Select a paper".

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: empty-library states for Rows and Gallery"
```

---

# PHASE 2 — Performance

### Task 6: Batch tag loading (kill the N+1)

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/LibraryStoreTests.swift`
- Modify: `NimbleScholar/Library/LibraryViewModel.swift`

> Today `vm.tags(for:)` runs a query *per paper* on every render/scroll. Load the whole map once
> per `reload()`.

- [ ] **Step 1: Write the failing test**

Append to `LibraryStoreTests.swift`:

```swift
extension LibraryStoreTests {
    func testAllTagsByPaper() throws {
        let store = try makeStore()
        let a = try store.create(Paper(title: "A"))
        let b = try store.create(Paper(title: "B"))
        try store.setTags(paperID: a.id!, tags: ["llm", "vision"])
        try store.setTags(paperID: b.id!, tags: ["llm"])
        let map = try store.allTagsByPaper()
        XCTAssertEqual(map[a.id!], ["llm", "vision"])
        XCTAssertEqual(map[b.id!], ["llm"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter testAllTagsByPaper`
Expected: FAIL — `allTagsByPaper` not found.

- [ ] **Step 3: Implement `allTagsByPaper()`**

Add to `LibraryStore` (near `tags(forPaper:)`):

```swift
    /// All paper→tags in a single query (avoids N+1 lookups when rendering the library).
    public func allTagsByPaper() throws -> [Int64: [String]] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT pt.paper_id AS pid, t.name AS name
                FROM paper_tags pt JOIN tags t ON t.id = pt.tag_id
                ORDER BY t.name
            """)
            var map: [Int64: [String]] = [:]
            for row in rows {
                let pid: Int64 = row["pid"]
                map[pid, default: []].append(row["name"])
            }
            return map
        }
    }
```

(`Row` is GRDB's; it's already imported in this file.)

- [ ] **Step 4: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter testAllTagsByPaper`
Expected: PASS.

- [ ] **Step 5: Cache the map in the view model**

In `NimbleScholar/Library/LibraryViewModel.swift`:

Add a published map and load it in `reload()`. Replace the `reload()` tail and the `tags(for:)` method:

```swift
    @Published var tagsByPaper: [Int64: [String]] = [:]
```

In `reload()`, after `tagCounts = ...`, add:

```swift
        tagsByPaper = (try? store.allTagsByPaper()) ?? [:]
```

Replace `tags(for:)`:

```swift
    func tags(for paper: Paper) -> [String] {
        guard let id = paper.id else { return [] }
        return tagsByPaper[id] ?? []
    }
```

- [ ] **Step 6: VERIFY ON MAC**

Build & run. With many papers, scroll Rows/Gallery — smooth, no per-card DB churn. Tags still show
correctly; adding/removing a tag still updates (it calls `reload()`).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "perf: batch-load paper tags once per reload instead of per-card queries"
```

### Task 7: Thumbnail cache disk cap + prewarm

**Files:**
- Modify: `NimbleScholar/Library/ThumbnailCache.swift`
- Modify: `NimbleScholar/Library/LibraryViewModel.swift`

- [ ] **Step 1: Add a disk-size cap (evict oldest)**

In `ThumbnailCache.swift`, add a method and call it after writing a PNG:

```swift
    private let maxBytes: UInt64 = 200 * 1024 * 1024  // 200 MB

    private func trimDiskIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        var total: UInt64 = 0
        var items: [(url: URL, date: Date, size: UInt64)] = []
        for url in files {
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = UInt64(v?.fileSize ?? 0)
            items.append((url, v?.contentModificationDate ?? .distantPast, size))
            total += size
        }
        guard total > maxBytes else { return }
        for item in items.sorted(by: { $0.date < $1.date }) {  // oldest first
            try? fm.removeItem(at: item.url)
            total -= item.size
            if total <= maxBytes { break }
        }
    }
```

In `image(for:)`, after `try? png.write(to: file)`, add `trimDiskIfNeeded()`.

- [ ] **Step 2: Add a prewarm entry point**

Add to `ThumbnailCache`:

```swift
    /// Render+cache in the background so the first scroll is instant.
    func prewarm(_ papers: [Paper]) {
        Task { for p in papers { _ = await image(for: p) } }
    }
```

- [ ] **Step 3: Prewarm after a reload**

In `LibraryViewModel.reload()`, at the very end:

```swift
        ThumbnailCache.shared.prewarm(papers)
```

- [ ] **Step 4: VERIFY ON MAC**

Build & run. Capture several papers; thumbnails appear without a visible per-card delay on
subsequent scrolls/launches. The cache dir under `~/Library/Caches/Nimble Scholar/thumbnails`
stays bounded.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "perf: thumbnail cache disk cap + background prewarm"
```

---

# PHASE 3 — Features

### Task 8: Read/Unread status

**Files:**
- Modify: `NimbleScholarCore/.../Models/Paper.swift`
- Modify: `NimbleScholarCore/.../Store/LibraryStore.swift` (migration + setRead + unread filter)
- Test: `NimbleScholarCore/Tests/.../LibraryStoreTests.swift`
- Modify app: `LibraryViewModel.swift`, `SidebarView.swift`, `ReaderViewModel.swift`, `PaperContextMenu.swift`, list/card views

- [ ] **Step 1: Add the `isRead` field to Paper**

In `Paper.swift`, add the property and column mapping. Add after `var source: String`:

```swift
    public var isRead: Bool = false
```

Add `case isRead = "read"` to **both** the `Columns` enum and the `CodingKeys` enum.

- [ ] **Step 2: Write the failing migration + setRead test**

Append to `LibraryStoreTests.swift`:

```swift
extension LibraryStoreTests {
    func testReadStatusRoundTrip() throws {
        let store = try makeStore()
        let p = try store.create(Paper(title: "P"))
        XCTAssertEqual(try store.paper(id: p.id!)?.isRead, false)
        try store.setRead(paperID: p.id!, read: true)
        XCTAssertEqual(try store.paper(id: p.id!)?.isRead, true)
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter testReadStatusRoundTrip`
Expected: FAIL — `setRead` not found (and/or column missing).

- [ ] **Step 4: Add migration + setRead**

In `LibraryStore.swift` migrator, after the `v2-fts` migration:

```swift
        m.registerMigration("v3-read") { db in
            try db.alter(table: "papers") { t in
                t.add(column: "read", .integer).notNull().defaults(to: 0)
            }
        }
```

Add the method:

```swift
    public func setRead(paperID: Int64, read: Bool) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE papers SET read = ?, updated_at = ? WHERE id = ?",
                           arguments: [read ? 1 : 0, Int64(Date().timeIntervalSince1970), paperID])
        }
    }
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter testReadStatusRoundTrip`
Expected: PASS.

- [ ] **Step 6: Unread smart filter + scope**

In `LibraryViewModel.swift`, add `.unread` to `LibraryScope`:

```swift
enum LibraryScope: Hashable {
    case all, unread, untagged, recent
    case tag(String)
}
```

In `scopeTitle`, add `case .unread: return "Unread"`. In `reload()`'s switch, add:

```swift
        case .unread: result = ((try? store.searchPapers(query: query, tag: nil)) ?? []).filter { !$0.isRead }
```

In `SidebarView.swift`, add a row in the first Section:

```swift
                Label("Unread", systemImage: "circle.fill").tag(LibraryScope.unread)
```

Add a `toggleRead` + `markRead` to `LibraryViewModel`:

```swift
    func toggleRead(_ paper: Paper) {
        if let id = paper.id { try? store.setRead(paperID: id, read: !paper.isRead); reload() }
    }
```

- [ ] **Step 7: Mark read on open, unread dot, context menu**

In `ReaderViewModel.load()`, after the document loads successfully, mark read:

```swift
            if let id = paper.id, !paper.isRead { try? store.setRead(paperID: id, read: true) }
```

In `PaperContextMenu.swift`, add before the Divider:

```swift
            Button(paper.isRead ? "Mark as Unread" : "Mark as Read") { vm.toggleRead(paper) }
```

In `ThreePaneView.swift` list row and `RowsView`/`GalleryView` cards, add an unread dot. For the
Three-pane row, change the `VStack` to an `HStack`:

```swift
                HStack(spacing: 6) {
                    Circle().fill(.blue).frame(width: 7, height: 7).opacity(paper.isRead ? 0 : 1)
                    VStack(alignment: .leading) {
                        Text(paper.title).lineLimit(2).font(.headline)
                        Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
```

- [ ] **Step 8: VERIFY ON MAC**

Build & run. New papers show an unread dot; opening one clears it; "Unread" sidebar filter works;
context menu toggles read/unread. (Migration runs cleanly on your existing library.)

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "feat: read/unread status (column + migration, dot, Unread filter, mark-on-open)"
```

### Task 9: Duplicate detection on capture

**Files:**
- Modify: `NimbleScholarCore/.../Store/LibraryStore.swift`
- Modify: `NimbleScholarCore/.../Capture/CaptureHandler.swift`
- Test: `NimbleScholarCore/Tests/.../CaptureHandlerTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `CaptureHandlerTests.swift`:

```swift
extension CaptureHandlerTests {
    func testCaptureUpdatesExistingArxivPaperInsteadOfDuplicating() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let handler = CaptureHandler(store: store) { _ in
            var m = PaperMetadata(); m.title = "First"; return m
        }
        var p = CapturePayload(); p.url = "https://arxiv.org/abs/2606.01234"; p.tags = "a"
        let first = try await handler.capture(p)
        try store.setTags(paperID: first.id!, tags: ["a", "keep-me"])

        // Capture the same arXiv id again (e.g. the pdf URL form).
        var p2 = CapturePayload(); p2.url = "https://arxiv.org/pdf/2606.01234"
        let handler2 = CaptureHandler(store: store) { _ in
            var m = PaperMetadata(); m.title = "Updated"; return m
        }
        let second = try await handler2.capture(p2)

        XCTAssertEqual(second.id, first.id)                 // same row, not a copy
        XCTAssertEqual(try store.allPapers().count, 1)
        XCTAssertEqual(second.title, "Updated")             // metadata merged
        XCTAssertEqual(Set(try store.tags(forPaper: first.id!)), ["a", "keep-me"])  // tags preserved
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter testCaptureUpdatesExistingArxivPaperInsteadOfDuplicating`
Expected: FAIL (currently creates a second row).

- [ ] **Step 3: Add a lookup to the store**

Add to `LibraryStore`:

```swift
    /// Find an existing paper by arXiv id (matched against url/doi/pdf_url) or exact URL.
    public func existingPaper(forCaptureURL url: String) throws -> Paper? {
        try dbQueue.read { db -> Paper? in
            if let id = ArxivService.extractID(from: url) {
                let bare = id.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
                if let p = try Paper.fetchOne(db, sql: """
                    SELECT * FROM papers
                    WHERE url LIKE ? OR pdf_url LIKE ? OR doi LIKE ?
                    LIMIT 1
                """, arguments: ["%\(bare)%", "%\(bare)%", "%\(bare)%"]) { return p }
            }
            return try Paper.fetchOne(db, sql: "SELECT * FROM papers WHERE url = ? LIMIT 1", arguments: [url])
        }
    }
```

- [ ] **Step 4: Use it in CaptureHandler**

In `CaptureHandler.capture(_:)`, replace `var saved = try store.create(p)` with:

```swift
        let saved: Paper
        if let existing = try store.existingPaper(forCaptureURL: payload.url) {
            p.id = existing.id
            p.createdAt = existing.createdAt
            if p.teaserURL.isEmpty { p.teaserURL = existing.teaserURL }
            if p.pipelineURL.isEmpty { p.pipelineURL = existing.pipelineURL }
            if p.pdfPath.isEmpty { p.pdfPath = existing.pdfPath }
            p.isRead = existing.isRead
            saved = try store.update(p)            // same row; tags/annotations untouched
        } else {
            saved = try store.create(p)
            if let tags = payload.tags {
                try store.setTags(paperID: saved.id!, tags: TagNormalizer.normalize(tags))
            }
        }
```

> Note: the existing `if let tags = payload.tags { ... }` block below the old `create` must be
> removed (it's now inside the `else`). The figure-enrichment block after it stays.

- [ ] **Step 5: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter CaptureHandlerTests`
Expected: PASS (both capture tests).

- [ ] **Step 6: VERIFY ON MAC**

Build & run. Capture an arXiv paper, tag it, then capture the same id again (abs or pdf URL) — the
existing paper is updated in place (no duplicate), tags preserved.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: duplicate detection — re-capturing an arXiv id updates the existing paper"
```

### Task 10: Reveal in Finder / Open in default PDF app

**Files:**
- Modify: `NimbleScholar/Library/PaperContextMenu.swift`
- Modify: `NimbleScholar/Library/LibraryViewModel.swift`

- [ ] **Step 1: Add helpers to the view model**

In `LibraryViewModel.swift`:

```swift
    func revealPDF(_ paper: Paper) {
        Task {
            if let url = await ensurePDF(for: paper) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
    func openPDFExternally(_ paper: Paper) {
        Task { if let url = await ensurePDF(for: paper) { NSWorkspace.shared.open(url) } }
    }
```

(Add `import AppKit` at the top of `LibraryViewModel.swift` if not present.)

- [ ] **Step 2: Add menu items**

In `PaperContextMenu.swift`, after the "Open in Browser" button:

```swift
            Button { vm.openPDFExternally(paper) } label: { Label("Open PDF in Default App", systemImage: "doc.richtext") }
            Button { vm.revealPDF(paper) } label: { Label("Reveal Cached PDF in Finder", systemImage: "folder") }
```

- [ ] **Step 3: VERIFY ON MAC**

Build & run. Right-click a paper → "Open PDF in Default App" opens it in Preview; "Reveal…" opens
Finder with the cached file selected (downloads first if needed).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: reveal cached PDF in Finder / open in default PDF app"
```

### Task 11: Re-fetch metadata

**Files:**
- Modify: `NimbleScholar/Library/LibraryViewModel.swift`
- Modify: `NimbleScholar/Library/PaperContextMenu.swift`

- [ ] **Step 1: Add a re-fetch action**

In `LibraryViewModel.swift`:

```swift
    func refetchMetadata(_ paper: Paper) {
        Task {
            let meta = (try? await AppEnvironment.resolveMetadata(for: paper.url)) ?? PaperMetadata()
            var p = paper
            if !meta.title.isEmpty { p.title = meta.title }
            if !meta.authors.isEmpty { p.authors = meta.authors }
            if !meta.abstract.isEmpty { p.abstract = meta.abstract }
            if !meta.year.isEmpty { p.year = meta.year }
            _ = try? store.update(p)
            if p.teaserURL.isEmpty, let id = ArxivService.extractID(from: p.url),
               let figs = try? await AppEnvironment.fetchArxivFigures(id) {
                p.teaserURL = figs.teaser ?? ""; p.pipelineURL = figs.pipeline ?? ""
                _ = try? store.update(p)
            }
            await MainActor.run { reload() }
        }
    }
```

- [ ] **Step 2: Add the menu item**

In `PaperContextMenu.swift`, after the Edit button:

```swift
            Button { vm.refetchMetadata(paper) } label: { Label("Re-fetch Metadata", systemImage: "arrow.clockwise") }
```

- [ ] **Step 3: VERIFY ON MAC**

Build & run. Right-click a paper with sparse metadata → "Re-fetch Metadata" repopulates title/
authors/abstract/figure from the source.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: re-fetch metadata action"
```

### Task 12: Export annotations to Markdown

**Files:**
- Create: `NimbleScholarCore/.../Services/MarkdownExporter.swift`
- Test: `NimbleScholarCore/Tests/.../MarkdownExporterTests.swift`
- Modify: `NimbleScholar/Reader/ReaderToolbar.swift` (or context menu) + a save panel

- [ ] **Step 1: Write the failing test**

Create `MarkdownExporterTests.swift`:

```swift
import XCTest
@testable import NimbleScholarCore

final class MarkdownExporterTests: XCTestCase {
    func testExportsTitleMetadataAndAnnotations() {
        var p = Paper(id: 1, title: "Attention Is All You Need")
        p.authors = "Vaswani"; p.year = "2017"
        let rows = [
            AnnotationIndex(id: 1, paperId: 1, page: 3, kind: "highlight", color: "#ffd966",
                            snippet: "self-attention", x: 0, y: 0, width: 0, height: 0, createdAt: 0, updatedAt: 0),
            AnnotationIndex(id: 2, paperId: 1, page: 5, kind: "note", color: "#7cc4ff",
                            snippet: "check this", x: 0, y: 0, width: 0, height: 0, createdAt: 0, updatedAt: 0),
        ]
        let md = MarkdownExporter.export(paper: p, annotations: rows)
        XCTAssertTrue(md.hasPrefix("# Attention Is All You Need"))
        XCTAssertTrue(md.contains("Vaswani"))
        XCTAssertTrue(md.contains("**p.3**"))
        XCTAssertTrue(md.contains("self-attention"))
        XCTAssertTrue(md.contains("check this"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter MarkdownExporterTests`
Expected: FAIL — `MarkdownExporter` not found.

- [ ] **Step 3: Implement the exporter**

Create `MarkdownExporter.swift`:

```swift
import Foundation

public enum MarkdownExporter {
    public static func export(paper: Paper, annotations: [AnnotationIndex]) -> String {
        var out = "# \(paper.title)\n\n"
        let meta = [paper.authors, paper.venue, paper.year].filter { !$0.isEmpty }.joined(separator: " · ")
        if !meta.isEmpty { out += "_\(meta)_\n\n" }
        if !paper.url.isEmpty { out += "<\(paper.url)>\n\n" }
        if !paper.summary.isEmpty { out += "> \(paper.summary)\n\n" }
        out += "## Annotations\n\n"
        if annotations.isEmpty {
            out += "_No annotations._\n"
        } else {
            for a in annotations.sorted(by: { $0.page < $1.page }) {
                let label = a.kind == "note" ? "📝" : "🖍"
                out += "- \(label) **p.\(a.page)** — \(a.snippet)\n"
            }
        }
        return out
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter MarkdownExporterTests`
Expected: PASS.

- [ ] **Step 5: Wire a save panel into the reader**

In `NimbleScholar/Reader/ReaderToolbar.swift`, add a button in the `ToolbarItemGroup` (after the
inspector toggle):

```swift
            Button { exportMarkdown() } label: { Image(systemName: "square.and.arrow.up") }
```

and add the method to `ReaderToolbar`:

```swift
    private func exportMarkdown() {
        let md = MarkdownExporter.export(paper: vm.paper, annotations: vm.annotations)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(vm.paper.title.prefix(40)).md"
        if panel.runModal() == .OK, let url = panel.url {
            try? md.data(using: .utf8)?.write(to: url)
        }
    }
```

- [ ] **Step 6: VERIFY ON MAC**

Build & run. Open a paper, add a highlight + note, click the export button → saves a `.md` with the
title, metadata, and your annotations.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: export a paper's highlights & notes to Markdown"
```

### Task 13: Local PDF import (drag-and-drop / Open With)

**Files:**
- Modify: `NimbleScholarCore/.../Store/LibraryStore.swift` (nothing new needed — uses create)
- Modify: `NimbleScholar/Library/LibraryViewModel.swift`
- Modify: `NimbleScholar/Library/LibraryContentView.swift`

- [ ] **Step 1: Add an import method**

In `LibraryViewModel.swift`:

```swift
    /// Import a local PDF: copy it into the cache and create a paper from its filename/metadata.
    func importPDF(at source: URL) {
        let cache = AppEnvironment.shared.downloader.cacheDir
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let dest = cache.appendingPathComponent(source.lastPathComponent)
        try? FileManager.default.copyItem(at: source, to: dest)
        var p = Paper(title: source.deletingPathExtension().lastPathComponent)
        p.pdfPath = dest.path
        p.source = "local"
        _ = try? store.create(p)
        reload()
    }
```

(`cacheDir` is already a public `let` on `PDFDownloader`.)

- [ ] **Step 2: Accept dropped PDFs on the library**

In `LibraryContentView.swift`, add to the `detail` view (after `.searchable`):

```swift
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                    Task { @MainActor in vm.importPDF(at: url) }
                }
            }
            return true
        }
```

Add `import UniformTypeIdentifiers` at the top of `LibraryContentView.swift`.

- [ ] **Step 3: VERIFY ON MAC**

Build & run. Drag a `.pdf` from Finder onto the library → a new paper appears titled from the
filename, its thumbnail rendered from page 1, and **Read** opens it.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: import a local PDF by drag-and-drop"
```

### Task 14: Library backup & restore

**Files:**
- Modify: `NimbleScholar/AppEnvironment.swift` (paths) — already has store + cache
- Create: `NimbleScholar/Library/BackupManager.swift`
- Modify: `NimbleScholar/App/NimbleScholarApp.swift` (menu commands)

- [ ] **Step 1: Create the backup manager (zip via `ditto`)**

Create `NimbleScholar/Library/BackupManager.swift`:

```swift
import AppKit
import NimbleScholarCore

enum BackupManager {
    /// The data directory: ~/Library/Application Support/Nimble Scholar
    private static var dataDir: URL {
        (try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true))
            .appendingPathComponent("Nimble Scholar", isDirectory: true)
    }

    static func backUp() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NimbleScholar-Backup.zip"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.removeItem(at: dest)
        run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", dataDir.path, dest.path])
    }

    static func restore() {
        let alert = NSAlert()
        alert.messageText = "Restore from backup?"
        alert.informativeText = "This replaces your current library with the backup. The app will quit; reopen it afterward."
        alert.addButton(withTitle: "Choose Backup…"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let open = NSOpenPanel(); open.allowedContentTypes = [.zip]
        guard open.runModal() == .OK, let zip = open.url else { return }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ns-restore-\(UUID().uuidString)")
        run(["/usr/bin/ditto", "-x", "-k", zip.path, tmp.path])
        // ditto with --keepParent nested the data under a "Nimble Scholar" folder.
        let restored = tmp.appendingPathComponent("Nimble Scholar")
        let src = FileManager.default.fileExists(atPath: restored.path) ? restored : tmp
        try? FileManager.default.removeItem(at: dataDir)
        try? FileManager.default.moveItem(at: src, to: dataDir)
        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ args: [String]) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: args[0]); p.arguments = Array(args.dropFirst())
        try? p.run(); p.waitUntilExit(); return p.terminationStatus
    }
}
```

- [ ] **Step 2: Add menu commands**

In `NimbleScholar/App/NimbleScholarApp.swift`, inside the `.commands { CommandGroup(after: .importExport) { ... } }`, add:

```swift
                Button("Back Up Library…") { BackupManager.backUp() }
                Button("Restore Library…") { BackupManager.restore() }
```

- [ ] **Step 3: VERIFY ON MAC**

Build & run. **File menu → Back Up Library…** writes a `.zip`. Add/delete a paper, then **Restore
Library…**, pick the zip — app quits; reopen → library matches the backup.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: library backup & restore (zip of DB + cached PDFs)"
```

### Task 15: Keyboard shortcuts

**Files:**
- Modify: `NimbleScholar/Library/LibraryContentView.swift`
- Modify: `NimbleScholar/Library/ThreePaneView.swift`

- [ ] **Step 1: Delete / open via keyboard on the selected paper**

In `LibraryContentView.swift`, add hidden command buttons via `.toolbar`/`.background` won't capture
keys reliably; instead add a `.onDeleteCommand` and a keyboard shortcut button overlay on the detail:

```swift
        .onDeleteCommand {
            if let id = vm.selection, let p = vm.papers.first(where: { $0.id == id }) { vm.delete(p) }
        }
        .background(
            Button("") {
                if let id = vm.selection, id != nil { openReaderForSelection() }
            }
            .keyboardShortcut(.return, modifiers: [])
            .hidden()
        )
```

Add to `LibraryContentView`:

```swift
    @Environment(\.openWindow) private var openWindow
    private func openReaderForSelection() {
        if let id = vm.selection, let pid = id { openWindow(id: "reader", value: pid) }
    }
```

> `vm.selection` is `Paper.ID?` which is `Int64??`; unwrap once to `Int64`. Adjust the
> `if let pid = id` accordingly (it flattens the optional).

- [ ] **Step 2: ⌘F focuses search**

`.searchable` already binds ⌘F on macOS to focus the search field — confirm during verification; no
code needed.

- [ ] **Step 3: VERIFY ON MAC**

Build & run. Select a paper in Three-pane: **Delete** removes it (after the existing confirm path if
any), **Return** opens the reader, **⌘F** focuses search.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: keyboard shortcuts (Delete to remove, Return to open reader)"
```

### Task 16: Multi-select bulk actions

**Files:**
- Modify: `NimbleScholar/Library/LibraryViewModel.swift`
- Modify: `NimbleScholar/Library/ThreePaneView.swift`
- Modify: `NimbleScholar/Library/LibraryContentView.swift`

> Scope: enable multi-selection in the **Three-pane list** (the natural place for it) and a bulk
> action bar. Gallery/Rows keep single-select.

- [ ] **Step 1: Add a multi-selection set + bulk ops to the view model**

In `LibraryViewModel.swift`:

```swift
    @Published var multiSelection: Set<Int64> = []

    private func selectedPapers() -> [Paper] { papers.filter { $0.id.map(multiSelection.contains) ?? false } }

    func bulkDelete() {
        for p in selectedPapers() { if let id = p.id { try? store.deletePaper(id: id) } }
        multiSelection.removeAll(); reload()
    }
    func bulkAddTag(_ tag: String) {
        for p in selectedPapers() where p.id != nil {
            let current = (try? store.tags(forPaper: p.id!)) ?? []
            try? store.setTags(paperID: p.id!, tags: current + [tag])
        }
        reload()
    }
    func bulkDownloadPDFs() async {
        for p in selectedPapers() { _ = await ensurePDF(for: p) }
    }
```

- [ ] **Step 2: Multi-select list + bulk bar in Three-pane**

In `ThreePaneView.swift`, change the `List` selection to the set and add a bulk bar. Replace the
`List(...)` with:

```swift
            VStack(spacing: 0) {
                List(vm.papers, selection: $vm.multiSelection) { paper in
                    HStack(spacing: 6) {
                        Circle().fill(.blue).frame(width: 7, height: 7).opacity(paper.isRead ? 0 : 1)
                        VStack(alignment: .leading) {
                            Text(paper.title).lineLimit(2).font(.headline)
                            Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(paper.id ?? -1)
                    .paperContextMenu(paper)
                }
                if vm.multiSelection.count > 1 {
                    HStack {
                        Text("\(vm.multiSelection.count) selected").font(.caption)
                        Spacer()
                        Button("Download") { Task { await vm.bulkDownloadPDFs() } }
                        Button("Delete", role: .destructive) { vm.bulkDelete() }
                    }
                    .padding(8).background(.bar)
                }
            }
            .frame(minWidth: 240, idealWidth: 300, maxWidth: 440)
```

> Note: `List(selection: $vm.multiSelection)` makes the list multi-selectable. To keep the detail
> pane working for single selection, drive `PaperDetailView` off `multiSelection.first` when the
> set has one element. Update the detail `Group`:

```swift
            Group {
                if vm.multiSelection.count == 1, let id = vm.multiSelection.first,
                   let paper = vm.papers.first(where: { $0.id == id }) {
                    PaperDetailView(paper: paper).environmentObject(vm)
                } else {
                    ContentUnavailableView("Select a paper", systemImage: "doc.text")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 3: VERIFY ON MAC**

Build & run, Three-pane. ⌘-click / shift-click selects multiple papers; a bulk bar appears with
Download and Delete; single selection still shows the detail pane.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: multi-select with bulk delete / download in three-pane"
```

---

# PHASE 4 — Documentation

### Task 17: Doc comments + ARCHITECTURE.md + README

**Files:**
- Modify: core + app files (doc comments)
- Create: `docs/ARCHITECTURE.md`
- Modify: `README.md`

- [ ] **Step 1: Doc-comment the public core APIs**

Add `///` doc comments to every `public` symbol in `NimbleScholarCore` that lacks one (models,
`LibraryStore` methods, services, `CaptureServer`/`CaptureHandler`). One line each: what it does +
any non-obvious behavior (e.g. "fires on the main queue", "matches arXiv id against url/doi/pdf_url").

- [ ] **Step 2: Doc-comment non-obvious UI logic**

Add `///` to: `AppEnvironment` (port auto-retry, in-memory fallback), `LibraryViewModel` (scope,
batched tag map, observation), `ReaderViewModel` (debounced save, reading position),
`AnnotationController` (file-as-source-of-truth, reconcile), `ThumbnailCache`, `BackupManager`.

- [ ] **Step 3: Write `docs/ARCHITECTURE.md`**

Create `docs/ARCHITECTURE.md` with these sections (write real content, not placeholders):
- **Overview** — core package vs app target; why the split.
- **Module map** — table: each folder/file and its one responsibility.
- **Data flow** — (1) capture: extension/sheet → CaptureServer/Handler → LibraryStore → GRDB
  observation → LibraryViewModel → views; (2) reading: ReaderWindow → PDFDownloader → PDFView →
  AnnotationController → PDF file + index; (3) thumbnails: ThumbnailCache (memory+disk).
- **Data model** — tables + the read column + annotations-index-vs-PDF-file relationship.
- **How to add a feature** — e.g. a new paper field (column + migration + Paper + UI), or a new
  bulk action.
- **Build & run** — `scripts/mac_bootstrap.sh full run`; `cd NimbleScholarCore && swift test`.

- [ ] **Step 4: Update the user README**

In `README.md`, add the new capabilities to the relevant sections: read/unread (dot + Unread
filter + mark-on-open), drag-and-drop PDF import, backup/restore (File menu), keyboard shortcuts,
multi-select, "Reveal in Finder / Open in default app", re-fetch metadata, and export annotations
to Markdown.

- [ ] **Step 5: Run the full core suite (regression)**

Run: `cd NimbleScholarCore && swift test`
Expected: ALL tests PASS.

- [ ] **Step 6: VERIFY ON MAC (final pass)**

Build & run; walk the whole app once (capture incl. dedupe, all three views + read dots + Unread
filter, drag-import a PDF, reader search/zoom/annotate/right-click-delete/export-md, backup,
shortcuts, multi-select). Confirm no regressions.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "docs: doc comments, ARCHITECTURE.md, README updates for new features"
```

---

## Self-Review (coverage vs spec)

- **Phase 1 (correctness/cleanup):** dead code → Task 1; FTS → Task 2; paper(id:)/scan → Task 3;
  annotation delete+reconcile → Task 4; empty states & edge cases → Task 5 (+ error paths verified
  throughout).
- **Phase 2 (perf):** N+1 tags → Task 6; thumbnail cap+prewarm → Task 7; paper(id:) scan removed in
  Task 3; observation coalescing confirmed in Task 6 verify.
- **Phase 3 (features):** read/unread → Task 8; duplicate detection → Task 9; reveal/open → Task 10;
  re-fetch → Task 11; markdown export → Task 12; PDF import → Task 13; backup/restore → Task 14;
  shortcuts → Task 15; multi-select → Task 16.
- **Phase 4 (docs):** Task 17.
- **Data model:** read column + migration (Task 8); paper(id:)/existingPaper/allTagsByPaper (Tasks
  3, 9, 6); annotation reconcile (Task 4).
- **Testing:** FTS (T2), paper(id:) (T3), allTagsByPaper (T6), read round-trip (T8), dedupe (T9),
  markdown (T12); UI verified per task on Mac.

**Known watch-points during execution:** (a) `vm.selection` is `Int64??` (double optional) — flatten
when reading; (b) `List(selection: $vm.multiSelection)` changes selection semantics — the detail
pane is rewired to `multiSelection` in Task 16, so Tasks before 16 still use `vm.selection`
(single). If you implement Task 16, update any remaining `vm.selection` readers (ThreePane detail)
consistently; (c) `Paper` gains `isRead` in Task 8 — the `existingPaper` merge in Task 9 references
it, so do Task 8 before Task 9.
```
