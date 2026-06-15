# Mark Papers Important (Star) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user star papers as important; starred papers float to the top of every list (All + tag/scope filters), with an "Important" sidebar filter.

**Architecture:** A new `important` column on `Paper`; `LibraryStore.setImportant` mirrors `setRead`. `LibraryViewModel` gains `toggleImportant`, an `.important` scope, and a stable `floatImportant` ordering applied as the final step in every reload/sort. A reusable `ImportanceStar` view is placed on cards, the detail pane, the context menu, and the sidebar.

**Tech Stack:** Swift/SwiftUI, GRDB (migration), XCTest.

**Environment note:** `swift test` / `xcodebuild` require macOS + Xcode (run on the user's Mac).

**Reference spec:** `docs/superpowers/specs/2026-06-15-important-star-design.md`

---

## File map

**Create:**
- `NimbleScholar/Library/ImportanceStar.swift` — reusable star toggle view
- `NimbleScholarCore/Tests/NimbleScholarCoreTests/ImportantTests.swift` — store round-trip

**Modify:**
- `NimbleScholarCore/Sources/NimbleScholarCore/Models/Paper.swift` — `isImportant`
- `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift` — `v8` migration + `setImportant`
- `NimbleScholar/Library/LibraryViewModel.swift` — toggle, scope, ordering
- `NimbleScholar/Library/SidebarView.swift` — Important entry
- `NimbleScholar/Library/PaperContextMenu.swift` — Mark/Unmark Important
- `NimbleScholar/Library/PaperDetailView.swift` — star by the title
- `NimbleScholar/Library/ThreePaneView.swift`, `GalleryView.swift`, `RowsView.swift` — card star

---

## Task 1: `Paper.isImportant` + migration + `setImportant`

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Models/Paper.swift`
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/ImportantTests.swift`

- [ ] **Step 1: Write the failing test.** Create `ImportantTests.swift`:

```swift
import XCTest
import GRDB
@testable import NimbleScholarCore

final class ImportantTests: XCTestCase {
    func testSetImportantRoundTrips() throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let saved = try store.create(Paper(title: "X"))
        XCTAssertFalse(try XCTUnwrap(store.paper(id: saved.id!)).isImportant)
        try store.setImportant(paperID: saved.id!, important: true)
        XCTAssertTrue(try XCTUnwrap(store.paper(id: saved.id!)).isImportant)
        try store.setImportant(paperID: saved.id!, important: false)
        XCTAssertFalse(try XCTUnwrap(store.paper(id: saved.id!)).isImportant)
    }
}
```

- [ ] **Step 2: Run it to verify it fails.**

Run: `cd NimbleScholarCore && swift test --filter ImportantTests`
Expected: FAIL — `value of type 'Paper' has no member 'isImportant'`.

- [ ] **Step 3: Add the property + column mappings.** In `Paper.swift`, add the property after `codeReady`:

```swift
    public var codeReady: Bool = false
    public var isImportant: Bool = false
    public var createdAt: Int64 = 0
```

Add to the `Columns` enum after the `codeReady` case:

```swift
        case codeReady = "code_ready"
        case isImportant = "important"
        case createdAt = "created_at", updatedAt = "updated_at"
```

Add the identical case to `CodingKeys`:

```swift
        case codeReady = "code_ready"
        case isImportant = "important"
        case createdAt = "created_at", updatedAt = "updated_at"
```

- [ ] **Step 4: Add the migration.** In `LibraryStore.swift`, after the `v7-existing-code-ready` block (before `return m`):

```swift
        m.registerMigration("v8-important") { db in
            try db.alter(table: "papers") { t in
                t.add(column: "important", .integer).notNull().defaults(to: 0)
            }
        }
```

- [ ] **Step 5: Add `setImportant`.** In `LibraryStore.swift`, right after the `setRead(paperID:read:)` method:

```swift
    public func setImportant(paperID: Int64, important: Bool) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE papers SET important = ?, updated_at = ? WHERE id = ?",
                           arguments: [important ? 1 : 0, Int64(Date().timeIntervalSince1970), paperID])
        }
    }
```

- [ ] **Step 6: Run the test to verify it passes.**

Run: `cd NimbleScholarCore && swift test --filter ImportantTests`
Expected: PASS.

- [ ] **Step 7: Run the full core suite.**

Run: `cd NimbleScholarCore && swift test`
Expected: all tests pass.

- [ ] **Step 8: Commit.**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Models/Paper.swift NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift NimbleScholarCore/Tests/NimbleScholarCoreTests/ImportantTests.swift
git commit -m "feat(core): Paper.important + v8 migration + setImportant"
```

---

## Task 2: View model — toggle, scope, float-to-top

**Files:**
- Modify: `NimbleScholar/Library/LibraryViewModel.swift`

- [ ] **Step 1: Add the `.important` scope case.** Change the `LibraryScope` enum (top of the file):

```swift
enum LibraryScope: Hashable {
    case all, unread, untagged, recent, important
    case tag(String)
}
```

- [ ] **Step 2: Add the scope title.** In `scopeTitle`, add the case (after `.recent`):

```swift
        case .recent: return "Recently added"
        case .important: return "Important"
        case .tag(let t): return t
```

- [ ] **Step 3: Handle the scope in `reload()` + float importance.** Replace the `reload()` body's `switch` + the final `papers =` line with:

```swift
        let result: [Paper]
        switch scope {
        case .all:           result = (try? store.searchPapers(query: query, tag: nil)) ?? []
        case .unread:        result = ((try? store.searchPapers(query: query, tag: nil)) ?? []).filter { !$0.isRead }
        case .important:     result = ((try? store.searchPapers(query: query, tag: nil)) ?? []).filter { $0.isImportant }
        case .tag(let t):    result = (try? store.searchPapers(query: query, tag: t)) ?? []
        case .untagged:      result = (try? store.untaggedPapers(query: query)) ?? []
        case .recent:        result = ((try? store.searchPapers(query: query, tag: nil)) ?? [])
                                 .sorted { $0.createdAt > $1.createdAt }
        }
        let ordered = (scope == .recent) ? Array(result.prefix(30)) : sorted(result)
        papers = floatImportant(ordered)
```

- [ ] **Step 4: Add `floatImportant` + float on re-sort.** Add the helper right after the `sorted(_:)` method:

```swift
    /// Stable: keeps important papers first while preserving the active sort within groups.
    private func floatImportant(_ list: [Paper]) -> [Paper] {
        list.sorted { $0.isImportant && !$1.isImportant }
    }
```

Change the `sort` property's `didSet` so re-sorting keeps stars on top:

```swift
    @Published var sort: SortMode = .updated {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: "librarySort")
            papers = floatImportant(sorted(papers))
        }
    }
