# Reading-Experience & UX Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make switching papers while reading a single click (and keyboard-drivable), and fix the ten audited UX rough edges: delete confirmation, visible errors, keyboard gaps, view-mode inconsistencies, stable list order, inline-edit data loss, and reading-position cues.

**Architecture:** All changes live in the SwiftUI app target (`NimbleScholar/`) except one pure ordering helper added to the `NimbleScholarCore` SwiftPM package (the only place with a test target). The reader becomes driven by `LibraryViewModel.readingPaperID` alone; menu commands reach the view model through `focusedSceneValue`; errors surface through a new message channel on the existing `ActivityCenter`/`StatusBar`.

**Tech Stack:** Swift 5 / SwiftUI (macOS 14 deployment target), PDFKit, GRDB via `NimbleScholarCore`, XcodeGen project generated on the user's Mac.

**Spec:** `docs/superpowers/specs/2026-07-08-reading-experience-ux-overhaul-design.md`

## Global Constraints

- **No Swift toolchain on this server.** Never run `swift build/test` or `xcodebuild` here. Verification = careful code review for type-checker-friendly Swift; compilation and the manual checklist happen on the user's Mac via `git pull && bash scripts/install_app.sh`. Core tests run there with `cd NimbleScholarCore && swift test`.
- Keep Swift expressions type-checker friendly: no long chained closures over tuples, no key paths into tuple elements, explicit types where inference is deep (prior build failures came from exactly this).
- Never stage the repo-root `CLAUDE.md` (untracked, user-local). Always `git add` explicit paths.
- Every commit message ends with the trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- Push to `origin main` after each task's commit (the user pulls from GitHub to build).
- Deployment target is macOS 14 — macOS 15-only API is off limits.
- Follow existing code style: comment only non-obvious constraints, match surrounding idiom.

---

### Task 1: `ListOrder` helper in Core (+ tests)

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Store/ListOrder.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/ListOrderTests.swift`

**Interfaces:**
- Consumes: `Paper` (public struct in Core; `public var id: Int64?`, `public var title: String`, init `Paper(title:)`).
- Produces: `public enum ListOrder` with `public static func preservingOrder(current: [Paper], fresh: [Paper]) -> [Paper]?` — returns `fresh`'s rows arranged in `current`'s order when both contain exactly the same ids (each once); returns `nil` when the id sets differ, any row lacks an id, or ids repeat (caller must re-sort). Task 2 calls this.

- [ ] **Step 1: Write the failing test**

Create `NimbleScholarCore/Tests/NimbleScholarCoreTests/ListOrderTests.swift`:

```swift
import XCTest
@testable import NimbleScholarCore

final class ListOrderTests: XCTestCase {
    private func paper(_ id: Int64, title: String = "t") -> Paper {
        var p = Paper(title: title)
        p.id = id
        return p
    }

    func testSameIDsKeepCurrentOrderWithFreshContents() {
        let current = [paper(1, title: "a"), paper(2, title: "b"), paper(3, title: "c")]
        let fresh = [paper(3, title: "c2"), paper(1, title: "a2"), paper(2, title: "b2")]
        let merged = ListOrder.preservingOrder(current: current, fresh: fresh)
        XCTAssertEqual(merged?.map { $0.id }, [1, 2, 3])
        XCTAssertEqual(merged?.map { $0.title }, ["a2", "b2", "c2"])
    }

    func testAddedPaperForcesResort() {
        XCTAssertNil(ListOrder.preservingOrder(current: [paper(1)], fresh: [paper(1), paper(2)]))
    }

    func testRemovedPaperForcesResort() {
        XCTAssertNil(ListOrder.preservingOrder(current: [paper(1), paper(2)], fresh: [paper(2)]))
    }

    func testDifferentIDsSameCountForcesResort() {
        XCTAssertNil(ListOrder.preservingOrder(current: [paper(1)], fresh: [paper(2)]))
    }

    func testMissingIDForcesResort() {
        var noID = Paper(title: "x")
        noID.id = nil
        XCTAssertNil(ListOrder.preservingOrder(current: [noID], fresh: [noID]))
    }

    func testEmptyListsKeepOrder() {
        XCTAssertEqual(ListOrder.preservingOrder(current: [], fresh: [])?.count, 0)
    }
}
```

- [ ] **Step 2: Verify it fails (deferred to Mac)**

Cannot run here (no Swift toolchain). On the user's Mac this would fail with "cannot find 'ListOrder' in scope":
`cd NimbleScholarCore && swift test --filter ListOrderTests`

- [ ] **Step 3: Write the implementation**

Create `NimbleScholarCore/Sources/NimbleScholarCore/Store/ListOrder.swift`:

```swift
import Foundation

/// Keeps a list's on-screen order stable across background refreshes: background
/// enrichment writes (figures, PDFs, links) must not reshuffle the library under
/// the user's cursor.
public enum ListOrder {
    /// `fresh` rearranged into `current`'s order, when both hold exactly the same
    /// ids (each exactly once). Returns nil when the id sets differ, ids repeat,
    /// or any row lacks an id — the caller should fall back to a full re-sort.
    public static func preservingOrder(current: [Paper], fresh: [Paper]) -> [Paper]? {
        guard current.count == fresh.count else { return nil }
        var freshByID: [Int64: Paper] = [:]
        for p in fresh {
            guard let id = p.id else { return nil }
            if freshByID.updateValue(p, forKey: id) != nil { return nil }
        }
        var out: [Paper] = []
        out.reserveCapacity(current.count)
        for p in current {
            guard let id = p.id, let updated = freshByID[id] else { return nil }
            out.append(updated)
        }
        return out
    }
}
```

- [ ] **Step 4: Review for correctness** (duplicate-id guard, count guard first, no force unwraps).

- [ ] **Step 5: Commit and push**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Store/ListOrder.swift NimbleScholarCore/Tests/NimbleScholarCoreTests/ListOrderTests.swift
git commit -m "feat(core): ListOrder.preservingOrder — stable list order across background refreshes

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
```

