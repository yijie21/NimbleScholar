# Design — Mindmap View Mode (connect papers to research ideas)

Date: 2026-06-17
Status: Approved (pending spec review)

## Overview

A new **4th library view mode** ("Mindmap") for building idea graphs that connect papers.
A research idea (e.g. "new method needs paper A as the backbone, paper B as the dataset")
becomes a mindmap: text nodes you author, connected by free-form edges, with papers
**attached** to nodes by dragging them off a narrow searchable paper shelf.

Decisions (from brainstorming):
- **Multiple named maps** — each research idea is its own mindmap, picked/created from a list.
  A paper can appear in many maps; a node can hold many papers.
- **Text nodes; papers attach to them** (shown as chips), not papers-as-nodes.
- **Lives as the 4th view mode**, beside Three-pane / Gallery / Rows.
- **Native SwiftUI canvas** (not an embedded JS library) — borrows proven infinite-canvas
  patterns (single zoom/offset transform + viewport culling) but keeps drag-and-drop and
  state in one native world. This is the lowest crash/lag path and the headline interaction
  (dragging a native card onto a node) is a single native drop instead of an AppKit↔JS bridge.
- **Free-form graph** — any node can connect to any other by dragging an edge.
- **Free node positioning** — drag nodes anywhere; positions are saved. No auto-layout.
- **Click an attached paper → open it in the reader** (switches to three-pane reading,
  consistent with how Gallery/Rows "Read" already snaps to the reader).

Non-goals (YAGNI for v1): auto-layout, node coloring/styling, edge labels, map export,
canvas multi-select.

## 1. Data model — Core migration `v9-mindmap` (additive, idempotent)

Registered in the single `LibraryStore.migrator` (same pattern as `v1`…`v8-important`).
Four tables; FK `onDelete: .cascade` throughout gives correctness for free.

```
mindmaps           id, name TEXT, zoom DOUBLE DEFAULT 1, offset_x DOUBLE DEFAULT 0,
                   offset_y DOUBLE DEFAULT 0, created_at INT, updated_at INT
mindmap_nodes      id, mindmap_id → mindmaps(id) CASCADE, text TEXT DEFAULT '',
                   x DOUBLE DEFAULT 0, y DOUBLE DEFAULT 0, created_at INT, updated_at INT
mindmap_edges      id, mindmap_id → mindmaps(id) CASCADE,
                   from_node_id → mindmap_nodes(id) CASCADE,
                   to_node_id   → mindmap_nodes(id) CASCADE
mindmap_node_papers  node_id  → mindmap_nodes(id) CASCADE,
                     paper_id → papers(id)        CASCADE,
                     PRIMARY KEY (node_id, paper_id)
```

Cascade consequences (relied upon, no manual cleanup):
- Delete a **node** → its edges (both directions) and its paper links vanish.
- Delete a **map** → all its nodes/edges/links vanish.
- Delete a **paper from the library** → it detaches from every node automatically.

`zoom`/`offset_*` on `mindmaps` persist the last viewport so a map reopens where you left it.

### Core models (`Core/Models/`)
`Mindmap`, `MindmapNode`, `MindmapEdge` — Codable GRDB records (`FetchableRecord`,
`MutablePersistableRecord`) following `Paper.swift` camelCase↔snake_case mapping
(`mindmapID = "mindmap_id"`, `fromNodeID = "from_node_id"`, etc.). The node↔paper join is
handled in the store via SQL (no dedicated model needed beyond a `(nodeID, paperID)` pair).

## 2. Core store layer (`Core/Store/MindmapStore.swift`, unit-tested)