```

- [ ] **Step 5: Add `toggleImportant`.** Next to `toggleRead(_:)`:

```swift
    func toggleImportant(_ paper: Paper) {
        if let id = paper.id { try? store.setImportant(paperID: id, important: !paper.isImportant); reload() }
    }
```

- [ ] **Step 6: Verify it builds (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds; no missing-case errors for `LibraryScope`.

- [ ] **Step 7: Commit.**

```bash
git add NimbleScholar/Library/LibraryViewModel.swift
git commit -m "feat(app): toggleImportant, Important scope, float-to-top ordering"
```

---

## Task 3: `ImportanceStar` view

**Files:**
- Create: `NimbleScholar/Library/ImportanceStar.swift`

- [ ] **Step 1: Create `ImportanceStar.swift`.**

```swift
import SwiftUI
import NimbleScholarCore

/// A star toggle for a paper's importance. Gold filled when important, subtle outline
/// otherwise. `onImage` adds a material backing so it stays legible over a thumbnail.
struct ImportanceStar: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper
    var onImage = false

    var body: some View {
        Button { vm.toggleImportant(paper) } label: {
            Image(systemName: paper.isImportant ? "star.fill" : "star")
                .foregroundStyle(paper.isImportant ? Color.yellow : Color.secondary)
                .padding(onImage ? 5 : 0)
                .background { if onImage { Circle().fill(.thinMaterial) } }
        }
        .buttonStyle(.plain)
        .help(paper.isImportant ? "Unmark important" : "Mark important")
    }
}
```

- [ ] **Step 2: Verify it builds (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds (the view is unused until Task 4, so just confirm it compiles).

- [ ] **Step 3: Commit.**

```bash
git add NimbleScholar/Library/ImportanceStar.swift
git commit -m "feat(app): ImportanceStar toggle view"
```

---

## Task 4: Place the star (cards, detail, menu, sidebar)

**Files:**
- Modify: `NimbleScholar/Library/SidebarView.swift`
- Modify: `NimbleScholar/Library/PaperContextMenu.swift`
- Modify: `NimbleScholar/Library/PaperDetailView.swift`
- Modify: `NimbleScholar/Library/ThreePaneView.swift`
- Modify: `NimbleScholar/Library/GalleryView.swift`
- Modify: `NimbleScholar/Library/RowsView.swift`

- [ ] **Step 1: Sidebar "Important" entry.** In `SidebarView.swift`, in the first `Section`, add it right after "All papers":

```swift
                Label("All papers", systemImage: "tray.full").tag(LibraryScope.all)
                Label("Important", systemImage: "star.fill").tag(LibraryScope.important)
                Label("Unread", systemImage: "circle.fill").tag(LibraryScope.unread)
