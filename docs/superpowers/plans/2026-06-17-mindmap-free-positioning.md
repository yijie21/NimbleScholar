# Mindmap Free Positioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make mindmap node positions free — every node is draggable anywhere and its position is saved — while keeping all the tree mechanics (Tab/Return, edges, collapse, undo); `TreeLayout` becomes an on-demand "Tidy" action and the map opens centered.

**Architecture:** Nodes store their own `x`/`y` (the existing `v9` columns, no migration). The view model's `layout` is read from those stored positions instead of recomputed by `TreeLayout` each render. A node drag commits on release: dropped onto another node → re-parent (and keep it where dropped); dropped on empty space → free-move. A "Tidy" button writes `TreeLayout` positions back to the nodes; `fit(in:)` runs once per map open to center the tree.

**Tech Stack:** Swift 5.9 / SwiftUI (macOS 14), GRDB 6.27, CoreGraphics. No new dependencies.

## Global Constraints

- Platform floor **macOS 14.0**, Swift tools **5.9**. **No new dependencies. No schema migration** (reuses `mindmap_nodes.x`/`y` from `v9`).
- The flicker invariant stays: **no model write during a drag's `.onChanged`** — drag uses the local `@GestureState` offset and commits one write (`move` or `reparent`) on `.onEnded`.
- **No Swift toolchain in this environment** — implementers WRITE tests but CANNOT run them; build/`swift test` happen on macOS. Do not fabricate test output; state execution is deferred.
- Core tests: `cd NimbleScholarCore && swift test`. App build: `bash scripts/mac_bootstrap.sh full run` (macOS only).
- Builds on branch `feat/mindmap` (the auto-layout tree redesign, committed, not merged).

## File Structure

**Core (modified):**
- `NimbleScholarCore/Sources/NimbleScholarCore/Store/MindmapStore.swift` — `import CoreGraphics`; add `setPositions(mapID:positions:)` (the existing `moveNode` is reused).
- `NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapStoreTests.swift` — `import CoreGraphics`; add a move/setPositions test.

**App (modified):**
- `NimbleScholar/Mindmap/MindmapViewModel.swift` — `relayout()` reads stored positions; seed new nodes; `move(_:to:)`; `reparent(...at:)`; `tidy()`.
- `NimbleScholar/Mindmap/NodeView.swift` — drag commits move-or-reparent; root draggable.
- `NimbleScholar/Mindmap/MindmapCanvas.swift` — fit-on-load (once per map).
- `NimbleScholar/Mindmap/MindmapView.swift` — Tidy button in `CanvasToolbar`.
- `README.md`, `docs/ARCHITECTURE.md`, `CHANGELOG.md` — docs.

---