A new `MindmapStore` wrapping the **same** `dbQueue` as `LibraryStore` (so the migration
stays in the one migrator, but mindmap CRUD doesn't bloat `LibraryStore`). Constructed from
`LibraryStore`'s queue. Methods:

- Maps: `mindmaps() -> [Mindmap]`, `createMindmap(name:) -> Mindmap`,
  `renameMindmap(id:name:)`, `deleteMindmap(id:)`, `saveViewport(mapID:zoom:offsetX:offsetY:)`.
- Nodes: `createNode(mapID:text:x:y:) -> MindmapNode`, `updateNodeText(id:text:)`,
  `moveNode(id:x:y:)`, `deleteNode(id:)`.
- Edges: `addEdge(mapID:from:to:) -> MindmapEdge` (no-op/dedupe if it already exists or
  from == to), `deleteEdge(id:)`.
- Papers: `attachPaper(nodeID:paperID:)` (INSERT OR IGNORE), `detachPaper(nodeID:paperID:)`.
- **`graph(forMap:) -> MindmapGraph`** — loads nodes, edges, and node→paper id links in a
  few queries (no N+1) into a struct: `nodes: [MindmapNode]`, `edges: [MindmapEdge]`,
  `paperIDsByNode: [Int64: [Int64]]`. The view model joins paper ids against the already
  in-memory library papers for display (no extra paper fetch per chip).

### Pure helper (`Core/Services/CanvasTransform.swift`, unit-tested)
Lives in Core (so `swift test` covers it). `CanvasTransform` — value type holding `zoom`
and `pan` (`CGSize`); methods
`screen(from canvasPoint:) -> CGPoint`, `canvas(from screenPoint:) -> CGPoint`,
`isVisible(canvasRect:in viewportRect:) -> Bool` (culling), and `clampedZoom(...)`. Keeping
the coordinate math in a pure struct makes pan/zoom/hit-test/culling testable without UI.

## 3. App UI (`NimbleScholar/Mindmap/`)

Add `case mindmap` to `LibraryViewMode` (symbol e.g. `"brain"`), so it appears in the
existing principal segmented picker in `LibraryContentView`. In `detail`, route
`.mindmap` → `MindmapView()`. While reading (`readingPaperID != nil`) the layout still
forces three-pane (the reader needs its detail pane), exactly as today.

Detail-pane layout in mindmap mode:

```
┌ PaperShelf ┬──────────── Canvas area ─────────────┐
│ [ search 🔍]│ [ Map ▾   + New   Rename   Delete ]  │  ← MapBar
│ ▸ Card      │                                      │
│ ▸ Card      │        infinite canvas               │
│ ▾ Card(exp) │   nodes • edges • paper chips        │
│ ▸ Card      │                                      │
└─────────────┴──────────────────────────────────────┘
```

### `MindmapViewModel` (`@MainActor ObservableObject`)
Owns: list of maps, the **active map id** (persisted in `UserDefaults`, default = most
recent), the loaded `MindmapGraph` for the active map, and the live `CanvasTransform`.
Mutations update in-memory state **and** write through to `MindmapStore`; node-position
writes are **debounced** (same shape as `ReaderViewModel.scheduleSave`, ~0.4s) so dragging
doesn't hammer SQLite. Reads `AppEnvironment.shared` for the store and the library papers.

### `PaperShelf.swift` (narrow, ~240pt)
- A **search field on top** → `store.searchPapers(query:tag:)` (FTS, debounced ~0.25s),
  further narrowed by the left sidebar's current scope/tag (reuses `LibraryViewModel`'s
  scope). Empty query shows the current scope's papers.
- A `ScrollView` of `ShelfCard`s. Each defaults **collapsed** (title, 1–2 lines, + small
  thumbnail); a chevron toggles **expanded** (thumbnail + authors + year + tags). Expanded
  state is per-card, kept in-memory in the shelf (not persisted).
- Each card is `.draggable(PaperRef(id:))`.
- Thumbnails reuse the existing two-level `ThumbnailCache`.

### `MapBar.swift`
Active-map picker (`Menu` of maps), **+ New** (prompts a name), **Rename**, **Delete**
(confirm). Switching maps loads that map's graph + restores its viewport.

### `MindmapCanvas.swift`
- Holds `zoom` + `panOffset`. Background drag = pan; scroll-wheel / pinch = zoom (clamped
  0.25–2.5). Double-click empty space = create a node at that canvas point (enters text edit).
- **Edges**: one `Canvas` pass drawing a `Path` per edge between node anchor points (in the
  transformed space). Not N SwiftUI views.
