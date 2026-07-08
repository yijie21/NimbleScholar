# Reading-experience & UX overhaul — design

**Date:** 2026-07-08
**Status:** Approved by user

## Problem

Reading and comparing papers is high-friction:

1. While reading, clicking another paper in the side list shows its metadata page;
   the user must click **Read** again to see the PDF (two-step switch).
2. Clicking a tag in the reading rail exits reading mode entirely, so "read the
   papers under this tag, jumping between them" is impossible.
3. A broader UX audit found nine further rough edges: unconfirmed destructive
   deletes, missing keyboard navigation, silent data loss on inline edits,
   swallowed persistence errors, view-mode inconsistencies, background reloads
   reordering the list, and invisible reading-position state.

## Root causes (current code)

- `ThreePaneView` shows `EmbeddedReader` only when the selected paper's id equals
  `readingPaperID`; selecting a different paper falls back to `PaperDetailView`.
- `LibraryViewModel.scope`'s `didSet` sets `readingPaperID = nil` (exits reader).
- `EmbeddedReader` holds `ReaderViewModel` in a `@StateObject`; without
  re-identifying the view per paper, swapping `readingPaperID` would keep showing
  the old document.
- `openReader` force-folds the paper list (`showPaperList = false`) on every open.

## Design

### 1. Fast paper switching in the reader

- **Reader driven by `readingPaperID`, not selection.** While
  `readingPaperID != nil`, the three-pane detail pane renders
  `EmbeddedReader(paperID: readingPaperID).id(readingPaperID)` regardless of
  `multiSelection`. `.id()` re-creates the `ReaderViewModel` so the document
  actually swaps; the outgoing paper's annotations are flushed
  (`vm.flushSave()`) before the swap.
- **Single-click switches.** While reading, a selection change to exactly one
  paper sets `readingPaperID` to that paper. (Selection and reading paper stay
  in sync; multi-selection while reading keeps the current PDF open.)
- **Position survives switching** via the existing per-paper last-page
  persistence (`ReaderViewModel` saves, `PDFKitView` restores). No new work
  beyond verifying the flush ordering.
- **Tag/scope clicks keep you reading.** `scope.didSet` no longer clears
  `readingPaperID`. While reading, a rail click re-filters the paper list to the
  new scope and sets `showPaperList = true` so the filtered list is visible.
  The current PDF stays open even when it is not in the new scope.
- **Next/previous paper:** ⌥⌘↓ / ⌥⌘↑ step through `vm.papers` (the currently
  filtered, sorted list) from inside the reader, wrapping at the ends. Exposed
  as menu items ("Next Paper" / "Previous Paper") so they are discoverable;
  disabled when not reading.
- **Double-click in the three-pane list opens the reader**, matching
  gallery/rows. Implemented so native single-click selection stays instant
  (double-click gesture on the row content, no plain `.onTapGesture`).
- **List visibility is a remembered preference.** `showPaperList` persists via
  `@AppStorage`; `openReader` stops force-folding it. Scope clicks while reading
  may still reveal it (above) — that write updates the stored preference too.

### 2. Safety: delete confirmation + visible errors

- **One confirmation gate for every delete path** (context menu, detail view,
  edit sheet, ⌫ key via `.onDeleteCommand`, bulk bar):
  `LibraryViewModel.requestDelete(_:)` records the pending papers and a
  `confirmationDialog` ("Delete N papers? This cannot be undone.") performs or
  cancels. No undo system this round.
- **Visible persistence errors.** A lightweight message channel on
  `ActivityCenter`/`StatusBar` surfaces failures that lose user data:
  - `ReaderViewModel.writeNow` — annotation/PDF write failures (check
    `doc.write(to:)`'s return value).
  - BibTeX export write failure.
  - Tag/summary/metadata save failures (store `update`/`setTags` throwing).
  Internal best-effort operations (figure scrapes, link scans, metadata
  enrichment) stay silent as today.
- **Annotations flush on app termination** (in addition to reader close), so a
  quit during the 0.6 s save debounce cannot lose the last edit.

### 3. Keyboard & discoverability

- **⌘W closes the reader** while reading; otherwise the default close-window
  behavior is untouched.
- **"Read Paper" menu command** (keeps ⌘O) replaces the hidden background
  button as the discoverable entry point.
- **Zoom shortcuts** on the existing toolbar buttons: ⌘+ zoom in, ⌘− zoom out,
  ⌘0 fit.
- **Night mode: menu command + ⌥⌘N** — deliberately *not* a toolbar button (the
  reader toolbar stays decluttered per prior request). Highlight color stays in
  Settings.
- **Inspector toggle: ⌥⌘I.**

### 4. Consistency across view modes

- **Multi-select in gallery and rows:** ⌘-click toggles membership, ⇧-click is
  additive; the bulk bar (count / Download / Delete) appears in all view modes.
- **Unread blue dot on gallery and rows cards**, matching the three-pane list.
- **"Recently added" scope drops its silent 30-item cap** — it becomes the full
  list sorted by created-date descending.
- **Inline edits commit on focus loss:** the summary fields (rows + detail) and
  `TagInputField` save when focus leaves the field, not only on Return.
- **Edit sheet dirty check:** Cancel/Esc with unsaved changes asks before
  discarding.

### 5. Stability & polish

- **Stable-order reloads.** Reloads triggered by DB observation of background
  (`touch: false`) writes merge updated rows in place, preserving the current
  on-screen order; a full re-sort happens only on user actions (sort change,
  scope change, query change, explicit edits, adds/deletes). Mechanism: compare
  the freshly fetched set's ids to the current order — when the id set is
  unchanged, keep the existing order and replace row contents; otherwise
  re-sort.
- **Reading-progress cue:** `PaperDetailView` shows "Last read: p. X of Y" when
  a saved position exists.
- **Find-bar cap honesty:** at the 500-match cap the counter shows "n of 500+".

## Error handling

- Delete confirmation is the only new modal; all other errors surface
  non-modally through the status-bar message channel with enough text to act on
  (operation + paper title).
- Reader switching guards: if the target paper has no PDF yet, the reader shows
  its existing "downloading/unavailable" state — switching never blocks on
  network.

## Testing

- Unit tests (ViewModel level, no UI): switch-while-reading sets
  `readingPaperID`; scope change while reading keeps `readingPaperID` and
  reveals the list; delete-confirmation flow (request → confirm → gone;
  request → cancel → intact); stable-order merge keeps order for unchanged id
  sets; recent scope uncapped.
- Everything visual/interaction-level is verified by the user's local build
  against a per-item manual checklist included in the implementation plan.

## Out of scope

Browser-style tabs, an undo system, unifying search-field placement across view
modes, reader-toolbar additions, and any capture/metadata pipeline changes.