---

### Task 2: Stable-order reloads + uncapped "Recently added" scope

**Files:**
- Modify: `NimbleScholar/Library/LibraryViewModel.swift` (reload plumbing: ~lines 34-41, 84-113; mutation call sites: 151-243, 268-288, 501-507)

**Interfaces:**
- Consumes: `ListOrder.preservingOrder(current:fresh:)` from Task 1.
- Produces: `func reload(resort: Bool = false)` — `resort: false` (the default, used by DB observation and `.task`) preserves the current on-screen order when the id set is unchanged; `resort: true` (user actions) fully re-sorts. Later tasks call `reload(resort: true)` from new user-action paths.

- [ ] **Step 1: Replace the reload coalescer with a resort-aware one**

In `LibraryViewModel.swift`, replace the `reload()` function (currently lines 84-91) with:

```swift
    /// Coalesce reloads within one frame: a mutation's explicit reload and the DB observation's
    /// reload (which fires just after the same write) collapse into a single DB fetch instead of two.
    /// `resort: true` marks a user action — the list fully re-sorts. Background reloads
    /// (`resort: false`) keep the current order when the same papers are still visible, so
    /// enrichment writes never reshuffle the list mid-scroll. The flag ORs across coalesced
    /// calls so a user resort can't be swallowed by a trailing observation reload.
    func reload(resort: Bool = false) {
        pendingResort = pendingResort || resort
        reloadCoalesce?.cancel()
        reloadCoalesce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000)
            if Task.isCancelled { return }
            self?.performReload()
        }
    }

    private var pendingResort = false
```

(Note: `private var pendingResort = false` must sit with the other stored properties, e.g. next to `reloadCoalesce` at line ~53 — property declarations can't follow a function inside the same scope in this codebase's style; place it beside `private var reloadCoalesce`.)

- [ ] **Step 2: Use the merge in `performReload` and drop the 30-item cap**

Replace the body section of `performReload()` (currently lines 93-105) with:

```swift
    private func performReload() {
        let resort = pendingResort
        pendingResort = false
        let result: [Paper]
        switch scope {
        case .all:           result = (try? store.searchPapers(query: query, tag: nil)) ?? []
        case .unread:        result = (try? store.searchPapers(query: query, tag: Self.toReadTag)) ?? []
        case .important:     result = ((try? store.searchPapers(query: query, tag: nil)) ?? []).filter { $0.isImportant }
        case .tag(let t):    result = (try? store.searchPapers(query: query, tag: t)) ?? []
        case .untagged:      result = (try? store.untaggedPapers(query: query)) ?? []
        case .recent:        result = ((try? store.searchPapers(query: query, tag: nil)) ?? [])
                                 .sorted { $0.createdAt > $1.createdAt }
        }
        // Background refreshes of the same papers keep the on-screen order; anything
        // else (user action, papers added/removed) goes through the full sort.
        if !resort, let merged = ListOrder.preservingOrder(current: papers, fresh: result) {
            papers = merged
        } else {
            papers = floatImportant(sorted(result))
        }
```

The rest of `performReload` (selection pruning, `tagCounts`, `tagsByPaper`, prewarm, `autoCompleteIncomplete()`) stays exactly as is. The old line `let ordered = (scope == .recent) ? Array(result.prefix(30)) : sorted(result)` and `papers = floatImportant(ordered)` are gone — the recent scope is now uncapped (`sorted(_:)` already returns recent lists unchanged).

- [ ] **Step 3: Mark user actions as resorts**

Change these existing call sites from `reload()` to `reload(resort: true)`:
- `scope` didSet (line 35) — Task 3 rewrites this didSet anyway; use `reload(resort: true)` there.
- `scheduleSearchReload()`'s `self?.reload()` (line 61)
- `addTag` (155), `removeTag` (160), `renameTag`'s `else { reload() }` (167), `deleteTag`'s `else { reload() }` (171)
- `saveSummary` (177), `delete` (180), `toggleRead` (183), `toggleImportant` (186)
- `markRead` (208), `refetchMetadata`'s `await MainActor.run { reload() }` (239), `save` (244)
- `importPDF(at:)` (270), `attachPDF` (287), `bulkDelete` (503)

Leave `reload()` (default, order-preserving) in: `init`'s observation callback, `refetchAllFigures`, `regenerateFiguresFromPDF` (this one re-derives thumbnails, order doesn't change), and `LibraryContentView`'s `.task { vm.reload() }` (first load starts from `papers == []`, so the id sets differ and it re-sorts anyway).

- [ ] **Step 4: Review** — confirm every changed call site compiles by signature (`reload(resort: true)`), no leftover `prefix(30)`, `pendingResort` declared once next to `reloadCoalesce`.

- [ ] **Step 5: Commit and push**

```bash
git add NimbleScholar/Library/LibraryViewModel.swift
git commit -m "feat(library): stable list order during background refreshes; uncap Recently added

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
```

---

### Task 3: Reading-flow state — switch on click, tags keep reading, remembered list

**Files:**
- Modify: `NimbleScholar/Library/LibraryViewModel.swift` (lines ~35-48, 189-199; add `openSelectedInReader`, `stepPaper`)

