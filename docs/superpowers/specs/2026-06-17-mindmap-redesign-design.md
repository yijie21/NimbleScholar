# Design — Mindmap Redesign: Auto-Layout Tree

Date: 2026-06-17
Status: Approved (pending spec review)
Supersedes the interaction/rendering/data-model of `2026-06-17-mindmap-design.md`
(the first cut). Builds on branch `feat/mindmap` (not yet merged).

## Overview

The first mindmap cut (free-form canvas: manually positioned nodes, drag-a-dot to connect)
had two problems in real use: **dragging a node flickers** (every drag frame writes node
coordinates into the `@Published` model, re-rendering the whole canvas and fighting the
gesture), and there is **no natural way to grow a tree from a root** (the dot-drag connect
is not how people build mindmaps).

This redesign replaces the interaction with a **classic auto-layout logical tree** — the
model used by simple-mind-map, jsMind, markmap, XMind, and MindNode. The decisive insight
from researching those tools: an auto-layout tree **persists structure, not per-node
coordinates**, so a drag commits one structural change on release and the layout engine
computes positions — there is no per-frame coordinate write, which removes the flicker
*by design*.

Decisions (from brainstorming):
- **Auto-layout tree** (not free-form, not hybrid). Nodes are placed by a layout engine;
  the user never positions nodes by hand.