## Task 1: Core — `setPositions` batch write (+ move/position test)

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/MindmapStore.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapStoreTests.swift`

**Interfaces:**
- Consumes: existing `moveNode(id:x:y:)`, `addChild`, `ensureRoot`, `tree(forMap:)`.
- Produces: `setPositions(mapID:positions:)` where `positions: [Int64: CGPoint]`.

- [ ] **Step 1: Write the failing test**

In `MindmapStoreTests.swift`, add `import CoreGraphics` at the top (after the existing imports), then append this test inside the class:

```swift
    func testMoveNodeAndSetPositions() throws {
        let (_, store) = try makeStores()
        let m = try store.createMindmap(name: "M")
        let root = try store.ensureRoot(mapID: m.id!, title: "M")
        let a = try store.addChild(parentID: root.id!, text: "A")
        let b = try store.addChild(parentID: root.id!, text: "B")

        try store.moveNode(id: a.id!, x: 12.5, y: -7.5)
        let aMoved = try store.tree(forMap: m.id!).nodes.first { $0.id == a.id! }!
        XCTAssertEqual(aMoved.x, 12.5, accuracy: 0.0001)
        XCTAssertEqual(aMoved.y, -7.5, accuracy: 0.0001)

        try store.setPositions(mapID: m.id!, positions: [root.id!: CGPoint(x: 1, y: 2),
                                                         b.id!: CGPoint(x: 3, y: 4)])
        let tree = try store.tree(forMap: m.id!)
        let r = tree.nodes.first { $0.id == root.id! }!
        let bb = tree.nodes.first { $0.id == b.id! }!
        XCTAssertEqual(r.x, 1, accuracy: 0.0001); XCTAssertEqual(r.y, 2, accuracy: 0.0001)
        XCTAssertEqual(bb.x, 3, accuracy: 0.0001); XCTAssertEqual(bb.y, 4, accuracy: 0.0001)
        // a was not in the setPositions map → unchanged
        let aa = tree.nodes.first { $0.id == a.id! }!
        XCTAssertEqual(aa.x, 12.5, accuracy: 0.0001)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter testMoveNodeAndSetPositions`
Expected: FAIL — `value of type 'MindmapStore' has no member 'setPositions'`.

- [ ] **Step 3: Implement `setPositions`**

In `MindmapStore.swift`, change the top imports from:

```swift
import Foundation
import GRDB
```

to:

```swift
import Foundation
import CoreGraphics
import GRDB
```

Then add this method inside the `// MARK: - Tree` section (e.g. right after `setCollapsed`):

```swift
    /// Write x/y for many nodes in one transaction (used by Tidy). Only nodes belonging to
    /// `mapID` are touched.
    public func setPositions(mapID: Int64, positions: [Int64: CGPoint]) throws {
        let ts = now()
        try dbQueue.write { db in
            for (id, p) in positions {
                try db.execute(sql: "UPDATE mindmap_nodes SET x = ?, y = ?, updated_at = ? WHERE id = ? AND mindmap_id = ?",
                               arguments: [Double(p.x), Double(p.y), ts, id, mapID])
            }
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter testMoveNodeAndSetPositions`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Store/MindmapStore.swift \
        NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapStoreTests.swift
git commit -m "feat(mindmap): setPositions batch write for free positioning + Tidy"
```

---

## Task 2: View model — stored-position layout, seeding, move, reparent-at, tidy

**Files:**
- Modify: `NimbleScholar/Mindmap/MindmapViewModel.swift`

**Interfaces:**
- Consumes: `store.setPositions(mapID:positions:)` (Task 1), existing `store.moveNode`, `store.setParent`, `TreeLayout.positions`, `MindmapNodeSizing.size`.
- Produces (consumed by Tasks 3–4): `move(_ nodeID: Int64, to point: CGPoint)`; `reparent(_ nodeID: Int64, to newParentID: Int64, index: Int, at point: CGPoint)` (NOTE the new `at:` parameter — the old 3-arg `reparent` is replaced); `tidy()`. `layout` now reflects stored `x`/`y`.

> NOTE: This task changes `reparent`'s signature, so `NodeView`'s current call site stops compiling until Task 3. That is expected — implement Tasks 2 and 3 back-to-back.

- [ ] **Step 1: Replace `relayout()` to read stored positions**

In `MindmapViewModel.swift`, replace the entire `relayout()` method:

```swift
    private func relayout() {
        var sz: [Int64: CGSize] = [:]
        for n in tree.nodes {
            guard let nid = n.id else { continue }
            sz[nid] = MindmapNodeSizing.size(text: n.text, chipCount: tree.paperIDsByNode[nid]?.count ?? 0)
        }
        sizes = sz
        layout = Dictionary(uniqueKeysWithValues:
            tree.nodes.compactMap { n in n.id.map { ($0, CGPoint(x: n.x, y: n.y)) } })
    }
```

- [ ] **Step 2: Add seeding constants + helper, and seed new nodes**

In `MindmapViewModel.swift`, add these stored constants near the other `private let`s (e.g. just below `private let activeKey = "activeMindmapID"`):

```swift
    private let seedGapX: CGFloat = 220   // place a child this far right of its parent (node width + gap)
    private let seedGapY: CGFloat = 70    // vertical spacing between seeded siblings
```

Add this helper in the `// MARK: Structural ops` section (e.g. just above `addChild`):

```swift
    /// Seed position for a freshly created child of `parentID` (beside the parent, stacked by index).
    private func seedChildPosition(parentID: Int64, siblingIndex: Int) -> CGPoint {
        let p = layout[parentID] ?? .zero
        return CGPoint(x: p.x + seedGapX, y: p.y + CGFloat(siblingIndex) * seedGapY)
    }
```

Replace `addChild(to:)`:

```swift
    func addChild(to parentID: Int64) {
        pushUndo()
        let index = tree.children(of: parentID).count   // new child's 0-based index (pre-insert count)
        guard let n = try? store.addChild(parentID: parentID, text: ""), let nid = n.id else { return }
        let seed = seedChildPosition(parentID: parentID, siblingIndex: index)
        try? store.moveNode(id: nid, x: Double(seed.x), y: Double(seed.y))
        reloadTree(); selectedNodeID = nid; editingNodeID = nid
    }
```

Replace `addSibling(of:)`:

```swift
    func addSibling(of nodeID: Int64) {
        if nodeID == tree.rootID { addChild(to: nodeID); return }   // root has no sibling
        pushUndo()
        guard let n = try? store.addSibling(of: nodeID, text: ""), let nid = n.id else { return }
        let ref = layout[nodeID] ?? .zero
        try? store.moveNode(id: nid, x: Double(ref.x), y: Double(ref.y + seedGapY))
        reloadTree(); selectedNodeID = nid; editingNodeID = nid
    }
```

- [ ] **Step 3: Replace `reparent` (add drop point) and add `move` + `tidy`**

Replace the `reparent(_:to:index:)` method:

```swift
    func reparent(_ nodeID: Int64, to newParentID: Int64, index: Int, at point: CGPoint) {
        guard nodeID != tree.rootID, nodeID != newParentID, !isDescendant(newParentID, of: nodeID) else { return }
        pushUndo()
        try? store.setParent(nodeID: nodeID, newParentID: newParentID, index: index)
        try? store.moveNode(id: nodeID, x: Double(point.x), y: Double(point.y))
        reloadTree(); selectedNodeID = nodeID
    }

    /// Free-move a node to a canvas point (drag released on empty space; root included).
    func move(_ nodeID: Int64, to point: CGPoint) {
        pushUndo()
        try? store.moveNode(id: nodeID, x: Double(point.x), y: Double(point.y))
        reloadTree(); selectedNodeID = nodeID
    }

    /// Re-arrange the whole map to a clean auto-layout, writing positions back to the nodes.
    func tidy() {
        guard let id = activeMapID, let root = tree.rootID else { return }
        var sz: [Int64: CGSize] = [:]
        for n in tree.nodes {
            guard let nid = n.id else { continue }
            sz[nid] = MindmapNodeSizing.size(text: n.text, chipCount: tree.paperIDsByNode[nid]?.count ?? 0)
        }
        let positions = TreeLayout.positions(rootID: root, childrenByParent: tree.childIDsByParent,
                                             collapsed: tree.collapsedSet, sizeOf: sz)
        pushUndo()
        try? store.setPositions(mapID: id, positions: positions)
        reloadTree()
    }
```

- [ ] **Step 4: Self-verify compile-correctness (no build)**

Confirm by reading: `relayout` no longer calls `TreeLayout` (only `tidy` does); `addChild`/`addSibling` seed via `store.moveNode`; `reparent` now takes `at point:` and persists the drop position; `move`/`tidy` exist; every `store.*` call matches a real `MindmapStore` signature (incl. `setPositions` from Task 1). `CGPoint`/`CGSize`/`CGFloat` are available (the file already `import CoreGraphics`). NodeView's old `reparent(_:to:index:)` call will not compile until Task 3 — expected.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholar/Mindmap/MindmapViewModel.swift
git commit -m "feat(mindmap): VM free positioning — stored layout, seeding, move, tidy"
```

---

## Task 3: Node drag — move-or-reparent, root draggable

**Files:**
- Modify: `NimbleScholar/Mindmap/NodeView.swift`

**Interfaces:**
- Consumes: `vm.layout`, `vm.transform`, `vm.rootID`, `vm.dropTarget(forDragged:at:)`, `vm.reparent(_:to:index:at:)`, `vm.move(_:to:)` (Task 2).
- Produces: nothing new (internal gesture change).

- [ ] **Step 1: Replace the drag gesture**

In `NodeView.swift`, replace the `reparentGesture` computed property (the `private var reparentGesture: some Gesture { ... }` block) with:

```swift
    /// Drag the node body to MOVE it, or to RE-PARENT it (when released over another node).
    /// Moves locally during the drag (no model write); commits move-or-reparent on release.
    private var moveOrReparentGesture: some Gesture {
        DragGesture(coordinateSpace: .named(coordSpace))
            .updating($dragOffset) { value, state, _ in state = value.translation }
            .onChanged { value in
                // Show the drop indicator only while hovering a valid re-parent target.
                let cursor = vm.transform.canvas(from: value.location)
                if nodeID != vm.rootID, vm.dropTarget(forDragged: nodeID, at: cursor) != nil {
                    dragInfo = NodeDragInfo(nodeID: nodeID, canvasPoint: cursor)
                } else {
                    dragInfo = nil
                }
            }
            .onEnded { value in
                defer { dragInfo = nil }
                let zoom = vm.transform.zoom
                let old = vm.layout[nodeID] ?? .zero
                // New position preserves the grab offset (move by the drag delta in canvas units).
                let dropPoint = CGPoint(x: old.x + value.translation.width / zoom,
                                        y: old.y + value.translation.height / zoom)
                let cursor = vm.transform.canvas(from: value.location)
                if nodeID != vm.rootID, let target = vm.dropTarget(forDragged: nodeID, at: cursor) {
                    vm.reparent(nodeID, to: target.parentID, index: target.index, at: dropPoint)
                } else {
                    vm.move(nodeID, to: dropPoint)
                }
            }
    }
```

- [ ] **Step 2: Update the gesture attachment**

In `NodeView.swift`, find the body modifier `.gesture(reparentGesture)` and change it to:

```swift
        .gesture(moveOrReparentGesture)
```

- [ ] **Step 3: Self-verify compile-correctness**

Confirm: the drag no longer bails for the root (root is draggable → its drop falls through to `vm.move`); `.onChanged` still does NO model mutation (only `dragInfo` + the `@GestureState` offset); `.onEnded` calls `vm.reparent(_:to:index:at:)` (4-arg, matches Task 2) when over a target else `vm.move(_:to:)`; `vm.layout[nodeID]` read is valid (published dict). No other references to `reparentGesture` remain.

- [ ] **Step 4: Commit**

```bash
git add NimbleScholar/Mindmap/NodeView.swift
git commit -m "feat(mindmap): node drag moves freely or re-parents on drop; root draggable"
```

---

## Task 4: Canvas fit-on-load + Tidy toolbar button

**Files:**
- Modify: `NimbleScholar/Mindmap/MindmapCanvas.swift`
- Modify: `NimbleScholar/Mindmap/MindmapView.swift`

**Interfaces:**
- Consumes: `vm.fit(in:)`, `vm.activeMapID`, `vm.layout`, `vm.tidy()`, `vm.rootID` (Task 2).

- [ ] **Step 1: Add fit-on-load to `MindmapCanvas`**

In `MindmapCanvas.swift`, add a state var alongside the other `@State` declarations (e.g. near `@State private var dragInfo`):

```swift
    @State private var didFitMapID: Int64?
```

Add this helper method to the `MindmapCanvas` struct (e.g. just below the `body`):

```swift
    /// Frame the tree once per map open (when its layout is ready), so a map doesn't open
    /// stuck in the top-left corner. Guarded so it never fights the user's pan/zoom afterward.
    private func fitIfNeeded(_ size: CGSize) {
        guard size.width > 0, let mapID = vm.activeMapID, !vm.layout.isEmpty, didFitMapID != mapID else { return }
        didFitMapID = mapID
        vm.fit(in: size)
    }
```

Then, inside the `GeometryReader { geo in ... }`, attach these two modifiers to the `ZStack` (next to the existing `.onChange(of: vm.editingNodeID)` modifier):

```swift
            .onChange(of: vm.activeMapID, initial: true) { _, _ in didFitMapID = nil; fitIfNeeded(geo.size) }
            .onChange(of: vm.layout) { _, _ in fitIfNeeded(geo.size) }
```

(The `activeMapID` change resets the guard on a map switch; the `layout` change re-attempts the fit once the new map's nodes are loaded. The guard makes it run exactly once per map and never during subsequent node drags.)

- [ ] **Step 2: Add the Tidy button to `CanvasToolbar`**

In `MindmapView.swift`, in the `CanvasToolbar` body's `HStack`, add a Tidy button immediately after the existing Collapse button:

```swift
            Button { vm.tidy() } label: { Label("Tidy", systemImage: "wand.and.stars") }
                .disabled(vm.rootID == nil)
```

- [ ] **Step 3: Build and verify the feature (macOS) — deferred to the user / Task 5**

This completes the feature; it should compile. The implementer cannot build (no toolchain). Build + manual verification is Task 5 / the user's macOS run.

- [ ] **Step 4: Self-verify compile-correctness**

Confirm: `fitIfNeeded` reads `geo.size` from the enclosing `GeometryReader`; `.onChange(of:initial:)` is the macOS 14 two-param form; `vm.layout` is `Equatable` (`[Int64: CGPoint]`) so `.onChange(of: vm.layout)` compiles; `vm.tidy()` and `vm.fit(in:)` exist (Task 2 / existing); the Tidy `Label`/`systemImage` is valid.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholar/Mindmap/MindmapCanvas.swift NimbleScholar/Mindmap/MindmapView.swift
git commit -m "feat(mindmap): fit-on-load centering + Tidy toolbar button"
```

---

## Task 5: Verification + docs

**Files:** `README.md`, `docs/ARCHITECTURE.md`, `CHANGELOG.md`

- [ ] **Step 1: Full Core test suite (macOS)**

Run: `cd NimbleScholarCore && swift test`
Expected: PASS — existing suites plus `testMoveNodeAndSetPositions`.

- [ ] **Step 2: Build + manual walkthrough (macOS)**

Run: `bash scripts/mac_bootstrap.sh full run`, switch to Mindmap, and verify:
1. A map opens **centered** (root not jammed in the corner).
2. **Drag a node to empty space** → it stays there, smooth, **no flicker**.
3. **Drag a node onto another node** → it re-parents (drop indicator showed the target) and stays at the drop point; dropping onto its own descendant does nothing.
4. **Drag the root** → it moves freely.
5. **Tab** adds a child **beside its parent** (not at the corner); **Return** adds a sibling just below.
6. **Tidy** re-arranges the whole tree into a clean layout.
7. **⌘Z** undoes a move / reparent / tidy; quit & relaunch → positions persist.
8. Arrows/Space/Delete/collapse, paper attach + chip-open, pan/zoom/Fit still work.

- [ ] **Step 3: Update docs**

In `README.md`, update the **Mindmap** subsection: nodes are now **draggable anywhere** (positions saved); **drag a node onto another to re-parent**, drop on empty space to move; new nodes appear **beside their parent**; a **Tidy** button auto-arranges the tree; the map **opens centered**. (Keep the Tab/Return/arrows/Space/Delete/undo lines.)

In `docs/ARCHITECTURE.md`, update the `Core/Services/TreeLayout.swift` row to note it now drives the **Tidy** action (positions are stored on the nodes again, not recomputed each render), and adjust the data-model note that said positions are "never persisted" — they are persisted again (the `v10` columns are unchanged; `x`/`y` from `v9` are live).

In `CHANGELOG.md`, add a short entry (dated 2026-06-17) under the current top milestone (or a new milestone): mindmap nodes are now **freely draggable** (positions persisted); one drag = move (drop on empty) or re-parent (drop on a node); **Tidy** button re-runs the auto-layout; maps **open centered**.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/ARCHITECTURE.md CHANGELOG.md
git commit -m "docs(mindmap): document free positioning + Tidy"
```

---

## Notes for the implementer

- **Build order:** Tasks 2 and 3 are one compile unit — Task 2 changes `reparent`'s signature (adds `at:`), which breaks `NodeView`'s call until Task 3. Implement them back-to-back; the app compiles again at the end of Task 3 (Task 4 then adds fit + Tidy). Core Task 1 is additive and compiles/tests on its own.
- **Flicker invariant (unchanged):** never mutate the model in the drag `.onChanged` — only the local `@GestureState` offset + the `dragInfo` binding. The single `move`/`reparent` write happens in `.onEnded`.
- **`TreeLayout` is retained**, now invoked only by `tidy()`. Its tests still pass; do not delete it.
- **No migration:** `mindmap_nodes.x`/`y` already exist; the tree code writes them again. Do not add a migration.
- **Grab offset:** the drag commits `old position + (translation / zoom)`, so a node moves by the drag delta rather than snapping its center to the cursor; the cursor is used only to detect a re-parent target.
</content>