**Interfaces:**
- Consumes: nothing new.
- Produces (used by Tasks 4 & 7):
  - `multiSelection` didSet now switches `readingPaperID` to the newly selected paper while reading.
  - `scope` didSet no longer exits the reader; while reading it sets `showPaperList = true`.
  - `showPaperList` persists to UserDefaults key `"showPaperList"`.
  - `func openSelectedInReader()` — opens the reader on the current single selection.
  - `func stepPaper(_ delta: Int)` — while reading, advances `readingPaperID` through `papers`, wrapping.

- [ ] **Step 1: Rewrite the state properties**

Replace the current `scope` property (line 35):

```swift
    @Published var scope: LibraryScope = .all {
        didSet {
            // Reading survives a scope change: the rail re-filters the side list (revealed
            // so the user sees the tag's papers) while the current PDF stays open.
            if readingPaperID != nil { showPaperList = true }
            reload(resort: true)
        }
    }
```

Replace `multiSelection` (line 42):

```swift
    @Published var multiSelection: Set<Int64> = [] {   // the one selection (3-pane multi + current)
        didSet {
            // While reading, single-clicking another paper switches the reader to it.
            guard readingPaperID != nil, multiSelection.count == 1,
                  let id = multiSelection.first, id != readingPaperID else { return }
            readingPaperID = id
        }
    }
```

Replace `showPaperList` (line 48):

```swift
    /// While reading, whether the left paper list is revealed (remembered across sessions).
    @Published var showPaperList: Bool = UserDefaults.standard.bool(forKey: "showPaperList") {
        didSet { UserDefaults.standard.set(showPaperList, forKey: "showPaperList") }
    }
```

- [ ] **Step 2: Stop force-folding the list in `openReader`, add the two new methods**

Replace `openReader`/`closeReader` (lines 191-199) with:

```swift
    func openReader(_ paper: Paper) {
        guard let id = paper.id else { return }
        multiSelection = [id]          // selects immediately (cheap)
        // Defer the reader swap one runloop so the click returns instantly; the heavy
        // EmbeddedReader build then runs on a fresh frame instead of blocking the tap.
        DispatchQueue.main.async { self.readingPaperID = id }
    }
    func closeReader() { readingPaperID = nil }

    /// Open the reader on the currently selected paper (menu command / ⌘O).
    func openSelectedInReader() {
        if let id = currentPaperID, let paper = papers.first(where: { $0.id == id }) {
            openReader(paper)
        }
    }

    /// While reading, jump to the next (+1) / previous (-1) paper in the visible list, wrapping.
    func stepPaper(_ delta: Int) {
        guard readingPaperID != nil, !papers.isEmpty else { return }
        let idx = papers.firstIndex(where: { $0.id == readingPaperID }) ?? 0
        let n = papers.count
        let next = ((idx + delta) % n + n) % n
        openReader(papers[next])
    }
```

(The only body change to `openReader` is deleting `showPaperList = false`.)

- [ ] **Step 3: Review** — check the `multiSelection` didSet can't loop (`openReader` sets selection first while `readingPaperID` is still the old value → didSet fires once and sets it directly; the deferred async assignment then writes the same value, which is harmless). Check `performReload`'s selection pruning (`multiSelection = multiSelection.intersection(visible)`) only ever shrinks the set, so it can't spuriously switch papers.

- [ ] **Step 4: Commit and push**

```bash
git add NimbleScholar/Library/LibraryViewModel.swift
git commit -m "feat(reader): tag clicks keep reading; selection switches the open paper; remembered list state

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
```

---

### Task 4: ThreePaneView — reader driven by readingPaperID, double-click to read

**Files:**
- Modify: `NimbleScholar/Library/ThreePaneView.swift` (detail Group lines 56-71; list row lines 22-38)

**Interfaces:**
- Consumes: `vm.readingPaperID`, `vm.openReader(_:)`, `EmbeddedReader(paperID:onClose:)`.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Key the detail pane on `readingPaperID`**

Replace the detail `Group` (lines 56-68) with:

```swift
            Group {
                if let rid = vm.readingPaperID {
                    // Keyed by paper id so switching papers rebuilds the ReaderViewModel —
                    // a plain @StateObject would keep showing the previous document.
                    EmbeddedReader(paperID: rid) { vm.closeReader() }
                        .id(rid)
                        .transition(.opacity)
                } else if vm.multiSelection.count == 1, let id = vm.multiSelection.first,
                          let paper = vm.papers.first(where: { $0.id == id }) {
                    PaperDetailView(paper: paper).environmentObject(vm)
                } else {
                    ContentUnavailableView("Select a paper", systemImage: "doc.text")
                }
            }
```

(The `.animation(.easeOut(duration: 0.15), value: vm.readingPaperID)` and `.frame` modifiers after the Group stay.)

- [ ] **Step 2: Double-click a list row opens the reader**

On the row's `HStack` (after `.paperContextMenu(paper)`, line 34), add a simultaneous gesture — `simultaneousGesture` does not steal the List's native single-click selection (the existing comment about plain `.onTapGesture` still holds; update it):

```swift
                    .tag(paper.id ?? -1)
                    .paperContextMenu(paper)
                    // No plain tap gesture here on purpose: it would suppress the List's native
                    // single-click selection. A *simultaneous* double-click gesture coexists with
                    // it — single click selects (and switches the reader while reading, via the
                    // selection didSet); double click opens the reader from browse mode.
                    .simultaneousGesture(TapGesture(count: 2).onEnded { vm.openReader(paper) })
```

- [ ] **Step 3: Review** — the reader now shows even when `multiSelection` is empty or >1 (deliberate: multi-selecting for a bulk action while reading keeps the PDF open). Confirm `EmbeddedReader`'s existing `.onDisappear { vm.flushSave() }` covers annotation flush when `.id` swaps the view.

- [ ] **Step 4: Commit and push**