- **Keyboard-driven editing:** Tab = add child, Return = add sibling (the dominant
  convention; jsMind's Tab-as-no-op is the minority and not followed).
- **Undo/redo included** (snapshot stack). Export deferred.
- **Paper attachment is kept** unchanged (drag a shelf card onto a node → chip; click chip
  → reader; ✕ → detach).

Non-goals (deferred): export (Markdown/OPML), multiple layout modes (radial/org/fishbone),
free positioning, cross-branch links, presentation mode, collaboration, AI generation.

## What changes vs. what stays

**Stays (reused as-is or lightly extended):** the 4th view mode wiring
(`LibraryContentView`, `AppEnvironment.mindmaps`), `CanvasTransform`, `MapBar`,
`PaperShelf`, `NodePaperChip`, the `MindmapStore`/`Mindmap`/`MindmapNode` plumbing, the
GRDB store + change observation.

**Replaced (rewritten):** `MindmapViewModel`, `MindmapCanvas`, `NodeView`.

**Removed/dormant:** free node positioning; the connect-dot drag handle; drop-on-empty-
canvas-creates-node; free-form edges. The `mindmap_edges` table and `MindmapEdge` model plus
`MindmapStore.addEdge/deleteEdge/edges(forMap:)` become **unused** — left in place (dormant)
to keep the migration additive; not actively deleted to limit churn. Tree structure now lives
entirely in `mindmap_nodes.parent_id`.

## 1. Data model — `v10-mindmap-tree` migration (additive, idempotent)

Registered in the single `LibraryStore.migrator`, after `v9-mindmap`. Adds three columns to
`mindmap_nodes`:

```
parent_id   INTEGER NULL  REFERENCES mindmap_nodes(id) ON DELETE CASCADE   -- NULL = root
sort_order  INTEGER NOT NULL DEFAULT 0                                     -- order among siblings
collapsed   INTEGER NOT NULL DEFAULT 0                                     -- subtree folded
```

Consequences:
- **Subtree delete is free:** `parent_id` cascade means deleting a node deletes all
  descendants in one `deleteOne`.
- **Positions are derived, never persisted.** The existing `x`/`y` columns are no longer the
  source of truth; the layout engine computes positions at render time. The columns remain
  (harmless) but are not written by the tree code.
- **One root per map**, auto-created (text = the map's name, or "Central idea" if blank), with
  `parent_id = NULL`. The root cannot be deleted (delete is refused; deleting the map removes
  it via the existing `mindmap_id` cascade).
- Pre-existing free-form nodes (the first cut is unreleased, so in practice none) would load as
  `parent_id = NULL` (multiple roots). `ensureRoot` (below) reconciles: if a map has no nodes,
  create a root; this is the only reconciliation v1 needs.

### Core model change (`Models/Mindmap.swift`)
`MindmapNode` gains `parentID: Int64?` (`parent_id`), `sortOrder: Int` (`sort_order`),
`collapsed: Bool` (`collapsed`) with matching `CodingKeys`, following the existing
camelCase↔snake_case pattern. A `MindmapTree` value type carries the loaded map:
`nodes: [MindmapNode]`, `paperIDsByNode: [Int64: [Int64]]`, and a computed
`childrenByParent: [Int64: [MindmapNode]]` (sorted by `sortOrder`) + `rootID: Int64?`.

## 2. Core — `TreeLayout` (pure, unit-tested) — `Core/Services/TreeLayout.swift`

A pure value type / function: tidy **left-to-right logical layout** (Reingold–Tilford-style
subtree-extent accumulation), the model used by simple-mind-map and markmap.

```
struct TreeLayout {
    struct Config { var levelGapX: CGFloat = 60; var siblingGapY: CGFloat = 16 }
    /// Returns a center position per visible node. Collapsed nodes' children are excluded.
    static func positions(
        rootID: Int64,
        childrenByParent: [Int64: [Int64]],     // already sorted by sort_order
        collapsed: Set<Int64>,
        sizeOf: [Int64: CGSize],                 // measured/estimated node sizes
        config: Config = .init()
    ) -> [Int64: CGPoint]
}
```

Algorithm (two-pass):
- **x (depth):** `x(node) = sum over ancestors of (levelWidth + levelGapX)`, where a level's
  width is the max node width at that depth (so columns don't overlap on wide nodes).
- **y (subtree extent):** recursively, `extent(node) = max(node.height, Σ extent(children) +
  siblingGapY·(n−1))`; stack children within the parent's extent; set the parent's y to the
  **center of its children's y-span** (or its own center if a leaf/collapsed).
- Collapsed nodes contribute only their own size (children excluded from `childrenByParent`
  traversal).

Node sizes come from a small pure estimator, also in Core (testable):
`MindmapNodeSizing.size(text:chipCount:) -> CGSize` — fixed width, height = base + estimated
text lines + `chipCount · chipHeight`. The app passes the resulting `[nodeID: CGSize]` to
`TreeLayout.positions`. (Real text measurement is a later refinement; estimation keeps layout
pure and deterministic for tests.)

## 3. `MindmapStore` — tree operations (extends the existing store)

New methods (alongside the existing map/paper CRUD, which are unchanged):

- `func ensureRoot(mapID:title:) throws -> MindmapNode` — return the existing root or create one.
- `func addChild(parentID:text:) throws -> MindmapNode` — `sort_order = max(siblings)+1`.
- `func addSibling(of nodeID:text:) throws -> MindmapNode` — same parent, inserted after
  `nodeID`, shifting later siblings' `sort_order`.
- `func setParent(nodeID:newParentID:index:) throws` — re-parent; renumber the destination
  siblings to insert at `index`. Rejected by the **view model** if `newParentID` is a
  descendant of `nodeID` (cycle guard).
- `func reorderSibling(nodeID:direction:) throws` — swap `sort_order` with the prev/next sibling.
- `func setCollapsed(nodeID:collapsed:) throws`.
- `func deleteNode(id:) throws` — existing method; `parent_id` cascade removes the subtree.
- `func tree(forMap:) throws -> MindmapTree` — one read: nodes (ordered by
  `parent_id, sort_order`) + the node→paper links (the existing `graph` join), assembled into
  `MindmapTree`.

**Undo/redo support** — id-stable snapshot/restore:
- `func snapshot(mapID:) throws -> MapSnapshot` — captures every node row (with its **id**,
  parent_id, sort_order, collapsed, text) + the `(node_id, paper_id)` links for the map.
- `func restore(mapID:_ snapshot:) throws` — in one transaction: delete all nodes for the map
  (cascade clears links), then re-insert each snapshot node **with its explicit id** (SQLite
  permits explicit-rowid insert) and re-insert the paper links. Preserving ids means selection
  and paper attachments survive an undo. A map is small, so a full snapshot is cheap.

## 4. `MindmapViewModel` — tree state, selection, keyboard, undo (rewrite)

`@MainActor ObservableObject`. Holds: `maps`, `activeMapID`, the loaded `tree: MindmapTree`,
`selectedNodeID: Int64?`, `editingNodeID: Int64?`, the computed `layout: [Int64: CGPoint]` +
`sizes: [Int64: CGSize]`, `transform: CanvasTransform`, and `undoStack`/`redoStack` of
`MapSnapshot`.

Every **structural** op follows: push current snapshot to `undoStack` (clear `redoStack`) →
write to store → `reloadTree()` → `relayout()` → publish. `reloadTree()` calls
`store.tree(forMap:)`; `relayout()` computes `sizes` (from text + chip count) then
`TreeLayout.positions(...)`.

Public surface (consumed by the canvas/node views):
- Structure: `addChild(toSelected)`, `addSibling(ofSelected)`, `deleteSelectedSubtree()`,
  `reparent(nodeID:to:index:)`, `reorder(nodeID:_:)`, `toggleCollapse(nodeID:)`.
- Text: `beginEdit(nodeID:)`, `commitEdit(_ text:)`, `cancelEdit()` (via `editingNodeID`).
- Selection/nav: `select(nodeID:)`, `navigate(_ direction: MoveDirection)` (↑/↓ = prev/next
  sibling, ← = parent, → = first visible child).
- Papers (kept): `attach(paperID:to:)`, `detach(paperID:from:)`.
- Drag-reparent hit-testing: `dropTarget(forDragged nodeID:at canvasPoint:) -> DropTarget?`
  where `DropTarget` is `(parentID: Int64, index: Int, kind: .child|.siblingBefore|.siblingAfter)`;
  returns nil over self/descendant.
- Undo: `undo()`, `redo()` (snapshot restore; then reload + relayout; keep selection if the id
  still exists).
- View helpers: `fit(in size:)` (frame the whole tree into the viewport), `updateTransform(_:)`.

The **cycle guard** (can't drop a node into its own subtree) lives here, checked against
`tree.childrenByParent` before calling `store.setParent`.

## 5. Rendering — two-layer, anti-flicker (`MindmapCanvas` rewrite)

Adopts Excalidraw's static/interactive split so dragging never re-renders the committed
content.

- **Committed layer:** one `Canvas` pass drawing parent→child connectors (horizontal beziers
  between `layout[parent]` and `layout[child]`), then a `ForEach` of `NodeView`s placed via
  `.position(transform.screen(from: layout[id]))`. Off-screen nodes are viewport-culled
  (reuse `CanvasTransform.isVisible`). `NodeView` is `Equatable` (on id + text + collapsed +
  selected + chip ids + position) so re-rendering one node does **not** invalidate siblings.
- **Interactive overlay (above, hit-test-transparent except the active gesture):** the **drag
  ghost** (a lightweight copy of the dragged node following an ephemeral `@GestureState`
  offset), the **drop indicator** (a line/box at the resolved `DropTarget`), and the
  **selection ring**. Because the ghost lives here, a re-parent drag mutates only local
  gesture state until **`.onEnded`**, which calls `vm.reparent(...)` once → one store write →
  one relayout. The committed layer is untouched during the drag.
- Pan = background `DragGesture`; zoom = `MagnifyGesture` (clamped) + on-canvas +/−; **Fit**
  button frames the tree. Single transform on the container (never per-node).

## 6. Interactions — the "real mindmap" feel (`NodeView` rewrite + canvas key handling)

The canvas is focusable (`@FocusState`); key handling via `.onKeyPress` (macOS 14). When a
node is **selected (not editing)**:
- **Tab** → add child (select + begin editing it) · **Return** → add sibling (select + edit) ·
  **Delete/Backspace** → delete node + subtree (refused on root; selection moves to parent) ·
  **Space** → toggle collapse · **arrows** → move selection (↑/↓ sibling, ← parent, → first
  child) · **Ctrl+↑/↓** → reorder among siblings · **⌘Z / ⌘⇧Z** → undo / redo.

When a node is **editing**: a `TextField` (`@FocusState`); **Return** commits, **Esc** cancels.
Enter into editing via double-click or type-to-edit. (To avoid Tab/Return ambiguity, editing
mode consumes Return/Esc for commit/cancel; create-child/sibling act only on a selected,
non-editing node.)

- **Re-parent drag:** drag a node → the overlay shows a ghost + a drop indicator computed from
  `vm.dropTarget(...)`; release commits the reparent. Dropping onto self/descendant is rejected
  (no indicator).
- **Papers (kept):** drag a shelf card onto a node → `vm.attach`; click a chip →
  `libraryVM.openReader`; ✕ on a chip → `vm.detach`. Dropping a paper on empty canvas is now a
  no-op.
- **Collapse affordance:** nodes with children show a small triangle; click toggles collapse.
- **Toolbar/context-menu fallback:** a compact canvas toolbar (Add child · Add sibling · Delete
  · Collapse · Undo · Redo · Fit) and a node context menu mirror every shortcut, so the feature
  is fully usable even where `.onKeyPress` mis-captures a key (Tab focus-traversal on macOS can
  be finicky).

## 7. Testing

**Core (`swift test`):**
- `TreeLayoutTests`: single node; a parent with N children (parent centered on children's
  span); multi-level extents don't overlap; a collapsed node excludes its children from
  positions; deterministic positions for a fixed tree + size map.
- `MindmapNodeSizingTests`: height grows with text lines and chip count; fixed width.
- `MindmapStoreTests` additions: `ensureRoot` (creates once, idempotent); `addChild`/
  `addSibling` assign correct `sort_order`; `setParent` re-parents and renumbers; `reorderSibling`
  swaps order; `setCollapsed`; delete-subtree cascade (delete a mid node removes its
  descendants); `tree(forMap:)` shape (children sorted, paperIDsByNode); **snapshot → mutate →
  restore round-trip preserves node ids, structure, and paper links**.

**App (manual, on macOS):** keyboard create/edit/navigate/delete; collapse/expand; drag-to-
reparent with drop indicator + descendant rejection; undo/redo; paper attach + chip-open;
**smoothness** — dragging a node and panning/zooming must not flicker (verify the committed
layer isn't re-rendering per frame); relaunch restores the tree + collapsed state.

## 8. Migration & compatibility

`v10-mindmap-tree` is additive/idempotent. The first cut is unreleased, so there is no real
free-form data to convert; `ensureRoot` covers the only case (a map needs a root).
`createMap` creates a root immediately so a new map opens with an editable central node.

## 9. File-level plan (informs the implementation plan)

- **Core (new):** `Services/TreeLayout.swift`, `Services/MindmapNodeSizing.swift`;
  tests `TreeLayoutTests.swift`, `MindmapNodeSizingTests.swift`.
- **Core (modified):** `Store/LibraryStore.swift` (+`v10-mindmap-tree`); `Models/Mindmap.swift`
  (+`parentID`/`sortOrder`/`collapsed`, `MindmapTree`, `MapSnapshot`); `Store/MindmapStore.swift`
  (+tree ops, snapshot/restore); `Tests/MindmapStoreTests.swift` (+tree/snapshot tests).
- **App (rewritten):** `Mindmap/MindmapViewModel.swift`, `Mindmap/MindmapCanvas.swift`,
  `Mindmap/NodeView.swift`.
- **App (unchanged):** `Mindmap/MindmapView.swift` (layout shell), `Mindmap/MapBar.swift`,
  `Mindmap/PaperShelf.swift`. (`MindmapView` may gain the small canvas toolbar.)

## 10. Risks / notes

- **`.onKeyPress` + Tab:** macOS may reserve Tab for focus traversal; `.onKeyPress(.tab)`
  returning `.handled` should intercept it, but the toolbar/context-menu fallback guarantees
  usability if a specific key is captured. This is the highest-risk interaction; it is isolated
  to `NodeView`/canvas key handling and backed by the fallback.
- **Node size estimation vs. real text:** v1 estimates height; very long labels could be
  slightly mis-sized. Acceptable — layout stays pure/testable; real measurement is a later
  refinement that only swaps the `sizeOf` input.
- **Dormant `mindmap_edges`:** left unused rather than dropped to keep the migration additive;
  a later cleanup migration can remove it.
- **Undo granularity:** one snapshot per structural op (not per keystroke); text edits snapshot
  on commit. This matches user expectation and keeps the stack small.
</content>
