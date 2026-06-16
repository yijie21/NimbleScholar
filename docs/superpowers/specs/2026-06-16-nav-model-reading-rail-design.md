# Design — Navigation Model Cleanup + Reading Icon Rail

Date: 2026-06-16
Status: Approved (pending spec review)

## Overview

Make the app's navigation/"transfer" logic coherent and macOS-elegant (Approach A), and
replace the disappearing sidebar (during reading) with a slim, clickable **icon rail**.

Two parts:
1. **Centralize navigation state + fix coupling bugs** — one selection source of truth and
   all transitions as named methods on `LibraryViewModel`.
2. **Reading icon rail** — while reading, the full sidebar collapses and a 56pt icon rail
   appears in its place; clicking a scope exits the reader and shows that scope.

Decisions (from brainstorming): Approach A (keep the 3 view modes; no full rebuild);
rail click while reading = **exit reader + show that scope**.

## Background (problems being fixed)

From the navigation audit:
- Two parallel selection states (`selection` for Gallery/Rows, `multiSelection` for
  three-pane) synced only inside `openReader` → Gallery taps don't carry to three-pane;
  ⌘O is dead after a Gallery tap.
- Closing the reader / changing scope leaves stale `multiSelection`/`readingPaperID` (you
  can "read" a paper not in the visible list).
- Reading mode logic + sidebar collapse smeared across files.

## 1. Centralized navigation (`LibraryViewModel`)

- **Remove `selection`** (the `Paper.ID?`). Use **`multiSelection: Set<Int64>`** as the one
  selection. `currentPaperID` (computed) = `multiSelection.count == 1 ? multiSelection.first : nil`.
- **Transition methods** (the single place transitions live):
  - `func select(_ paper: Paper)` → `multiSelection = [id]`.
  - `func openReader(_ paper: Paper)` → `multiSelection = [id]`, `readingPaperID = id`.
  - `func closeReader()` → `readingPaperID = nil` (keep `multiSelection` so the detail shows
    the paper).
  - `func setScope(_ s: LibraryScope)` → `readingPaperID = nil`; `scope = s` (its `didSet`
    reloads).
- **Invalidate stale selection on reload:** at the end of `reload()`, prune
  `multiSelection` to ids present in `papers`
  (`multiSelection = multiSelection.filter { id in papers.contains { $0.id == id } }`).
- `tags`-rename/`delete` paths already adjust scope; route them and the sidebar through
  `setScope` so reading always exits on a scope change.

## 2. Selection call sites

- **GalleryView** / **RowsView**: single tap → `vm.select(paper)` (was `vm.selection = id`);
  the card "selected" ring → `vm.multiSelection.contains(paper.id ?? -1)` (was
  `vm.selection == paper.id`). Double-tap / Read → `vm.openReader(paper)` (unchanged).
- **ThreePaneView**: list still binds to `$vm.multiSelection` (keeps shift/⌘ multi-select +
  bulk bar). Detail shows when `multiSelection.count == 1` (unchanged).
- **⌘O** (`openSelectedReader`): uses `currentPaperID`; now works after a Gallery/Rows tap.

## 3. Reading icon rail

`LibraryContentView.body` becomes:
```swift
HStack(spacing: 0) {
    if vm.readingPaperID != nil {
        ReadingRail().environmentObject(vm)
            .transition(.move(edge: .leading).combined(with: .opacity))
        Divider()
    }
    NavigationSplitView(columnVisibility: $columns) {
        SidebarView().environmentObject(vm).frame(minWidth: 200)
    } detail: { detail }
    … (existing onChange, safeAreaInsets, task, sheet)
}
.animation(.easeInOut(duration: 0.25), value: vm.readingPaperID)
```
- The existing `onChange(readingPaperID)` still collapses the split view's sidebar
  (`columns = .detailOnly`) while reading, so the rail stands in for it (no double sidebar);
  `.all` restores the full sidebar when reading ends.
- **`ReadingRail`** (new `NimbleScholar/Library/ReadingRail.swift`): a 56pt-wide `VStack`
  (in a `ScrollView`) of icon buttons:
  - Fixed scopes: All (`tray.full`), Important (`star.fill`, gold), Unread (`circle.fill`),
    Recently added (`clock`), Untagged (`tag.slash`).
  - A divider, then one dot per tag (`Circle().fill(TagColor.color(for:))`) from
    `vm.tagCounts`.
  - Each is a `Button { vm.setScope(<scope>) }`, `.help(<name>)`, with the active scope
    highlighted (filled background when `vm.scope == <scope>`).
  - Clicking any item runs `setScope`, which exits the reader (so the rail disappears and
    the full sidebar returns showing the chosen scope).

## 4. Unchanged

The three view modes, `EmbeddedReader` (PDF + inline inspector, no thumbnails), the
reading-width narrowing of the list, and all toolbar/menu actions stay as they are.

## Testing
- **Unit (`swift test`):** none required (UI/navigation). Optionally a tiny VM test that
  `setScope` clears `readingPaperID`, and that `reload()` prunes a now-absent selection —
  both are pure-ish and testable with an in-memory store.
- **Manual:** tap in Gallery then ⌘O opens that paper; switching Gallery→Three-pane keeps
  the selection; open reader → 56pt rail shows with the right icons; clicking a rail scope
  exits the reader and shows that scope; deleting the current tag while reading exits the
  reader; bulk multi-select + bottom bar still work in three-pane.

## Risks / notes
- The rail is a custom sibling column (not a NavigationSplitView column) because
  NavigationSplitView sidebars can't be made as narrow as 56pt; this keeps the main split
  view intact and only adds the rail during reading.
- Removing `selection` touches Gallery/Rows highlight + tap; the `?? -1` fallback matches
  existing list-tag behavior and is only used for the highlight comparison.