```bash
git add NimbleScholar/Library/ThreePaneView.swift
git commit -m "feat(reader): single-click switches the open paper; double-click reads from three-pane

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
```

---

### Task 5: Delete confirmation everywhere

**Files:**
- Modify: `NimbleScholar/Library/LibraryViewModel.swift` (replace `delete`/`bulkDelete`, add pending-delete state)
- Modify: `NimbleScholar/Library/LibraryContentView.swift` (dialog + `.onDeleteCommand`)
- Modify: `NimbleScholar/Library/PaperContextMenu.swift:44`
- Modify: `NimbleScholar/Library/PaperDetailView.swift:35`
- Modify: `NimbleScholar/Library/PaperEditSheet.swift:45`
- Modify: `NimbleScholar/Library/ThreePaneView.swift` (bulk bar Delete button)

**Interfaces:**
- Produces (used by Task 8's BulkActionBar):
  - `@Published var pendingDelete: [Paper]`
  - `func requestDelete(_ papersToDelete: [Paper])`, `func requestDeleteSelection()`
  - `func confirmPendingDelete()`, `func cancelPendingDelete()`
- Removes: public `delete(_:)` and `bulkDelete()` (all call sites updated in this task).

- [ ] **Step 1: Pending-delete state in the view model**

In `LibraryViewModel.swift`, replace `func delete(_ paper: Paper)` (lines 179-181) with:

```swift
    // MARK: - Deletion (always confirmed)

    /// Papers awaiting the user's confirmation; non-empty drives the confirmation dialog.
    @Published var pendingDelete: [Paper] = []

    func requestDelete(_ papersToDelete: [Paper]) {
        pendingDelete = papersToDelete.filter { $0.id != nil }
    }
    func requestDeleteSelection() { requestDelete(selectedPapers()) }

    func confirmPendingDelete() {
        let ids = pendingDelete.compactMap { $0.id }
        for id in ids { try? store.deletePaper(id: id) }
        if let rid = readingPaperID, ids.contains(rid) { readingPaperID = nil }
        multiSelection.subtract(ids)
        pendingDelete = []
        reload(resort: true)
    }
    func cancelPendingDelete() { pendingDelete = [] }
```

and delete `func bulkDelete()` (lines 501-504). Note `selectedPapers()` (line 499) stays private — `requestDeleteSelection()` wraps it.

- [ ] **Step 2: One dialog at the window level**

In `LibraryContentView.swift`, on the outer `VStack(spacing: 0)` in `body` (after the closing brace at line 103's `}`, i.e. attached to the VStack), add:

```swift
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: Binding(
                get: { !vm.pendingDelete.isEmpty },
                set: { if !$0 { vm.cancelPendingDelete() } }
            )
        ) {
            Button("Delete", role: .destructive) { vm.confirmPendingDelete() }
            Button("Cancel", role: .cancel) { vm.cancelPendingDelete() }
        } message: {
            Text("This cannot be undone.")
        }
```

and add the computed title to `LibraryContentView`:

```swift
    private var deleteDialogTitle: String {
        vm.pendingDelete.count == 1
            ? "Delete “\(vm.pendingDelete[0].title)”?"
            : "Delete \(vm.pendingDelete.count) papers?"
    }
```

- [ ] **Step 3: Route every delete path through the request**

- `LibraryContentView.swift:175`: `.onDeleteCommand { vm.bulkDelete() }` → `.onDeleteCommand { vm.requestDeleteSelection() }`
- `PaperContextMenu.swift:44`: `Button(role: .destructive) { vm.delete(paper) }` → `Button(role: .destructive) { vm.requestDelete([paper]) }`
- `PaperDetailView.swift:35`: `Button("Delete", role: .destructive) { vm.delete(paper) }` → `Button("Delete", role: .destructive) { vm.requestDelete([paper]) }`
- `PaperEditSheet.swift:45`: `Button("Delete", role: .destructive) { vm.delete(paper); dismiss() }` → `Button("Delete", role: .destructive) { vm.requestDelete([paper]); dismiss() }` (the dialog lives on the window, so it appears after the sheet closes)
- `ThreePaneView.swift:44`: `Button("Delete", role: .destructive) { vm.bulkDelete() }` → `Button("Delete", role: .destructive) { vm.requestDeleteSelection() }`

- [ ] **Step 4: Review** — grep for remaining `vm.delete(` / `vm.bulkDelete(` (must be none); confirm `confirmPendingDelete` clears `readingPaperID` *before* `multiSelection.subtract` so the selection didSet can't re-open a deleted paper.

- [ ] **Step 5: Commit and push**

```bash
git add NimbleScholar/Library/LibraryViewModel.swift NimbleScholar/Library/LibraryContentView.swift NimbleScholar/Library/PaperContextMenu.swift NimbleScholar/Library/PaperDetailView.swift NimbleScholar/Library/PaperEditSheet.swift NimbleScholar/Library/ThreePaneView.swift
git commit -m "feat(library): every delete path confirms first — no more silent destruction

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
```

---

### Task 6: Visible persistence errors + termination-safe annotation flush

**Files:**
- Modify: `NimbleScholar/Library/ActivityCenter.swift` (error channel + StatusBar row)
- Modify: `NimbleScholar/Reader/ReaderViewModel.swift` (write check, willTerminate flush)
- Modify: `NimbleScholar/Library/LibraryContentView.swift` (`exportBibTeX`)
- Modify: `NimbleScholar/Library/LibraryViewModel.swift` (`saveSummary`, `addTag`, `removeTag`, `save`, `attachPDF`)

**Interfaces:**
- Produces: `ActivityCenter.reportError(_ message: String)` and `clearError()` — MainActor; shows the message in the StatusBar (auto-clears after 8 s or on the ✕ button). Any later code may call it.

- [ ] **Step 1: Error channel on ActivityCenter**

In `ActivityCenter.swift`, after the `itemLabels` property (line 15), add:

```swift
    /// One-line failure message shown in the status bar (auto-clears; ✕ dismisses).
    @Published private(set) var errorMessage: String?
    private var errorClear: Task<Void, Never>?

    func reportError(_ message: String) {
        errorMessage = message
        errorClear?.cancel()
        errorClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled { self?.errorMessage = nil }
        }
    }
    func clearError() {
        errorClear?.cancel()
        errorMessage = nil
    }
```

- [ ] **Step 2: Show it in the StatusBar**

In `StatusBar.body`, make the error the first branch of the existing `if` chain (before `if activity.batchTotal > 0`):

```swift
            if let err = activity.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(err).lineLimit(1).foregroundStyle(.primary)
                Button { activity.clearError() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Dismiss")
            } else if activity.batchTotal > 0 {
```

- [ ] **Step 3: Reader — check the PDF write, flush on quit**

In `ReaderViewModel.swift`:
- Add `import AppKit` under the existing imports.
- Add a stored property next to `saveWork` (line 64): `private var terminationObserver: NSObjectProtocol?`
- At the end of `init(paperID:)`, register the observer (an unexpected quit during the 0.6 s debounce must not lose the last annotation):

```swift
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushSave() }
        }
```

- Add a `deinit`:

```swift
    deinit {
        if let o = terminationObserver { NotificationCenter.default.removeObserver(o) }
    }
```

- Replace `writeNow()` (lines 78-81):

```swift
    private func writeNow() {
        guard let url = localURL, let doc = document else { return }
        if !doc.write(to: url) {
            ActivityCenter.shared.reportError("Couldn't save annotations for “\(paper.title)” — the PDF may be locked or the disk full.")
        }
    }
```

- [ ] **Step 4: BibTeX export surfaces failures**

In `LibraryContentView.swift`, replace the body of `exportBibTeX()` (lines 6-13):

```swift
@MainActor func exportBibTeX() {
    let papers = (try? AppEnvironment.shared.store.searchPapers(query: nil, tag: nil)) ?? []
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "papers.bib"
    if panel.runModal() == .OK, let url = panel.url {
        do {
            guard let data = BibTeXExporter.export(papers).data(using: .utf8) else { return }
            try data.write(to: url)
        } catch {
            ActivityCenter.shared.reportError("BibTeX export failed — \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 5: User-data saves in the view model stop swallowing errors**

In `LibraryViewModel.swift`, convert these five (only these — background best-effort scrapes stay silent):

```swift
    func saveSummary(_ text: String, for paper: Paper) {
        var p = paper; p.summary = text
        do { _ = try store.update(p) }
        catch { ActivityCenter.shared.reportError("Couldn't save summary — \(error.localizedDescription)") }
        reload(resort: true)
    }
```

```swift
    func addTag(_ tag: String, to paper: Paper) {
        guard let id = paper.id else { return }
        let current = (try? store.tags(forPaper: id)) ?? []
        do { try store.setTags(paperID: id, tags: current + [tag]) }
        catch { ActivityCenter.shared.reportError("Couldn't add tag — \(error.localizedDescription)") }
        reload(resort: true)
    }
    func removeTag(_ tag: String, from paper: Paper) {
        guard let id = paper.id else { return }
        let current = ((try? store.tags(forPaper: id)) ?? []).filter { $0 != tag }
        do { try store.setTags(paperID: id, tags: current) }
        catch { ActivityCenter.shared.reportError("Couldn't remove tag — \(error.localizedDescription)") }
        reload(resort: true)
    }
```

```swift
    func save(_ paper: Paper) {
        do { _ = try (paper.id == nil ? store.create(paper) : store.update(paper)) }
        catch { ActivityCenter.shared.reportError("Couldn't save paper — \(error.localizedDescription)") }
        reload(resort: true)
    }
```

In `attachPDF(at:to:)`, replace `_ = try? store.update(p)` with:

```swift
        do { _ = try store.update(p) }
        catch { ActivityCenter.shared.reportError("Couldn't attach PDF — \(error.localizedDescription)") }
```

- [ ] **Step 6: Review** — `deinit` only touches the observer token (safe off-MainActor); `store.setTags`/`update`/`create` are throwing (they're called with `try?` today, so signatures allow `try`).

- [ ] **Step 7: Commit and push**

```bash
git add NimbleScholar/Library/ActivityCenter.swift NimbleScholar/Reader/ReaderViewModel.swift NimbleScholar/Library/LibraryContentView.swift NimbleScholar/Library/LibraryViewModel.swift
git commit -m "feat(app): surface save failures in the status bar; flush annotations on quit

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
```

---

### Task 7: Menu commands & keyboard shortcuts

**Files:**
- Create: `NimbleScholar/App/PaperCommands.swift`
- Modify: `NimbleScholar/App/NimbleScholarApp.swift` (register commands)
- Modify: `NimbleScholar/Library/LibraryContentView.swift` (focusedSceneValue; remove hidden ⌘O button + `openSelectedReader()`)
- Modify: `NimbleScholar/Reader/EmbeddedReader.swift` (⌘W close)
- Modify: `NimbleScholar/Reader/ReaderToolbar.swift` (zoom + inspector shortcuts)

**Interfaces:**
- Consumes: `vm.openSelectedInReader()`, `vm.stepPaper(_:)` from Task 3.
- Produces: `FocusedValues.libraryVM` (a `LibraryViewModel?` focused scene value) and the `PaperCommands` menu. Shortcuts: ⌘O read, ⌥⌘↓/⌥⌘↑ next/previous paper, ⌥⌘N night reading, ⌘W close reader (view-level, so the menu's Close Window still works when not reading), ⌘= / ⌘− / ⌘0 zoom, ⌥⌘I inspector.

- [ ] **Step 1: Create the commands file**

`NimbleScholar/App/PaperCommands.swift`:

```swift
import SwiftUI

/// Lets menu commands reach the library window's view model.
struct LibraryVMFocusedKey: FocusedValueKey {
    typealias Value = LibraryViewModel
}
extension FocusedValues {
    var libraryVM: LibraryViewModel? {
        get { self[LibraryVMFocusedKey.self] }
        set { self[LibraryVMFocusedKey.self] = newValue }
    }
}

/// The Paper menu: open the reader, step through papers while reading, night mode.
/// Actions no-op (rather than disable) when no library window is focused — menu
/// enablement can't observe @Published state reliably.
struct PaperCommands: Commands {
    @FocusedValue(\.libraryVM) private var vm
    @AppStorage("nightReading") private var nightReading = false

    var body: some Commands {
        CommandMenu("Paper") {
            Button("Read Paper") { vm?.openSelectedInReader() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Next Paper") { vm?.stepPaper(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Previous Paper") { vm?.stepPaper(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Divider()
            Toggle("Night Reading", isOn: $nightReading)
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
    }
}
```

- [ ] **Step 2: Register the menu**

In `NimbleScholarApp.swift`, inside `.commands { … }` after the existing `CommandGroup(after: .importExport)` block, add:

```swift
            PaperCommands()
```

- [ ] **Step 3: Publish the view model to the menu; drop the hidden ⌘O button**

In `LibraryContentView.swift`:
- On the outer `VStack(spacing: 0)` in `body` (alongside the Task 5 dialog modifier), add: `.focusedSceneValue(\.libraryVM, vm)`
- Delete the `private func openSelectedReader()` (lines 76-80) and the hidden-button `.background` block (lines 176-180):

```swift
        .background(
            Button("") { openSelectedReader() }
                .keyboardShortcut("o", modifiers: [.command])
                .hidden()
        )
```

- [ ] **Step 4: ⌘W closes the reader**

In `EmbeddedReader.swift`, after `.navigationTitle(vm.paper.title)` (line 80), add — a view-level shortcut wins over the menu's Close Window while the reader is on screen, and File ▸ Close behaves normally otherwise:

```swift
            .background(
                Button("") { vm.flushSave(); onClose() }
                    .keyboardShortcut("w", modifiers: .command)
                    .hidden()
            )
```

- [ ] **Step 5: Zoom + inspector shortcuts on the toolbar**

In `ReaderToolbar.swift`, replace the four buttons after the find button:

```swift
            Button { pdfView?.zoomOut(nil) } label: { Image(systemName: "minus.magnifyingglass") }
                .keyboardShortcut("-", modifiers: .command)
                .help("Zoom out (⌘−)")
            Button { pdfView?.zoomIn(nil) } label: { Image(systemName: "plus.magnifyingglass") }
                .keyboardShortcut("=", modifiers: .command)
                .help("Zoom in (⌘=)")
            Button("Fit") {
                if let pv = pdfView { pv.autoScales = true; pv.scaleFactor = pv.scaleFactorForSizeToFit }
            }
            .keyboardShortcut("0", modifiers: .command)
            .help("Fit to window (⌘0)")
            Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help("Annotations & chat (⌥⌘I)")
```

- [ ] **Step 6: Review** — no duplicate key equivalents (⌘O now lives only in the menu; ⌘W only in the reader view; ⇧⌘I Import vs ⌥⌘I inspector don't clash). `Toggle` inside `CommandMenu` with `@AppStorage` is valid macOS 14 SwiftUI.

- [ ] **Step 7: Commit and push**

```bash
git add NimbleScholar/App/PaperCommands.swift NimbleScholar/App/NimbleScholarApp.swift NimbleScholar/Library/LibraryContentView.swift NimbleScholar/Reader/EmbeddedReader.swift NimbleScholar/Reader/ReaderToolbar.swift
git commit -m "feat(app): Paper menu (read, next/prev, night mode) + reader keyboard shortcuts

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
```

---

### Task 8: Multi-select + bulk bar in all view modes; unread dots on cards

**Files:**
- Modify: `NimbleScholar/Library/LibraryViewModel.swift` (`select(_:)`)
- Modify: `NimbleScholar/Library/ThreePaneView.swift` (extract `BulkActionBar`)
- Modify: `NimbleScholar/Library/GalleryView.swift` (bulk bar, unread dot)
- Modify: `NimbleScholar/Library/RowsView.swift` (bulk bar, unread dot)

**Interfaces:**
- Consumes: `vm.requestDeleteSelection()` (Task 5), `vm.isUnread(_:)`.
- Produces: `struct BulkActionBar: View` (in ThreePaneView.swift) shown by all three modes; `select(_:)` honoring ⌘ (toggle) and ⇧ (additive).

- [ ] **Step 1: Modifier-aware selection**

In `LibraryViewModel.swift`, replace `func select(_ paper: Paper)` (line 189):

```swift
    /// Click-select honoring the standard modifiers: ⌘ toggles membership, ⇧ adds,
    /// plain click replaces. (Gallery/rows cards route their taps here.)
    func select(_ paper: Paper) {
        guard let id = paper.id else { return }
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            if multiSelection.contains(id) { multiSelection.remove(id) }
            else { multiSelection.insert(id) }
        } else if mods.contains(.shift) {
            multiSelection.insert(id)
        } else {
            multiSelection = [id]
        }
    }
```

- [ ] **Step 2: Extract the bulk bar**

In `ThreePaneView.swift`, replace the inline bulk `if` block (lines 39-48) with `BulkActionBar()` and add at file bottom:

```swift
/// Selection-count bar with bulk actions; renders nothing unless 2+ papers are selected.
/// Shared by the three-pane list, gallery, and rows.
struct BulkActionBar: View {
    @EnvironmentObject var vm: LibraryViewModel

    var body: some View {
        if vm.multiSelection.count > 1 {
            HStack {
                Text("\(vm.multiSelection.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Download") { Task { await vm.bulkDownloadPDFs() } }
                Button("Delete", role: .destructive) { vm.requestDeleteSelection() }
            }
            .padding(8)
            .background(.bar)
        }
    }
}
```

(Task 5 already switched this Delete to `requestDeleteSelection()`; keep that.)

- [ ] **Step 3: Show it in gallery and rows**

`GalleryView.body` — wrap the ScrollView (a plain VStack, not `safeAreaInset`, which has misbehaved in this window before):

```swift
        if vm.papers.isEmpty {
            EmptyLibraryView()
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                        ForEach(vm.papers) { paper in
                            GalleryCard(paper: paper,
                                        selected: vm.multiSelection.contains(paper.id ?? -1),
                                        unread: vm.isUnread(paper))
                                .equatable()
                                .environmentObject(vm)
                        }
                    }
                    .padding(20)
                }
                BulkActionBar()
            }
        }
```

`RowsView.content` similarly:

```swift
    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.papers) { paper in
                        RowCard(paper: paper,
                                selected: vm.multiSelection.contains(paper.id ?? -1),
                                unread: vm.isUnread(paper),
                                tags: vm.tags(for: paper))
                            .equatable()
                            .environmentObject(vm)
                    }
                }
                .padding(20)
            }
            BulkActionBar()
        }
    }
