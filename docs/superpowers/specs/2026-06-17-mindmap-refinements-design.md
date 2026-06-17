# Design — Mindmap Refinements (seed distance, edge-follows-drag, heading/content + collapse)

Date: 2026-06-17
Status: Approved (pending spec review)
Builds on the free-positioning change (`2026-06-17-mindmap-free-positioning-design.md`),
branch `feat/mindmap`.

## Overview

Three refinements from real use:
1. A Tab-created child spawns too far from its parent (mostly because a tiny new map is
   fit-zoomed up to 2.5×, exaggerating the seed offset).
2. Dragging a node does not move the connector line to its parent — the line lags until release.
3. Nodes need a **heading + optional content**; collapsing a node should hide its content,
   its attached papers, and its child subtree, leaving just the heading.

Decisions (from brainstorming):
- Collapse is one toggle: **collapsed = heading only**; **expanded = heading + content + paper
  chips + child subtree**.
- Content is edited by **double-clicking the content/body area** when expanded; the heading is
  edited by double-clicking the heading (as today).

Non-goals (YAGNI): rich-text/markdown content, resizable nodes, per-node colors.

## 1. Tab child spawns too far

Two fixes:

- **Cap fit-on-load zoom at 1.0.** `MindmapViewModel.fit(in:)` currently scales to fit and is
  clamped by `CanvasTransform.clampZoom` (min 0.25, max 2.5), so a lone-root map zooms to 2.5×
  and the seed offset looks enormous. Change `fit` to only ever scale **down**:
  `zoom = min(1.0, fitScale)` then `clampZoom`. A small tree opens at 100%.
- **Reduce the seed gap.** In `MindmapViewModel`, lower `seedGapX` from `220` to a small
  beside-the-parent offset (≈ node width with a ~30px gap; concrete value pinned in the plan,
  e.g. `seedGapX = 150`, `seedGapY = 60`) so a child appears just to the side of its parent and
  siblings just below.

## 2. Edge follows the drag

Today the connectors are drawn in the committed `Canvas` from the **stored** `layout`, while a
dragged node moves only via its local `@GestureState` offset, so the parent→child line stays put
until release.

Fix — a live drag position the connector layer reads:
- Extend the existing drag payload so a dragging node reports its **live center on every
  `.onChanged`** (not only when hovering a re-parent target). Concretely, change
  `NodeDragInfo` to `{ nodeID: Int64, center: CGPoint, target: DropTarget? }`: `center` is the
  node's live center (`storedCenter + translation/zoom`), set on every drag frame; `target` is
  the re-parent target (non-nil only past the 24pt threshold and over a node) used by the drop
  indicator.
- The connectors `Canvas` in `MindmapCanvas`, for any edge whose parent or child is
  `dragInfo?.nodeID`, uses `dragInfo!.center` for that endpoint instead of `layout[id]`. So the
  line tracks the node in real time. This re-renders only the single connectors `Canvas` per
  frame (cheap); the `NodeView`s remain `Equatable`-isolated, so no node re-render and no flicker.
- On `.onEnded` the drag payload clears and everything reverts to the committed `layout`
  (which the `move`/`reparent` write just updated).

The drop-indicator overlay keeps reading `dragInfo?.target`.

## 3. Heading + content; collapse = heading only

### Data — migration `v11-mindmap-content`
Add one column to `mindmap_nodes`:
```
content  TEXT NOT NULL DEFAULT ''
```
The existing `text` column is the **heading**; `content` is the optional body note. `collapsed`
already exists. `MindmapNode` gains `public var content: String = ""` with a `content` CodingKey
(snake_case == camelCase here).

