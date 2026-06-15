# Bind Unread Dot to the `to-read` Tag — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make "unread" mean "has the `to-read` tag" — the blue dot, the Unread filter, and Mark-as-Read all follow that tag; opening via Read/Browser (or removing the tag) clears it. Plus a safari icon on the detail Browser button.

**Architecture:** A `LibraryStore.removeTag(_:fromPaper:)` helper (bumps `updated_at` for cross-window refresh). `LibraryViewModel` gains `toReadTag` + `isUnread`/`markRead`/`toggleToRead` and a tag-based Unread scope. The reader clears the tag on open. The dot, context menu, and Browser button switch to the tag.

**Tech Stack:** Swift/SwiftUI, GRDB, XCTest.

**Environment note:** `swift test` / `xcodebuild` require macOS + Xcode (run on the user's Mac).

**Reference spec:** `docs/superpowers/specs/2026-06-15-to-read-tag-unread-design.md`

---

## File map

**Create:**
- `NimbleScholarCore/Tests/NimbleScholarCoreTests/ToReadTagTests.swift` — `removeTag` test

**Modify:**
- `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift` — `removeTag(_:fromPaper:)`
- `NimbleScholar/Library/LibraryViewModel.swift` — `toReadTag`, `isUnread`, `markRead`, `toggleToRead`, Unread scope
- `NimbleScholar/Reader/ReaderViewModel.swift` — clear tag on open
- `NimbleScholar/Library/ThreePaneView.swift` — dot from `isUnread`
- `NimbleScholar/Library/PaperContextMenu.swift` — `toggleToRead` + Open-in-Browser clears tag
- `NimbleScholar/Library/PaperDetailView.swift` — Browser button icon + clears tag

---

## Task 1: `LibraryStore.removeTag(_:fromPaper:)`

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/ToReadTagTests.swift`

- [ ] **Step 1: Write the failing test.** Create `ToReadTagTests.swift`:

```swift
import XCTest
import GRDB
@testable import NimbleScholarCore

final class ToReadTagTests: XCTestCase {
    func testRemoveTagFromPaper() throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let p = try store.create(Paper(title: "X"))
        try store.setTags(paperID: p.id!, tags: ["to-read", "vla"])
        try store.removeTag("to-read", fromPaper: p.id!)
        XCTAssertEqual(Set(try store.tags(forPaper: p.id!)), ["vla"])
        // removing a tag the paper doesn't have is a no-op
        try store.removeTag("nope", fromPaper: p.id!)
        XCTAssertEqual(Set(try store.tags(forPaper: p.id!)), ["vla"])
    }
}
```

- [ ] **Step 2: Run it to verify it fails.**

Run: `cd NimbleScholarCore && swift test --filter ToReadTagTests`
Expected: FAIL — `value of type 'LibraryStore' has no member 'removeTag'`.

- [ ] **Step 3: Implement `removeTag`.** In `LibraryStore.swift`, add right after `setImportant(paperID:important:)`:

```swift
    /// Remove a single tag from a paper (no-op if absent). Bumps `updated_at` so the
    /// library's change observation refreshes even when the tag is cleared elsewhere
    /// (e.g. from the reader window).
    public func removeTag(_ name: String, fromPaper id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                DELETE FROM paper_tags
                 WHERE paper_id = ? AND tag_id = (SELECT id FROM tags WHERE name = ?)
                """, arguments: [id, name])
            try db.execute(sql: "UPDATE papers SET updated_at = ? WHERE id = ?",
                           arguments: [Int64(Date().timeIntervalSince1970), id])
        }
    }
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `cd NimbleScholarCore && swift test --filter ToReadTagTests`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift NimbleScholarCore/Tests/NimbleScholarCoreTests/ToReadTagTests.swift
git commit -m "feat(core): LibraryStore.removeTag(_:fromPaper:)"
```

---

## Task 2: View model — tag-based unread

**Files:**
- Modify: `NimbleScholar/Library/LibraryViewModel.swift`

- [ ] **Step 1: Add the `toReadTag` constant.** In `LibraryViewModel`, add it just inside the class (e.g. above `@Published var papers`):

```swift
    /// The tag that marks a paper "unread" (drives the blue dot + Unread filter).
    static let toReadTag = "to-read"
```

- [ ] **Step 2: Switch the Unread scope to the tag.** In `reload()`, replace the `.unread` case:

```swift
        case .unread:        result = (try? store.searchPapers(query: query, tag: Self.toReadTag)) ?? []
```

- [ ] **Step 3: Add `isUnread`, `markRead`, `toggleToRead`.** Add these next to `toggleImportant(_:)`:

```swift
    /// A paper counts as "unread" while it still carries the to-read tag.
    func isUnread(_ paper: Paper) -> Bool { tags(for: paper).contains(Self.toReadTag) }

    /// Clear the to-read tag (used when a paper is opened via Read/Browser).
    func markRead(_ paper: Paper) {
        guard let id = paper.id else { return }
        try? store.removeTag(Self.toReadTag, fromPaper: id)
        reload()
    }

    /// Toggle the to-read tag (context-menu Mark as Read/Unread).
    func toggleToRead(_ paper: Paper) {
        if isUnread(paper) { removeTag(Self.toReadTag, from: paper) }
        else { addTag(Self.toReadTag, to: paper) }
    }
```

- [ ] **Step 4: Verify it builds (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds; the Unread sidebar entry now lists papers tagged `to-read`.

- [ ] **Step 5: Commit.**

```bash
git add NimbleScholar/Library/LibraryViewModel.swift
git commit -m "feat(app): to-read tag drives unread (scope + helpers)"
```

---

## Task 3: Reader clears the tag on open

**Files:**
- Modify: `NimbleScholar/Reader/ReaderViewModel.swift`

- [ ] **Step 1: Replace the read-marking line.** In `ReaderViewModel.swift`, change:

```swift
            if let id = paper.id, !paper.isRead { try? store.setRead(paperID: id, read: true) }
```

to:

```swift
            if let id = paper.id { try? store.removeTag(LibraryViewModel.toReadTag, fromPaper: id) }
```

- [ ] **Step 2: Verify it builds + clears (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: builds; opening any paper in the reader removes its `to-read` tag and the
library's blue dot disappears (via the store's observation).

- [ ] **Step 3: Commit.**

```bash
git add NimbleScholar/Reader/ReaderViewModel.swift
git commit -m "feat(reader): clear to-read tag when a paper is opened"
```

---

## Task 4: UI — dot, menu, Browser button

**Files:**
- Modify: `NimbleScholar/Library/ThreePaneView.swift`
- Modify: `NimbleScholar/Library/PaperContextMenu.swift`
- Modify: `NimbleScholar/Library/PaperDetailView.swift`

- [ ] **Step 1: Dot from `isUnread`.** In `ThreePaneView.swift`, change the dot line:

```swift
                        Circle().fill(.blue).frame(width: 7, height: 7).opacity(paper.isRead ? 0 : 1)
```

to:

```swift
                        Circle().fill(.blue).frame(width: 7, height: 7).opacity(vm.isUnread(paper) ? 1 : 0)
```

- [ ] **Step 2: Context-menu Mark-as-Read → tag toggle.** In `PaperContextMenu.swift`, replace the existing read-toggle button:

```swift
            Button {
                vm.toggleRead(paper)
            } label: {
                Label(paper.isRead ? "Mark as Unread" : "Mark as Read",
                      systemImage: paper.isRead ? "circle" : "checkmark.circle")
            }
```

with:

```swift
            Button { vm.toggleToRead(paper) } label: {
                Label(vm.isUnread(paper) ? "Mark as Read" : "Mark as Unread",
                      systemImage: vm.isUnread(paper) ? "checkmark.circle" : "circle")
            }
```

- [ ] **Step 3: Context-menu "Open in Browser" clears the tag.** In `PaperContextMenu.swift`, change the Open-in-Browser button body to clear the tag first:

```swift
            Button {
                vm.markRead(paper)
                let s = paper.pdfURL.isEmpty ? paper.url : paper.pdfURL
                if let u = URL(string: s) { NSWorkspace.shared.open(u) }
            } label: { Label("Open in Browser", systemImage: "safari") }
```

- [ ] **Step 4: Detail Browser button — icon + clear tag.** In `PaperDetailView.swift`, replace:

```swift
                    Button("Browser") {
                        if let u = URL(string: paper.pdfURL.isEmpty ? paper.url : paper.pdfURL) {
                            NSWorkspace.shared.open(u)
                        }
                    }
```

with:

```swift
                    Button {
                        vm.markRead(paper)
                        if let u = URL(string: paper.pdfURL.isEmpty ? paper.url : paper.pdfURL) {
                            NSWorkspace.shared.open(u)
                        }
                    } label: { Label("Browser", systemImage: "safari") }
```

- [ ] **Step 5: Verify (macOS).**

Run: `bash scripts/mac_bootstrap.sh full run`
Expected: a captured (to-read) paper shows the blue dot; clicking **Read** or **Browser**
clears it; right-click **Mark as Read** clears it and **Mark as Unread** restores it;
removing the `to-read` chip clears the dot; the detail **Browser** button shows a safari
icon; the **Unread** sidebar matches the dotted papers.

- [ ] **Step 6: Commit.**

```bash
git add NimbleScholar/Library/ThreePaneView.swift NimbleScholar/Library/PaperContextMenu.swift NimbleScholar/Library/PaperDetailView.swift
git commit -m "feat(ui): blue dot + menu + Browser button follow the to-read tag"
```

---

## Self-review notes

- **Spec coverage:** `removeTag(_:fromPaper:)` (Task 1); `toReadTag` + `isUnread`/`markRead`/`toggleToRead` + tag-based Unread scope (Task 2); reader clears tag on open (Task 3); dot, context menu (toggle + Open-in-Browser), detail Browser button icon + clear (Task 4). Testing: store unit (Task 1) + manual (Tasks 2–4). All spec sections mapped.
- **Type/name consistency:** `LibraryStore.removeTag(_:fromPaper:)`; `LibraryViewModel.toReadTag` / `isUnread(_:)` / `markRead(_:)` / `toggleToRead(_:)`; the reader uses `LibraryViewModel.toReadTag`. Consistent across tasks.
- **Cross-window refresh:** `removeTag` bumps `papers.updated_at` and deletes a `paper_tags` row — both are tracked by `observeChanges`, so clearing the tag from the reader refreshes the library window.
- **Intentional:** `isRead`/`setRead`/`toggleRead` remain defined but unused by the UI (no migration/API removal).