```

- [ ] **Step 4: Unread dot on both cards**

`GalleryCard`: add `let unread: Bool` after `let selected: Bool`, include it in equality (`l.unread == r.unread`), and put the dot on the title line:

```swift
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if unread { Circle().fill(.blue).frame(width: 7, height: 7) }
                Text(paper.title).font(.subheadline).bold().lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
```

`RowCard`: add `let unread: Bool` after `let selected: Bool`, include in `==`, and:

```swift
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if unread { Circle().fill(.blue).frame(width: 7, height: 7) }
                    Text(paper.title).font(.headline)
                }
```

- [ ] **Step 5: Review** — both cards' `static func ==` updated (a stale Equatable is an invisible refresh bug); `NSEvent` needs AppKit — `LibraryViewModel.swift` already `import AppKit`.

- [ ] **Step 6: Commit and push**

```bash
git add NimbleScholar/Library/LibraryViewModel.swift NimbleScholar/Library/ThreePaneView.swift NimbleScholar/Library/GalleryView.swift NimbleScholar/Library/RowsView.swift
git commit -m "feat(library): multi-select + bulk bar in every view mode; unread dots on cards

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
```

---

### Task 9: Inline edits commit on focus loss; edit-sheet dirty check

**Files:**
- Modify: `NimbleScholar/Library/RowsView.swift` (`InlineSummaryField`)
- Modify: `NimbleScholar/Library/PaperDetailView.swift` (`DetailSummaryField`)
- Modify: `NimbleScholar/Library/TagInputField.swift`
- Modify: `NimbleScholar/Library/PaperEditSheet.swift`

**Interfaces:** nothing produced for later tasks.

- [ ] **Step 1: Summary fields save on blur (only when changed)**

`InlineSummaryField` (RowsView.swift):

```swift
/// One-sentence summary, editable inline — saved on Return or when focus leaves the field.
struct InlineSummaryField: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("One-sentence summary…", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.callout)
            .lineLimit(1...3)
            .focused($focused)
            .onAppear { text = paper.summary }
            .onSubmit { commit() }
            .onChange(of: focused) { _, nowFocused in if !nowFocused { commit() } }
    }

    private func commit() {
        guard text != paper.summary else { return }   // no-op saves would churn updatedAt
        vm.saveSummary(text, for: paper)
    }
}
```

`DetailSummaryField` (PaperDetailView.swift) — same treatment, keeping its paper-change reset:

```swift
/// Editable one-sentence summary in the detail panel. Reloads its text when the selected
/// paper changes; saves on Return or when focus leaves the field.
private struct DetailSummaryField: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Summary").font(.caption).foregroundStyle(.secondary)
            TextField("One-sentence summary…", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { _, nowFocused in if !nowFocused { commit() } }
        }
        .onAppear { text = paper.summary }
        .onChange(of: paper.id) { _, _ in text = paper.summary }
    }

    private func commit() {
        guard text != paper.summary else { return }
        vm.saveSummary(text, for: paper)
    }
}
```

- [ ] **Step 2: Tag field commits typed text on blur**

In `TagInputField.swift`, on the `TextField` (after `.onSubmit`, line 34), add:

```swift
                    .onChange(of: focused) { _, nowFocused in
                        if !nowFocused, !newTag.isEmpty { commit(newTag) }
                    }
