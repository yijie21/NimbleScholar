# Design — Mindmap Free Positioning

Date: 2026-06-17
Status: Approved (pending spec review)
Builds on the auto-layout tree redesign (`2026-06-17-mindmap-redesign-design.md`),
branch `feat/mindmap`.

## Overview

The auto-layout tree pins every node to a computed position, so a node "is fixed at the
top-left corner" and can't be moved where the user wants. This change makes node **positions
free**: every node is draggable anywhere and its position is saved. All the tree mechanics
from the redesign stay — Tab=child, Return=sibling, arrows=navigate, parent→child edges,
collapse/expand, undo/redo, paper attachment.

Decisions (from brainstorming):
- **Free positioning.** Nodes store their own `x`/`y`; `TreeLayout` is used only by an
  on-demand **Tidy** action, not on every render.
- **One drag, disambiguated by drop target:** drop a node **onto another node** = re-parent
  (and keep it where dropped); drop on **empty space** = free-move. No modifier key.
- **The root is draggable too** (move only — it can't be re-parented).
- **Fit-on-load** centers the tree (fixes the "crammed in the top-left" complaint).

Non-goals (YAGNI): snap-to-grid, alignment guides, multi-select drag, per-node manual-vs-auto
flags, auto-layout on every edit.

## What changes vs. what stays

**Stays:** the 4th view mode + `MindmapView` shell, `MapBar`, `PaperShelf`, `CanvasToolbar`
(gains one button), `MindmapCanvas` two-layer rendering, the tree data model
(`parent_id`/`sort_order`/`collapsed`), Tab/Return/arrows/Space/Delete/undo, `CanvasTransform`,
`TreeLayout` (re-purposed for Tidy), paper chips.

**Changes:** `MindmapViewModel` (layout from stored positions; seed new nodes; move/reparent
on drop; `tidy()`; fit-on-load), `NodeView` (drag commits move-or-reparent; root draggable),
`MindmapStore` (un-dormant `moveNode`; add a batch `setPositions`).

**No schema change:** `mindmap_nodes.x`/`y` already exist (`v9`); we simply write/read them
again. The redesign's "x/y dormant" note is reversed.

## 1. Core store (`MindmapStore`)

- **Un-dormant `moveNode(id:x:y:)`** (already present) — writes a node's `x`/`y` + `updated_at`.
  It will now be called by the VM on a free-drag release.
- **Add `setPositions(mapID:positions:)`** — one transaction writing `x`/`y` for many nodes
  (`positions: [Int64: CGPoint]`), used by Tidy:
  ```swift
  public func setPositions(mapID: Int64, positions: [Int64: CGPoint]) throws
  ```
  (Writes only nodes belonging to `mapID`; stamps `updated_at`.)
- `addChild`/`addSibling` are unchanged in the store (they still default `x`/`y` to 0). The
  **seed position is set by the VM** right after creation (it knows the parent's position),
  via `moveNode`. This keeps the store's tree ops position-agnostic.

## 2. View model (`MindmapViewModel`)

- **`relayout()` reads stored positions** instead of calling `TreeLayout`:
  ```swift
  layout = Dictionary(uniqueKeysWithValues:
      tree.nodes.compactMap { n in n.id.map { ($0, CGPoint(x: n.x, y: n.y)) } })
  ```
  `sizes` is still computed (for culling, hit-testing, the drop indicator). `TreeLayout` is no
  longer called here.
- **Seed new nodes near their parent.** After `store.addChild`/`addSibling` returns the new
  node, the VM computes a seed and persists it before reload:
  - child: `parent.position + (levelGapX + nodeWidth, sibling-index · (rowGap))`
  - sibling: `existing-sibling.position + (0, rowGap)` (just below it)
  Then `store.moveNode(newID, x:, y:)`, then `reloadTree()`. (`levelGapX`/`rowGap` are small
  constants; node width from `MindmapNodeSizing.width`.) New nodes thus appear beside/under
  their parent, never at the origin.
- **`move(_ nodeID:to canvasPoint:)`** — free-move on drop: `store.moveNode(...)` then update
  `layout` (and reload). Single write on release (no per-frame writes → no flicker).
- **`reparent(_:to:index:)`** gains an optional drop position: after `store.setParent(...)`,
  also `store.moveNode(nodeID, x:, y:)` to keep the node where the user dropped it.
  Signature: `reparent(_ nodeID: Int64, to newParentID: Int64, index: Int, at point: CGPoint)`.
- **`tidy()`** — `let pos = TreeLayout.positions(rootID:childrenByParent:collapsed:sizeOf:)`;
  `store.setPositions(mapID:, positions: pos)`; `reloadTree()`. Pushes an undo snapshot first
  (it's a structural-ish change). Re-arranges the whole map to a clean tree.
- **`fit(in:)`** already exists; call it from `loadActive()` once a viewport size is known so a
  map opens centered. (Implementation: `MindmapView`/`MindmapCanvas` calls `vm.fit(in:)` on
  first appearance of the canvas with its `GeometryReader` size; a one-shot guard prevents
  re-fitting on every appearance.)
- **`dropTarget(forDragged:at:)`** is unchanged (returns the node under a point, excluding
  self/descendant). It now also serves the "is this a re-parent or a move?" decision.

## 3. Node drag (`NodeView`)

The existing reparent drag becomes a **move-or-reparent** drag:
- Still uses the local `@GestureState dragOffset` for a smooth visual move (no model write
  during `.onChanged`); `.onChanged` still publishes `dragInfo` so the overlay can show a
  drop indicator **only when hovering a valid re-parent target**.
- `.onEnded`, in canvas coordinates `p = transform.canvas(from: value.location)`:
  - if `vm.dropTarget(forDragged: nodeID, at: p)` returns a target **and** `nodeID != rootID`
    → `vm.reparent(nodeID, to: target.parentID, index: target.index, at: p)`
  - else → `vm.move(nodeID, to: p)` (free position; applies to the root too)
- **Root is now draggable** for moving (the current `guard nodeID != vm.rootID` in the drag is
  removed; root simply never reparents because the `else` branch moves it).

The drop indicator (overlay) still appears only over a valid re-parent target, signaling
"release here to re-parent" vs. "release on empty space to place."

## 4. UI (`MindmapView` / `CanvasToolbar`)

Add a **Tidy** button (e.g. `arrow.up.arrow.down.square` / "wand.and.stars") to
`CanvasToolbar` that calls `vm.tidy()`. Everything else in the toolbar and canvas is unchanged.

## 5. Fix: open centered

`loadActive()` no longer leaves the view at the stored viewport for a tree that lives near the
origin. On the canvas's first appearance, `vm.fit(in: size)` frames all nodes. A new map's root
is seeded at `(0, 0)` and `fit` centers it. (The persisted viewport still applies on later
opens; the one-shot fit runs when there is content and no meaningful saved viewport, or always
on first appearance — see plan for the exact guard.)

## 6. Testing

**Core (`swift test`):**
- `MindmapStoreTests`: `setPositions` writes `x`/`y` for the given nodes and leaves others
  untouched; `moveNode` round-trip (x/y persisted) — a focused test since these now matter.

**App (manual, macOS):** drag a node to empty space → it stays there (smooth, no flicker);
drag a node onto another → re-parents and stays at the drop point; drag the root → it moves;
**Tab** adds a child beside its parent (not at the corner); **Tidy** re-arranges the whole tree;
relaunch → positions persist; opening a map shows the tree centered, not in the corner.

## 7. Risks / notes

- **Edges during a drag** still read committed positions, so the dragged node's edges snap on
  release (unchanged from the redesign; acceptable).
- **`fit`-on-load guard:** must run once per map open (not every SwiftUI re-appearance) to avoid
  fighting the user's pan/zoom. The plan pins the exact mechanism (a `@State didFit` keyed by
  `activeMapID`).
- **Seeding overlap:** two children seeded by sibling index can still overlap a hand-moved node;
  that's fine — the user drags or hits Tidy. v1 doesn't do collision avoidance on seed.
- **`TreeLayout` is retained** (now Tidy-only) and its tests still pass; no Core layout code is
  deleted.
</content>