### Node layout (`NodeView`)
- **Heading** row: always shown (the node's `text`), with a disclosure chevron when the node has
  anything to hide.
- **Collapsed** (`collapsed == true`): show heading + a ▶ chevron only. The child subtree stays
  hidden (already handled — collapsed nodes are excluded from `childIDsByParent`/layout
  traversal and Tidy).
- **Expanded** (`collapsed == false`): heading + ▾ chevron, then the **content** body (or a faint
  "Add note…" placeholder when empty), then the **paper chips**.
- **Chevron visibility:** show the collapse toggle when the node has children **or** non-empty
  content **or** attached papers — so a leaf node with just a note/papers can still collapse.
  (Today it only shows when there are children.) The view model exposes a helper, e.g.
  `canCollapse(_:)`, computed from the tree + content.

### Editing two fields
The view model replaces the single `editingNodeID: Int64?` with an edit target that names the
field:
```swift
enum NodeField { case heading, content }
struct NodeEdit: Equatable { var nodeID: Int64; var field: NodeField }
@Published var editing: NodeEdit?
```
- `beginEdit(_ nodeID:)` → `editing = NodeEdit(nodeID, .heading)` (used by Tab/Return on a new
  node, and double-click on the heading).
- `beginEditContent(_ nodeID:)` → `editing = NodeEdit(nodeID, .content)` (double-click the content
  area / the "Add note…" placeholder).
- `commitHeading(_:)` writes `text` (the existing `store.updateNodeText`); `commitContent(_:)`
  writes `content` (new `store.updateNodeContent(id:content:)`); `cancelEdit()` clears.
- `NodeView` shows the heading `TextField` when `editing == (nid,.heading)` and the content
  `TextField`/`TextEditor` when `editing == (nid,.content)`. The canvas's focus/`onKeyPress`
  handlers gate on `vm.editing == nil` (replacing the `editingNodeID == nil` checks).

Tab/Return still create a child/sibling and begin editing its **heading**.

### Sizing (`MindmapNodeSizing`)
Extend the estimator to reflect the new layout and collapsed state:
```swift
static func size(heading: String, content: String, chipCount: Int, collapsed: Bool) -> CGSize
```
- Collapsed → heading height only.
- Expanded → heading + estimated content lines (when non-empty) + `chipCount · chipHeight`.
The view model passes `collapsed`/`content` through when building `sizes` in `relayout()`/`tidy()`.

### Store
Add `updateNodeContent(id:content:)` (mirrors `updateNodeText`). `tree(forMap:)`/snapshot already
select `*`/all columns, so `content` flows through `MindmapNode` automatically; **snapshot/restore
must include `content` in its explicit-id INSERT** (add the column to that INSERT statement).

## 4. Testing

**Core (`swift test`):**
- `MindmapStoreTests`: `v11` `content` round-trip via `updateNodeContent` + `tree(forMap:)`;
  snapshot→restore preserves `content` (extend the existing snapshot test or add one).
- `MindmapNodeSizingTests`: collapsed size == heading-only height; expanded grows with content
  lines and chips; width fixed.

**App (manual, macOS):** Tab spawns a child just beside its parent at ~100% zoom on a fresh map;
dragging a node drags its parent/child connector lines with it (no lag, no flicker); a node with
content/papers/children collapses to just its heading (▶) and expands back (▾); double-click
heading edits the title, double-click the body edits the content; relaunch persists content +
collapsed state.

## 5. Files touched (informs the plan)

- **Core:** `Models/Mindmap.swift` (`MindmapNode.content` + CodingKey), `Store/LibraryStore.swift`
  (`v11-mindmap-content` migration), `Store/MindmapStore.swift` (`updateNodeContent`; add
  `content` to snapshot/restore INSERT), `Services/MindmapNodeSizing.swift` (new `size(...)`
  signature); tests for store + sizing.
- **App:** `Mindmap/MindmapViewModel.swift` (`seedGapX`/`seedGapY`, `fit` zoom cap, `editing`
  edit-target + content edit methods, `canCollapse`, size calls, live-drag center in the move
  gesture wiring), `Mindmap/NodeView.swift` (heading/content layout, content editing, chevron
  visibility, report live center every `.onChanged`, `NodeDragInfo` change), `Mindmap/MindmapCanvas.swift`
  (connectors use live drag center; key handlers gate on `vm.editing`).

## 6. Risks / notes

- **Edge-follow re-renders the connectors `Canvas` each drag frame.** This is one `Canvas` view,
  not the nodes; it's the intended, cheap path (the flicker we removed came from republishing the
  *model*/all nodes, which we still don't do).
- **`MindmapNodeSizing` signature change** ripples to every caller (`relayout`, `tidy`, the canvas
  cull, NodeView's `size`); the plan updates all of them in one task.
- **`v11` is additive/idempotent** (one `ALTER … ADD COLUMN … DEFAULT ''`); existing nodes get
  empty content.
- **Snapshot/restore** must carry `content` or an undo would blank out notes — explicitly covered
  in the store task + test.
</content>