```

- [ ] **Step 3: Edit sheet asks before discarding changes**

In `PaperEditSheet.swift`:
- Add state after `@State var paper: Paper`:

```swift
    @State private var original: Paper
    @State private var confirmDiscard = false
```

- Extend `init`:

```swift
    init(paper: Paper) {
        _paper = State(initialValue: paper)
        _original = State(initialValue: paper)
    }
```

- Replace the Cancel button (line 48):

```swift
                Button("Cancel") {
                    if paper != original { confirmDiscard = true } else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
```

- On the outer `VStack(spacing: 0)` (after `.frame(width: 560, height: 580)`), add:

```swift
        .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
```

- [ ] **Step 4: Review** — `Paper` is Equatable (GalleryCard already compares with `==`); `.keyboardShortcut(.cancelAction)` routes the sheet's Esc through the dirty check.

- [ ] **Step 5: Commit and push**

```bash
git add NimbleScholar/Library/RowsView.swift NimbleScholar/Library/PaperDetailView.swift NimbleScholar/Library/TagInputField.swift NimbleScholar/Library/PaperEditSheet.swift
git commit -m "fix(library): commit inline summary/tag edits on focus loss; edit sheet dirty check

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
```

---

### Task 10: "Last read" cue + honest find-bar counter

**Files:**
- Modify: `NimbleScholar/Reader/PDFKitView.swift` (persist page count)
- Modify: `NimbleScholar/Library/PaperDetailView.swift` (show the cue)
- Modify: `NimbleScholar/Reader/FindBar.swift` (500+ counter)

**Interfaces:**
- Produces: UserDefaults key `"readingPageCount.<paperID>"` (written by the reader, read by the detail view; complements existing `"readingPage.<paperID>"`).

- [ ] **Step 1: Persist the page count when the reader opens**

In `PDFKitView.makeNSView`, right after `let key = "readingPage.\(vm.paper.id ?? -1)"` (line 44), add:

```swift
        // The detail view shows "Last read: p. X of Y" without opening the PDF.
        UserDefaults.standard.set(document.pageCount, forKey: "readingPageCount.\(vm.paper.id ?? -1)")
```

- [ ] **Step 2: Show the cue in the detail view**

In `PaperDetailView`, under the authors/venue/year `Text` (line 22), add:

```swift
                if let cue = lastReadCue {
                    Label(cue, systemImage: "bookmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
```

and add the helper to `PaperDetailView`:

```swift
    /// "Last read: p. X of Y" from the reader's saved position (0 = never opened / page 1).
    private var lastReadCue: String? {
        guard let id = paper.id else { return nil }
        let page = UserDefaults.standard.integer(forKey: "readingPage.\(id)")
        guard page > 0 else { return nil }
        let count = UserDefaults.standard.integer(forKey: "readingPageCount.\(id)")
        return count > 0 ? "Last read: p. \(page + 1) of \(count)" : "Last read: p. \(page + 1)"
    }
```

- [ ] **Step 3: Find bar shows the cap**

In `FindBar.swift`:
- Add state after `@State private var current = 0`: `@State private var capped = false`
- In `runSearch()`, replace the cap line:

```swift
        capped = found.count > Self.maxMatches
        if capped { found = Array(found.prefix(Self.maxMatches)) }
```

(and set `capped = false` in the early-return guard branch, next to `matches = []`.)
- Replace `counterText`:

```swift
    private var counterText: String {
        if matches.isEmpty { return "Not found" }
        return "\(current + 1) of \(matches.count)\(capped ? "+" : "")"
    }
```

- [ ] **Step 4: Commit and push**

```bash
git add NimbleScholar/Reader/PDFKitView.swift NimbleScholar/Library/PaperDetailView.swift NimbleScholar/Reader/FindBar.swift
git commit -m "feat(reader): last-read cue on the detail page; find bar reports capped match counts

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
```

---

### Task 11: Final review + user verification checklist

**Files:** none created; review-only.

- [ ] **Step 1: Whole-diff self-review**

Run `git log --oneline` (11 commits expected for Tasks 1-10) and `git diff <base>..HEAD --stat`. Re-read every modified Swift file end-to-end checking: type-checker-friendly expressions, no orphaned references (`vm.delete`, `bulkDelete`, `openSelectedReader`, hidden ⌘O button), Equatable `==` functions updated wherever card inits gained parameters, and all `reload(resort:)` call sites consistent.

- [ ] **Step 2: Hand the user this manual checklist** (they run `git pull && bash scripts/install_app.sh`, and `cd NimbleScholarCore && swift test --filter ListOrderTests` for the Core tests):

1. Open a paper → open the side list → **single-click another paper → its PDF loads directly** (no metadata page).
2. Jump A→B→A: **A reopens at your last position**.
3. While reading, click a **tag in the left rail** → list re-filters and reveals, PDF stays open; click papers from that tag to compare.
4. **⌥⌘↓ / ⌥⌘↑** step through the visible list while reading; **⌘W** closes the reader; ⌘W in the library closes the window.
5. **Double-click** a paper in the three-pane list (browse mode) → reader opens; single click still selects instantly.
6. Delete a paper (context menu / ⌫ / detail / edit sheet / bulk bar) → **confirmation appears every time**; Cancel keeps it.
7. **⌘O** with a paper selected opens the reader; the new **Paper menu** shows Read / Next / Previous / Night Reading (⌥⌘N flips inversion live).
8. **⌘= / ⌘− / ⌘0** zoom in the reader; **⌥⌘I** toggles the inspector.
9. In gallery/rows: **⌘-click** several papers → bulk bar appears; unread papers show the **blue dot**.
10. Type a summary, click away without Return → **it saved**. Same for a typed-but-uncommitted tag.
11. Edit sheet: change the title, press Esc → **"Discard unsaved changes?"**.
12. Detail page of a previously read paper shows **"Last read: p. X of Y"**.
13. "Recently added" scope shows **all** papers, not 30.
14. While the auto-completer is fetching figures (status bar busy), the list **doesn't reshuffle** under you.
15. Search a one-letter query in a long PDF → counter can read **"1 of 500+"**.

- [ ] **Step 3: Report** any checklist failures back and fix before closing the branch of work.