```

- [ ] **Step 2: Context-menu item.** In `PaperContextMenu.swift`, after the Mark-as-Read `Button { vm.toggleRead(paper) } … }` block and before the following `Divider()`:

```swift
            Button { vm.toggleImportant(paper) } label: {
                Label(paper.isImportant ? "Unmark Important" : "Mark as Important",
                      systemImage: paper.isImportant ? "star.slash" : "star")
            }
```

- [ ] **Step 3: Detail-pane star by the title.** In `PaperDetailView.swift`, replace the title line:

```swift
                Text(paper.title).font(.title2).bold()
```

with:

```swift
                HStack(alignment: .top, spacing: 8) {
                    Text(paper.title).font(.title2).bold()
                    ImportanceStar(paper: paper).font(.title3)
                }
```

- [ ] **Step 4: Three-pane row star.** In `ThreePaneView.swift`, add the star as the leading element of the row `HStack`:

```swift
                    HStack(spacing: 6) {
                        ImportanceStar(paper: paper).font(.caption)
                        Circle().fill(.blue).frame(width: 7, height: 7).opacity(paper.isRead ? 0 : 1)
```

- [ ] **Step 5: Gallery card star.** In `GalleryView.swift`, add a top-leading overlay next to the existing status-badge overlay:

```swift
                .overlay(alignment: .topTrailing) { PaperStatusBadge(paper: paper) }
                .overlay(alignment: .topLeading) { ImportanceStar(paper: paper, onImage: true).font(.caption).padding(6) }
```

- [ ] **Step 6: Rows card star.** In `RowsView.swift`, add the same top-leading overlay on the thumbnail:

```swift
                .overlay(alignment: .topTrailing) { PaperStatusBadge(paper: paper) }
                .overlay(alignment: .topLeading) { ImportanceStar(paper: paper, onImage: true).font(.caption).padding(6) }
```

- [ ] **Step 7: Verify (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: each card shows a star (gold when important); clicking it toggles and the paper jumps to the top; the right-click menu and detail star toggle too; the sidebar shows **Important** listing only starred papers; switching tags keeps starred papers on top.

- [ ] **Step 8: Commit.**

```bash
git add NimbleScholar/Library/SidebarView.swift NimbleScholar/Library/PaperContextMenu.swift NimbleScholar/Library/PaperDetailView.swift NimbleScholar/Library/ThreePaneView.swift NimbleScholar/Library/GalleryView.swift NimbleScholar/Library/RowsView.swift
git commit -m "feat(ui): star on cards/detail/menu + Important sidebar filter"
```

---

## Self-review notes

- **Spec coverage:** `important` column + `v8` + `setImportant` (Task 1); `toggleImportant`, `.important` scope, stable `floatImportant` across all scopes + re-sort (Task 2); `ImportanceStar` (Task 3); placement on three-pane/gallery/rows cards, detail, context menu, sidebar (Task 4). Testing: store unit (Task 1) + manual (Task 4). All spec sections mapped.
- **Type/name consistency:** `Paper.isImportant`; `LibraryStore.setImportant(paperID:important:)`; `LibraryViewModel.toggleImportant(_:)` / `floatImportant(_:)` / `LibraryScope.important`; `ImportanceStar(paper:onImage:)` — consistent across tasks.
- **Ordering:** `floatImportant` is applied as the final step in `reload()` (all scopes) and in the `sort` `didSet`, so stars stay on top everywhere; Swift's stable sort preserves the active sort within the starred group and the rest.
