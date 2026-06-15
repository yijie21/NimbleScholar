# Design — Bind the Unread Dot to the `to-read` Tag

Date: 2026-06-15
Status: Approved (pending spec review)

## Overview

Make "unread" mean "has the `to-read` tag", end to end. New captures arrive tagged
`to-read` (already the default) and show the blue dot. Opening a paper via **Read** or
**Browser**, or removing the `to-read` tag by hand, clears the dot. The blue dot, the
"Unread" sidebar filter, and the right-click "Mark as Read/Unread" item all follow the
`to-read` tag — they can no longer disagree. Also: give the detail **Browser** button an
icon (it currently has none).

Decisions (from brainstorming):
- **Unify** the dot, the Unread filter, and the Mark-as-Read menu on the `to-read` tag.
- Opening via Read or Browser removes the `to-read` tag.
- Browser button icon = **safari** (matches the existing "Open in Browser" menu item).

The `isRead` column stays in place but no longer drives the UI (left to avoid a churny
migration; harmless).

## 1. Core (`LibraryStore`)

Add:
```swift
public func removeTag(_ name: String, fromPaper id: Int64) throws
```
Deletes the join row for `(paper, tag name)` and bumps `papers.updated_at` so the library
window's `ValueObservation` refreshes even when the tag is cleared from the *reader*
window. (The observation already tracks `paper_tags` count + `papers` MAX(updated_at).)
Implementation:
```sql
DELETE FROM paper_tags
 WHERE paper_id = ? AND tag_id = (SELECT id FROM tags WHERE name = ?);
UPDATE papers SET updated_at = ? WHERE id = ?;
```
No-op if the paper doesn't have the tag. Unit-tested (round-trip: add tag → remove → gone).

## 2. View model (`LibraryViewModel`)

- `static let toReadTag = "to-read"` — the single source of truth for the tag name.
- `func isUnread(_ paper: Paper) -> Bool { tags(for: paper).contains(Self.toReadTag) }`.
- `func markRead(_ paper: Paper)` → `store.removeTag(Self.toReadTag, fromPaper: id)` + `reload()`
  (used by the Browser actions).
- `func toggleToRead(_ paper: Paper)` → if `isUnread`, remove the tag; else add it
  (reuses existing `addTag`/`removeTag`, which reload). Powers the context menu.
- **Unread scope** in `reload()`:
  `case .unread: result = (try? store.searchPapers(query: query, tag: Self.toReadTag)) ?? []`
  (papers tagged `to-read`), replacing the old `!isRead` filter.

## 3. Reader (`ReaderViewModel`)

Replace the open-time read-marking line
`if let id = paper.id, !paper.isRead { try? store.setRead(paperID: id, read: true) }`
with clearing the tag:
`if let id = paper.id { try? store.removeTag(LibraryViewModel.toReadTag, fromPaper: id) }`.
This covers every reader entry point (detail Read, context-menu Read, double-click, ⌘O).

## 4. UI

- **Blue dot** (`ThreePaneView` list row): drive its opacity from `vm.isUnread(paper)`
  instead of `paper.isRead`:
  `Circle().fill(.blue)…​.opacity(vm.isUnread(paper) ? 1 : 0)`.
  Removing the `to-read` tag (by hand or via Read/Browser) hides the dot automatically.
- **Context menu** (`PaperContextMenu`): the Mark-as-Read button becomes:
  ```swift
  Button { vm.toggleToRead(paper) } label: {
      Label(vm.isUnread(paper) ? "Mark as Read" : "Mark as Unread",
            systemImage: vm.isUnread(paper) ? "checkmark.circle" : "circle")
  }
  ```
  and the existing "Open in Browser" item also calls `vm.markRead(paper)` before opening.
- **Detail view** (`PaperDetailView`): the **Browser** button gets the safari icon and
  clears the tag:
  ```swift
  Button {
      vm.markRead(paper)
      if let u = URL(string: paper.pdfURL.isEmpty ? paper.url : paper.pdfURL) {
          NSWorkspace.shared.open(u)
      }
  } label: { Label("Browser", systemImage: "safari") }
  ```

## 5. Testing

- **Unit (`swift test`):** `removeTag(_:fromPaper:)` — set a paper's tags to include
  `to-read`, remove it, assert it's gone (and a non-existent tag removal is a no-op).
- **Manual:** a captured paper shows the dot; opening it via Read clears the dot (in all
  view modes / entry points); the Browser button clears it; manually removing the `to-read`
  chip clears it; the "Unread" sidebar shows exactly the dotted papers; the Browser button
  shows a safari icon.

## Risks / notes
- Keys off the literal tag **`to-read`**. If the user changes the *default capture tag* in
  Settings to something else, new papers won't get the dot. Acceptable (documented).
- `isRead` / `setRead` / `toggleRead` become unused by the UI but remain defined; no
  migration or API removal, to keep the change small.