- **Nodes**: `ForEach` over **culled** nodes (only those whose transformed frame intersects
  the viewport + margin), each placed via `.position` using `CanvasTransform.screen(from:)`.
- **Drop destination**: a paper dropped on **empty canvas** creates a new node at the drop
  point pre-attached with that paper (drop location → canvas coords via the inverse
  transform); dropping on a node is handled by the node (below).
- Persists the viewport (debounced) to the active map.

### `NodeView.swift`
- Rounded card: `Text(node.text)` → `TextField/TextEditor` on double-click (commit on
  blur/Return → `updateNodeText`).
- A wrap of attached **paper chips** (`NodePaperChip`).
- **Drag to move** the node → updates `x/y` in memory, debounced persist.
- **Edge port** (small handle): drag from it to another node → `addEdge`. Edge tap → delete
  (with a small affordance / context menu).
- `.dropDestination(for: PaperRef.self)` → `attachPaper(nodeID:paperID:)`.

### `NodePaperChip.swift`
Compact: truncated title + remove (×, → `detachPaper`). **Click → `vm.openReader(paper)`**
on the `LibraryViewModel`, which sets `readingPaperID` and (per existing
`LibraryContentView` logic) snaps to the three-pane reader. (Returning via Back lands on the
three-pane detail; the user re-selects Mindmap mode to continue — acceptable for v1.)

## 4. Drag & drop

One `Transferable` payload, `PaperRef` (wraps the paper's `Int64` id, e.g. via
`CodableRepresentation`). Shelf card `.draggable(PaperRef(id:))`; `NodeView` and the canvas
background are `.dropDestination(for: PaperRef.self)`. Drop-on-node attaches; drop-on-canvas
creates a node pre-attached. No web bridge, no JSON round-trip across runtimes.

## 5. Performance / "no crash, no lag"

- The active map's graph is loaded **once** into the view model; every edit mutates memory +
  writes through. No per-frame DB reads.
- Node-drag + viewport persistence are **debounced** before hitting SQLite.
- Edges = a single `Canvas` draw; nodes are **viewport-culled**; zoom is **clamped** to avoid
  degenerate transforms.
- Shelf thumbnails reuse `ThumbnailCache` (memory + disk) so scrolling stays smooth.
- All mindmap writes go through GRDB's serialized queue (same safety as the rest of the app).

## 6. Testing

**Unit (`swift test`) — `MindmapStoreTests`:**
- create/rename/delete map; create node; add/dedupe edge (reject self-loop and duplicates);
  attach/detach paper (INSERT OR IGNORE idempotent).
- `graph(forMap:)` returns the correct nodes/edges/`paperIDsByNode` shape.
- Cascades: deleting a node removes its edges (both directions) + paper links; deleting a map
  removes all of its rows; deleting a **paper** (via `LibraryStore.deletePaper`) removes its
  `mindmap_node_papers` links.

**Unit — `CanvasTransformTests`:** `screen(from:)`/`canvas(from:)` round-trip at several
zoom/pan values; `isVisible` culling for on/off-screen rects; zoom clamping.

**Manual (running app):** switch to Mindmap mode; create a map; double-click to add nodes;
edit text; drag nodes (smooth, positions persist across relaunch); connect two nodes; drag a
shelf card onto a node (attaches) and onto empty canvas (creates a node); expand/collapse and
search shelf cards; click a chip → opens the reader; delete a node/paper and confirm links
clean up; reopen a map and confirm the viewport restored.

## 7. Risks / notes

- The canvas is a custom native view; pan/zoom/culling are ~hundreds of lines but follow a
  single, well-understood transform — the testable `CanvasTransform` de-risks the math.
- Edge creation via an edge-port drag and edge deletion need clear affordances; if the port
  drag proves fiddly in practice, a fallback is "select node A, ⌥-click node B to connect."
- Opening a paper from a chip leaves mindmap mode for the reader (by design, reusing existing
  navigation); remembering "return to Mindmap after Back" is a possible later polish, out of
  scope for v1.
</content>
</invoke>
