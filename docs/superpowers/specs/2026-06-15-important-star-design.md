# Design — Mark Papers Important (Star)

Date: 2026-06-15
Status: Approved (pending spec review)

## Overview

Let the user mark a paper "important" with a gold star. Important papers float to the top
of every list — All papers and within any tag/scope filter — keeping the chosen sort order
within the starred group and the rest. A dedicated "Important" sidebar filter shows only
starred papers.

Decisions (from brainstorming):
- **Toggle from:** a clickable star on each card, the right-click menu, and the detail pane.
- **Sidebar:** add an "Important" filter alongside All / Unread / Recently added / Untagged.
- **Ordering:** important-first in all scopes, stable (preserves the active sort within groups).

## 1. Data model

Add to `Paper`: `isImportant: Bool = false` → column `important` (in `Columns` + `CodingKeys`).

Migration `v8-important` (after `v7-existing-code-ready`):
```sql
ALTER TABLE papers ADD COLUMN important INTEGER NOT NULL DEFAULT 0;
```
Not added to `papers_fts`.

## 2. Store

`LibraryStore.setImportant(paperID:important:)` — mirrors the existing `setRead`:
updates the `important` column and bumps `updated_at`. (Reuse the same write pattern as
`setRead`, including touching `updatedAt` so observers refresh.)

## 3. View model (`LibraryViewModel`)

- `func toggleImportant(_ paper: Paper)` → `store.setImportant(paperID:important: !paper.isImportant)` then `reload()`.
- `enum LibraryScope` gains `case important`.
- `scopeTitle`: `.important → "Important"`.
- `reload()`:
  - `.important` → `((try? store.searchPapers(query: query, tag: nil)) ?? []).filter { $0.isImportant }`.
  - Apply ordering as the **final** step for all scopes:
    ```swift
    let ordered = (scope == .recent) ? Array(result.prefix(30)) : sorted(result)
    papers = floatImportant(ordered)
    ```
  - `private func floatImportant(_ list: [Paper]) -> [Paper] { list.sorted { $0.isImportant && !$1.isImportant } }`
    (Swift's sort is stable, so order within the starred group and within the rest is preserved.)
- `sort` `didSet` handler: change `papers = sorted(papers)` → `papers = floatImportant(sorted(papers))` so re-sorting keeps stars on top.

## 4. UI

**`ImportanceStar`** — reusable view (new file `NimbleScholar/Library/ImportanceStar.swift`):
```swift
struct ImportanceStar: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper
    var body: some View {
        Button { vm.toggleImportant(paper) } label: {
            Image(systemName: paper.isImportant ? "star.fill" : "star")
                .foregroundStyle(paper.isImportant ? .yellow : .secondary)
        }
        .buttonStyle(.plain)
        .help(paper.isImportant ? "Unmark important" : "Mark important")
    }
}
```

Placement:
- **Three-pane list rows**, **gallery cards**, **rows cards**: add `ImportanceStar(paper:)` to each
  card (a small corner/leading star). On gallery/three-pane, place it as a top-leading overlay
  (mirroring how `PaperStatusBadge` sits in a corner); on the wide rows card, place it leading.
- **Detail view** (`PaperDetailView`): an `ImportanceStar(paper:)` next to the title.
- **Context menu** (`PaperContextMenu`): a button toggling importance, next to Mark-as-Read:
  ```swift
  Button { vm.toggleImportant(paper) } label: {
      Label(paper.isImportant ? "Unmark Important" : "Mark as Important",
            systemImage: paper.isImportant ? "star.slash" : "star")
  }
  ```
- **Sidebar** (`SidebarView`): in the top `Section`, add
  `Label("Important", systemImage: "star.fill").tag(LibraryScope.important)`
  (the SF Symbol renders gold via `.symbolRenderingMode`/tint if desired; default is fine).

## 5. Testing

- **Unit (`swift test`):** `setImportant` round-trip via the store (set true → read back true; toggle false).
- **Manual:** star a paper from a card / right-click / detail → it jumps to the top of All papers
  and stays on top inside a tag filter; the active sort order holds within the starred group;
  the "Important" sidebar entry lists only starred papers; unstarring drops it back.

## Risks / notes
- **Recently added** also floats stars to the top of its 30-item window — consistent with the
  rest, and harmless.
- No change to capture, reader, or existing sorts beyond the always-on important-first layer.
