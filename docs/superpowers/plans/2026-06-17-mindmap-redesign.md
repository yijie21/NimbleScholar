# Mindmap Redesign (Auto-Layout Tree) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the free-form mindmap canvas with a classic auto-layout logical tree (Tab=child, Enter=sibling, arrows=navigate, drag=re-parent, collapse/expand, undo/redo), which both adds real mindmap behavior and removes the drag flicker by persisting structure instead of per-node coordinates.

**Architecture:** Tree structure lives in `mindmap_nodes.parent_id`/`sort_order`/`collapsed` (new `v10-mindmap-tree` migration); a pure `TreeLayout` in Core computes positions from structure (never persisted). The app rewrites `MindmapViewModel` (tree state + selection + keyboard ops + snapshot undo), `NodeView` (inline edit + collapse + local-offset drag-to-reparent), and `MindmapCanvas` (two-layer render: committed edges/nodes + interactive overlay). Paper attachment is unchanged.

**Tech Stack:** Swift 5.9 / SwiftUI (macOS 14), GRDB 6.27, SwiftPM, CoreGraphics. No new dependencies.

## Global Constraints

- Platform floor **macOS 14.0**, Swift tools **5.9**. **No new dependencies.**
- New migration named exactly **`v10-mindmap-tree`**, additive/idempotent, registered after `v9-mindmap` and before `return m` in `LibraryStore.migrator`.
- Core models map camelCase→snake_case via `CodingKeys` exactly like `Paper.swift`/the existing `MindmapNode`.
- FK `onDelete: .cascade` (GRDB enables `PRAGMA foreign_keys=ON` by default — relied upon for subtree delete).
- **Positions are derived by `TreeLayout`, never persisted.** The tree code must not write `mindmap_nodes.x`/`y`.
- Drag payload for papers stays a plain `String` (paper id), matching the existing shelf/`dropDestination(for: String.self)`.
- **No Swift toolchain in the implementation environment** — implementers WRITE tests but CANNOT run them; build/`swift test` happen on macOS. Implementers must not fabricate test output; state execution is deferred.
- Core tests: `cd NimbleScholarCore && swift test`. App build: `bash scripts/mac_bootstrap.sh full run` (macOS only).
- This builds on branch `feat/mindmap` (the first mindmap cut, committed, not merged). Core changes are ADDITIVE so the existing app keeps compiling until the app rewrite tasks (6–8) replace the VM/NodeView/Canvas.

## File Structure

**Core (new):**
- `NimbleScholarCore/Sources/NimbleScholarCore/Services/TreeLayout.swift` — pure tidy-tree layout.
- `NimbleScholarCore/Sources/NimbleScholarCore/Services/MindmapNodeSizing.swift` — pure node-size estimate.
- `NimbleScholarCore/Tests/NimbleScholarCoreTests/TreeLayoutTests.swift`, `MindmapNodeSizingTests.swift`.

**Core (modified):**
- `Models/Mindmap.swift` — `MindmapNode` gains `parentID`/`sortOrder`/`collapsed`; add `MindmapTree`, `MapSnapshot`, `NodePaperLink`.
- `Store/LibraryStore.swift` — add `v10-mindmap-tree` migration.
- `Store/MindmapStore.swift` — tree ops + snapshot/restore.
- `Tests/NimbleScholarCoreTests/MindmapStoreTests.swift` — tree-op + snapshot tests.

**App (rewritten):**
- `NimbleScholar/Mindmap/MindmapViewModel.swift`
- `NimbleScholar/Mindmap/NodeView.swift`
- `NimbleScholar/Mindmap/MindmapCanvas.swift`

**App (modified):**
- `NimbleScholar/Mindmap/MindmapView.swift` — gains the canvas toolbar; `createMap` creates a root.

**App (unchanged):** `MapBar.swift`, `PaperShelf.swift`, `NodePaperChip` (lives in `NodeView.swift` — kept).

---

## Task 1: `v10-mindmap-tree` migration + model fields + tree/snapshot value types

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift` (add migration after `v9-mindmap`)
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Models/Mindmap.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapStoreTests.swift` (append)

**Interfaces:**
- Produces: `MindmapNode.parentID: Int64?`, `.sortOrder: Int`, `.collapsed: Bool`; `MindmapTree(nodes:paperIDsByNode:)` with `rootID`, `children(of:)`, `childIDsByParent`, `collapsedSet`; `MapSnapshot(nodes:paperLinks:)`; `NodePaperLink(nodeID:paperID:)`.

- [ ] **Step 1: Write the failing test**

Append to `MindmapStoreTests.swift` (inside the class):

```swift
    func testNodeTreeColumnsRoundTrip() throws {
        let (_, store) = try makeStores()
        let m = try store.createMindmap(name: "M")
        var n = MindmapNode(mindmapID: m.id!, text: "child")
        n.parentID = nil; n.sortOrder = 3; n.collapsed = true
        try store.dbQueue.write { try n.insert($0) }
        let back = try store.dbQueue.read { try MindmapNode.fetchOne($0, key: n.id!) }
        XCTAssertEqual(back?.sortOrder, 3)
        XCTAssertEqual(back?.collapsed, true)
        XCTAssertNil(back?.parentID)
    }

    func testMindmapTreeHelpers() {
        var root = MindmapNode(mindmapID: 1, text: "root"); root.id = 1; root.parentID = nil
        var a = MindmapNode(mindmapID: 1, text: "a"); a.id = 2; a.parentID = 1; a.sortOrder = 1
        var b = MindmapNode(mindmapID: 1, text: "b"); b.id = 3; b.parentID = 1; b.sortOrder = 0; b.collapsed = true
        let tree = MindmapTree(nodes: [root, a, b], paperIDsByNode: [2: [9]])
        XCTAssertEqual(tree.rootID, 1)
        XCTAssertEqual(tree.children(of: 1).map { $0.id }, [3, 2])     // sorted by sort_order
        XCTAssertEqual(tree.childIDsByParent[1], [3, 2])
        XCTAssertEqual(tree.collapsedSet, [3])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter testNodeTreeColumnsRoundTrip`
Expected: FAIL — `value of type 'MindmapNode' has no member 'parentID'`.

- [ ] **Step 3: Add the migration**

In `LibraryStore.swift`, inside `migrator`, immediately after the `m.registerMigration("v9-mindmap")` block and before `return m`:

```swift
        m.registerMigration("v10-mindmap-tree") { db in
            try db.alter(table: "mindmap_nodes") { t in
                t.add(column: "parent_id", .integer).references("mindmap_nodes", onDelete: .cascade)
                t.add(column: "sort_order", .integer).notNull().defaults(to: 0)
                t.add(column: "collapsed", .integer).notNull().defaults(to: 0)
            }
        }
```

- [ ] **Step 4: Extend the `MindmapNode` model + add value types**

In `Models/Mindmap.swift`, replace the `MindmapNode` struct with:

```swift
/// A text node on a map. Tree structure: `parentID` (nil = root), `sortOrder` among siblings,
/// `collapsed` subtree. Positions are computed by TreeLayout, not stored (x/y are dormant).
public struct MindmapNode: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var mindmapID: Int64
    public var text: String = ""
    public var x: Double = 0
    public var y: Double = 0
    public var parentID: Int64?
    public var sortOrder: Int = 0
    public var collapsed: Bool = false
    public var createdAt: Int64 = 0
    public var updatedAt: Int64 = 0

    public static let databaseTableName = "mindmap_nodes"
    enum CodingKeys: String, CodingKey {
        case id, text, x, y, collapsed
        case mindmapID = "mindmap_id"
        case parentID = "parent_id", sortOrder = "sort_order"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
    public init(id: Int64? = nil, mindmapID: Int64, text: String = "", x: Double = 0, y: Double = 0) {
        self.id = id; self.mindmapID = mindmapID; self.text = text; self.x = x; self.y = y
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

Then append to `Models/Mindmap.swift` (after `MindmapGraph`):

```swift
/// One map loaded as a tree: nodes + per-node attached paper ids, with tree-shaped helpers.
public struct MindmapTree: Equatable {
    public var nodes: [MindmapNode]
    public var paperIDsByNode: [Int64: [Int64]]
    public init(nodes: [MindmapNode] = [], paperIDsByNode: [Int64: [Int64]] = [:]) {
        self.nodes = nodes; self.paperIDsByNode = paperIDsByNode
    }
    public var rootID: Int64? { nodes.first { $0.parentID == nil }?.id }
    /// Children of a node, ordered by sortOrder then id.
    public func children(of parentID: Int64) -> [MindmapNode] {
        nodes.filter { $0.parentID == parentID }
            .sorted { ($0.sortOrder, $0.id ?? 0) < ($1.sortOrder, $1.id ?? 0) }
    }
    /// parentID -> ordered child ids (for TreeLayout).
    public var childIDsByParent: [Int64: [Int64]] {
        var m: [Int64: [Int64]] = [:]
        for n in nodes.sorted(by: { ($0.sortOrder, $0.id ?? 0) < ($1.sortOrder, $1.id ?? 0) }) {
            guard let pid = n.parentID, let nid = n.id else { continue }
            m[pid, default: []].append(nid)
        }
        return m
    }
    public var collapsedSet: Set<Int64> { Set(nodes.filter { $0.collapsed }.compactMap { $0.id }) }
}

/// A node→paper attachment row (for snapshots).
public struct NodePaperLink: Equatable {
    public let nodeID: Int64
    public let paperID: Int64
    public init(nodeID: Int64, paperID: Int64) { self.nodeID = nodeID; self.paperID = paperID }
}

/// A full, id-stable capture of one map's tree + attachments, for undo/redo.
public struct MapSnapshot: Equatable {
    public var nodes: [MindmapNode]
    public var paperLinks: [NodePaperLink]
    public init(nodes: [MindmapNode], paperLinks: [NodePaperLink]) {
        self.nodes = nodes; self.paperLinks = paperLinks
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd NimbleScholarCore && swift test --filter testNodeTreeColumnsRoundTrip && swift test --filter testMindmapTreeHelpers`
Expected: PASS both.

- [ ] **Step 6: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift \
        NimbleScholarCore/Sources/NimbleScholarCore/Models/Mindmap.swift \
        NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapStoreTests.swift
git commit -m "feat(mindmap): v10 tree migration + node tree fields + tree/snapshot types"
```

---

## Task 2: `MindmapStore` tree operations

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/MindmapStore.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapStoreTests.swift` (append)

**Interfaces:**
- Consumes: `MindmapNode` tree fields, `MindmapTree` (Task 1).
- Produces: `ensureRoot(mapID:title:) -> MindmapNode`, `addChild(parentID:text:) -> MindmapNode`, `addSibling(of:text:) -> MindmapNode`, `setParent(nodeID:newParentID:index:)`, `reorderSibling(nodeID:before:)`, `setCollapsed(nodeID:collapsed:)`, `tree(forMap:) -> MindmapTree`.

- [ ] **Step 1: Write the failing test**

Append to `MindmapStoreTests.swift`:

```swift
    func testTreeOps() throws {
        let (_, store) = try makeStores()
        let m = try store.createMindmap(name: "Idea")
        let root = try store.ensureRoot(mapID: m.id!, title: "Idea")
        XCTAssertNil(root.parentID)
        // idempotent
        XCTAssertEqual(try store.ensureRoot(mapID: m.id!, title: "Idea").id, root.id)

        let a = try store.addChild(parentID: root.id!, text: "A")
        let b = try store.addChild(parentID: root.id!, text: "B")
        XCTAssertEqual(a.sortOrder, 0)
        XCTAssertEqual(b.sortOrder, 1)

        // sibling inserted right after A, shifting B
        let a2 = try store.addSibling(of: a.id!, text: "A2")
        var tree = try store.tree(forMap: m.id!)
        XCTAssertEqual(tree.children(of: root.id!).map { $0.text }, ["A", "A2", "B"])

        // re-parent A2 under B at index 0
        try store.setParent(nodeID: a2.id!, newParentID: b.id!, index: 0)
        tree = try store.tree(forMap: m.id!)
        XCTAssertEqual(tree.children(of: root.id!).map { $0.text }, ["A", "B"])
        XCTAssertEqual(tree.children(of: b.id!).map { $0.text }, ["A2"])

        // reorder B before A
        try store.reorderSibling(nodeID: b.id!, before: true)
        tree = try store.tree(forMap: m.id!)
        XCTAssertEqual(tree.children(of: root.id!).map { $0.text }, ["B", "A"])

        // collapse + delete subtree cascade
        try store.setCollapsed(nodeID: b.id!, collapsed: true)
        try store.deleteNode(id: b.id!)            // removes B and its child A2 (cascade)
        tree = try store.tree(forMap: m.id!)
        XCTAssertEqual(tree.nodes.map { $0.text }.sorted(), ["A", "Idea"])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter testTreeOps`
Expected: FAIL — `has no member 'ensureRoot'`.

- [ ] **Step 3: Add the tree operations**

In `MindmapStore.swift`, add a new section before the `// MARK: - Papers + graph` section:

```swift
    // MARK: - Tree

    /// The map's root (parent_id NULL), creating it if absent.
    @discardableResult
    public func ensureRoot(mapID: Int64, title: String) throws -> MindmapNode {
        try dbQueue.write { db in
            if let root = try MindmapNode
                .filter(sql: "mindmap_id = ? AND parent_id IS NULL", arguments: [mapID])
                .order(sql: "sort_order ASC, id ASC").fetchOne(db) { return root }
            var n = MindmapNode(mindmapID: mapID, text: title)
            n.parentID = nil; n.sortOrder = 0
            let ts = now(); n.createdAt = ts; n.updatedAt = ts
            try n.insert(db)
            return n
        }
    }

    @discardableResult
    public func addChild(parentID: Int64, text: String) throws -> MindmapNode {
        try dbQueue.write { db in
            let mapID = try Int64.fetchOne(db, sql: "SELECT mindmap_id FROM mindmap_nodes WHERE id = ?", arguments: [parentID])
            guard let mapID else { throw DatabaseError(message: "parent node \(parentID) not found") }
            let maxOrder = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) FROM mindmap_nodes WHERE parent_id = ?", arguments: [parentID]) ?? -1
            var n = MindmapNode(mindmapID: mapID, text: text)
            n.parentID = parentID; n.sortOrder = maxOrder + 1
            let ts = now(); n.createdAt = ts; n.updatedAt = ts
            try n.insert(db)
            return n
        }
    }

    /// Insert a sibling immediately after `nodeID` (shifting later siblings). Root has no
    /// sibling — callers must not call this on the root (the view model converts it to addChild).
    @discardableResult
    public func addSibling(of nodeID: Int64, text: String) throws -> MindmapNode {
        try dbQueue.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT mindmap_id, parent_id, sort_order FROM mindmap_nodes WHERE id = ?", arguments: [nodeID])
            else { throw DatabaseError(message: "node \(nodeID) not found") }
            let mapID: Int64 = row["mindmap_id"]
            let parent: Int64? = row["parent_id"]
            let order: Int = row["sort_order"]
            guard let parent else { throw DatabaseError(message: "cannot add sibling to root") }
            try db.execute(sql: "UPDATE mindmap_nodes SET sort_order = sort_order + 1 WHERE parent_id = ? AND sort_order > ?", arguments: [parent, order])
            var n = MindmapNode(mindmapID: mapID, text: text)
            n.parentID = parent; n.sortOrder = order + 1
            let ts = now(); n.createdAt = ts; n.updatedAt = ts
            try n.insert(db)
            return n
        }
    }

    /// Move `nodeID` under `newParentID` at `index` among the destination's children.
    public func setParent(nodeID: Int64, newParentID: Int64, index: Int) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE mindmap_nodes SET sort_order = sort_order + 1 WHERE parent_id = ? AND sort_order >= ?", arguments: [newParentID, index])
            try db.execute(sql: "UPDATE mindmap_nodes SET parent_id = ?, sort_order = ?, updated_at = ? WHERE id = ?", arguments: [newParentID, index, now(), nodeID])
        }
    }

    /// Swap `nodeID` with its previous (`before=true`) or next sibling; no-op at an edge/root.
    public func reorderSibling(nodeID: Int64, before: Bool) throws {
        try dbQueue.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT parent_id, sort_order FROM mindmap_nodes WHERE id = ?", arguments: [nodeID]),
                  let parent = row["parent_id"] as Int64? else { return }
            let order: Int = row["sort_order"]
            let sql = before
                ? "SELECT id, sort_order FROM mindmap_nodes WHERE parent_id = ? AND sort_order < ? ORDER BY sort_order DESC LIMIT 1"
                : "SELECT id, sort_order FROM mindmap_nodes WHERE parent_id = ? AND sort_order > ? ORDER BY sort_order ASC LIMIT 1"
            guard let nb = try Row.fetchOne(db, sql: sql, arguments: [parent, order]) else { return }
            let nbID: Int64 = nb["id"]; let nbOrder: Int = nb["sort_order"]
            try db.execute(sql: "UPDATE mindmap_nodes SET sort_order = ? WHERE id = ?", arguments: [nbOrder, nodeID])
            try db.execute(sql: "UPDATE mindmap_nodes SET sort_order = ? WHERE id = ?", arguments: [order, nbID])
        }
    }

    public func setCollapsed(nodeID: Int64, collapsed: Bool) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE mindmap_nodes SET collapsed = ?, updated_at = ? WHERE id = ?",
                           arguments: [collapsed ? 1 : 0, now(), nodeID])
        }
    }

    /// Load the map as a tree (nodes ordered + per-node attached paper ids).
    public func tree(forMap mapID: Int64) throws -> MindmapTree {
        try dbQueue.read { db in
            let nodes = try MindmapNode.filter(sql: "mindmap_id = ?", arguments: [mapID])
                .order(sql: "parent_id ASC, sort_order ASC, id ASC").fetchAll(db)
            let rows = try Row.fetchAll(db, sql: """
                SELECT np.node_id AS nid, np.paper_id AS pid
                FROM mindmap_node_papers np
                JOIN mindmap_nodes n ON n.id = np.node_id
                WHERE n.mindmap_id = ?
                ORDER BY np.paper_id ASC
                """, arguments: [mapID])
            var byNode: [Int64: [Int64]] = [:]
            for r in rows { let nid: Int64 = r["nid"]; byNode[nid, default: []].append(r["pid"]) }
            return MindmapTree(nodes: nodes, paperIDsByNode: byNode)
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter testTreeOps`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Store/MindmapStore.swift \
        NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapStoreTests.swift
git commit -m "feat(mindmap): tree ops (ensureRoot, add/move/reorder/collapse, tree load)"
```

---

## Task 3: `MindmapStore` snapshot/restore (undo support)

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/MindmapStore.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapStoreTests.swift` (append)

**Interfaces:**
- Consumes: `MapSnapshot`, `NodePaperLink`, tree ops (Tasks 1–2).
- Produces: `snapshot(mapID:) -> MapSnapshot`, `restore(mapID:_:)`.

- [ ] **Step 1: Write the failing test**

Append to `MindmapStoreTests.swift`:

```swift
    func testSnapshotRestorePreservesIdsAndLinks() throws {
        let (lib, store) = try makeStores()
        let p = try lib.create(Paper(title: "P"))
        let m = try store.createMindmap(name: "M")
        let root = try store.ensureRoot(mapID: m.id!, title: "M")
        let a = try store.addChild(parentID: root.id!, text: "A")
        try store.attachPaper(nodeID: a.id!, paperID: p.id!)

        let snap = try store.snapshot(mapID: m.id!)

        // mutate: add a node, delete A
        _ = try store.addChild(parentID: root.id!, text: "B")
        try store.deleteNode(id: a.id!)
        XCTAssertEqual(try store.tree(forMap: m.id!).nodes.map { $0.text }.sorted(), ["B", "M"])

        // restore brings A (same id) + its paper link back, drops B
        try store.restore(mapID: m.id!, snap)
        let tree = try store.tree(forMap: m.id!)
        XCTAssertEqual(tree.nodes.map { $0.text }.sorted(), ["A", "M"])
        let aBack = tree.nodes.first { $0.text == "A" }!
        XCTAssertEqual(aBack.id, a.id)                              // id preserved
        XCTAssertEqual(try store.paperIDs(forNode: aBack.id!), [p.id!])   // link preserved
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter testSnapshotRestorePreservesIdsAndLinks`
Expected: FAIL — `has no member 'snapshot'`.

- [ ] **Step 3: Add snapshot/restore**

In `MindmapStore.swift`, add at the end (before the closing brace):

```swift
    // MARK: - Undo snapshot/restore (id-stable)

    public func snapshot(mapID: Int64) throws -> MapSnapshot {
        try dbQueue.read { db in
            let nodes = try MindmapNode.filter(sql: "mindmap_id = ?", arguments: [mapID])
                .order(sql: "id ASC").fetchAll(db)
            let rows = try Row.fetchAll(db, sql: """
                SELECT np.node_id AS nid, np.paper_id AS pid
                FROM mindmap_node_papers np
                JOIN mindmap_nodes n ON n.id = np.node_id
                WHERE n.mindmap_id = ?
                """, arguments: [mapID])
            let links = rows.map { NodePaperLink(nodeID: $0["nid"], paperID: $0["pid"]) }
            return MapSnapshot(nodes: nodes, paperLinks: links)
        }
    }

    /// Replace the map's nodes+links with the snapshot, preserving node ids (so selection and
    /// attachments survive an undo). Two-pass insert (parent_id set in a second pass) avoids
    /// self-FK ordering issues; paper links for papers deleted since the snapshot are skipped.
    public func restore(mapID: Int64, _ snapshot: MapSnapshot) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM mindmap_nodes WHERE mindmap_id = ?", arguments: [mapID])
            for n in snapshot.nodes {
                try db.execute(sql: """
                    INSERT INTO mindmap_nodes (id, mindmap_id, text, x, y, parent_id, sort_order, collapsed, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?)
                    """, arguments: [n.id, mapID, n.text, n.x, n.y, n.sortOrder, n.collapsed ? 1 : 0, n.createdAt, n.updatedAt])
            }
            for n in snapshot.nodes where n.parentID != nil {
                try db.execute(sql: "UPDATE mindmap_nodes SET parent_id = ? WHERE id = ?", arguments: [n.parentID, n.id])
            }
            for l in snapshot.paperLinks {
                let paperExists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM papers WHERE id = ?)", arguments: [l.paperID]) ?? false
                if paperExists {
                    try db.execute(sql: "INSERT OR IGNORE INTO mindmap_node_papers (node_id, paper_id) VALUES (?, ?)", arguments: [l.nodeID, l.paperID])
                }
            }
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter testSnapshotRestorePreservesIdsAndLinks`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Store/MindmapStore.swift \
        NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapStoreTests.swift
git commit -m "feat(mindmap): id-stable snapshot/restore for undo"
```

---

## Task 4: `MindmapNodeSizing` (pure node-size estimate)

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Services/MindmapNodeSizing.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapNodeSizingTests.swift`

**Interfaces:**
- Produces: `MindmapNodeSizing.width: CGFloat`, `MindmapNodeSizing.size(text:chipCount:) -> CGSize`.

- [ ] **Step 1: Write the failing test**

Create `MindmapNodeSizingTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import NimbleScholarCore

final class MindmapNodeSizingTests: XCTestCase {
    func testWidthIsFixed() {
        XCTAssertEqual(MindmapNodeSizing.size(text: "x", chipCount: 0).width, MindmapNodeSizing.width)
        XCTAssertEqual(MindmapNodeSizing.size(text: String(repeating: "y", count: 200), chipCount: 5).width, MindmapNodeSizing.width)
    }
    func testHeightGrowsWithTextAndChips() {
        let short = MindmapNodeSizing.size(text: "hi", chipCount: 0).height
        let long = MindmapNodeSizing.size(text: String(repeating: "word ", count: 30), chipCount: 0).height
        let withChips = MindmapNodeSizing.size(text: "hi", chipCount: 3).height
        XCTAssertGreaterThan(long, short)
        XCTAssertGreaterThan(withChips, short)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter MindmapNodeSizingTests`
Expected: FAIL — `cannot find 'MindmapNodeSizing' in scope`.

- [ ] **Step 3: Implement**

Create `MindmapNodeSizing.swift`:

```swift
import CoreGraphics

/// Pure node-size estimate for tree layout (real text measurement is a later refinement).
/// Fixed width; height grows with estimated wrapped text lines + attached-paper chips.
public enum MindmapNodeSizing {
    public static let width: CGFloat = 200
    private static let charsPerLine = 22
    private static let lineHeight: CGFloat = 18
    private static let verticalPadding: CGFloat = 18
    private static let chipHeight: CGFloat = 22

    public static func size(text: String, chipCount: Int) -> CGSize {
        let lines = max(1, Int((Double(text.count) / Double(charsPerLine)).rounded(.up)))
        let textHeight = CGFloat(lines) * lineHeight + verticalPadding
        let chipsHeight = CGFloat(max(0, chipCount)) * chipHeight
        return CGSize(width: width, height: textHeight + chipsHeight)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter MindmapNodeSizingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Services/MindmapNodeSizing.swift \
        NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapNodeSizingTests.swift
git commit -m "feat(mindmap): pure node-size estimator"
```

---

## Task 5: `TreeLayout` (pure tidy-tree layout)

**Files:**
- Create: `NimbleScholarCore/Sources/NimbleScholarCore/Services/TreeLayout.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/TreeLayoutTests.swift`

**Interfaces:**
- Consumes: nothing (pure). Uses `MindmapNodeSizing.width` conceptually but takes sizes as input.
- Produces: `TreeLayout.Config(levelGapX:siblingGapY:)`; `TreeLayout.positions(rootID:childrenByParent:collapsed:sizeOf:config:) -> [Int64: CGPoint]` (node CENTERS).

- [ ] **Step 1: Write the failing test**

Create `TreeLayoutTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import NimbleScholarCore

final class TreeLayoutTests: XCTestCase {
    let size = CGSize(width: 200, height: 40)

    func testSingleNodeAtOrigin() {
        let p = TreeLayout.positions(rootID: 1, childrenByParent: [:], collapsed: [], sizeOf: [1: size])
        XCTAssertEqual(p.count, 1)
        XCTAssertNotNil(p[1])
    }

    func testParentCenteredOnChildren() {
        // root(1) with children 2 and 3
        let children: [Int64: [Int64]] = [1: [2, 3]]
        let sizes: [Int64: CGSize] = [1: size, 2: size, 3: size]
        let p = TreeLayout.positions(rootID: 1, childrenByParent: children, collapsed: [], sizeOf: sizes)
        XCTAssertEqual(p.count, 3)
        // children are deeper (larger x) than root
        XCTAssertGreaterThan(p[2]!.x, p[1]!.x)
        XCTAssertEqual(p[2]!.x, p[3]!.x, accuracy: 0.001)        // same depth → same x
        // root y is the midpoint of its two children's y
        XCTAssertEqual(p[1]!.y, (p[2]!.y + p[3]!.y) / 2, accuracy: 0.001)
        // children don't overlap vertically
        XCTAssertNotEqual(p[2]!.y, p[3]!.y)
    }

    func testCollapsedExcludesChildren() {
        let children: [Int64: [Int64]] = [1: [2], 2: [3]]
        let sizes: [Int64: CGSize] = [1: size, 2: size, 3: size]
        let p = TreeLayout.positions(rootID: 1, childrenByParent: children, collapsed: [2], sizeOf: sizes)
        XCTAssertNotNil(p[1]); XCTAssertNotNil(p[2])
        XCTAssertNil(p[3])                                       // 3 hidden under collapsed 2
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter TreeLayoutTests`
Expected: FAIL — `cannot find 'TreeLayout' in scope`.

- [ ] **Step 3: Implement**

Create `TreeLayout.swift`:

```swift
import CoreGraphics

/// Pure tidy left-to-right logical-tree layout (Reingold–Tilford style): depth → x, and each
/// parent is vertically centered on its children's span. Collapsed nodes exclude their subtree.
/// Returns each visible node's CENTER point in canvas coordinates.
public struct TreeLayout {
    public struct Config {
        public var levelGapX: CGFloat
        public var siblingGapY: CGFloat
        public init(levelGapX: CGFloat = 60, siblingGapY: CGFloat = 16) {
            self.levelGapX = levelGapX; self.siblingGapY = siblingGapY
        }
    }

    public static func positions(
        rootID: Int64,
        childrenByParent: [Int64: [Int64]],
        collapsed: Set<Int64>,
        sizeOf: [Int64: CGSize],
        config: Config = .init()
    ) -> [Int64: CGPoint] {
        let columnWidth = (sizeOf.values.map { $0.width }.max() ?? 200)
        let columnStep = columnWidth + config.levelGapX

        var positions: [Int64: CGPoint] = [:]
        var cursorY: CGFloat = 0

        func assign(_ id: Int64, depth: Int) {
            let h = sizeOf[id]?.height ?? 40
            let centerX = CGFloat(depth) * columnStep + columnWidth / 2
            let kids = collapsed.contains(id) ? [] : (childrenByParent[id] ?? [])
            if kids.isEmpty {
                let centerY = cursorY + h / 2
                positions[id] = CGPoint(x: centerX, y: centerY)
                cursorY += h + config.siblingGapY
            } else {
                for kid in kids { assign(kid, depth: depth + 1) }
                let firstY = positions[kids.first!]?.y ?? cursorY
                let lastY = positions[kids.last!]?.y ?? cursorY
                positions[id] = CGPoint(x: centerX, y: (firstY + lastY) / 2)
            }
        }
        assign(rootID, depth: 0)
        return positions
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter TreeLayoutTests`
Expected: PASS.

- [ ] **Step 5: Run the full Core suite (no regressions)**

Run: `cd NimbleScholarCore && swift test`
Expected: PASS (all existing + new mindmap/layout tests).

- [ ] **Step 6: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Services/TreeLayout.swift \
        NimbleScholarCore/Tests/NimbleScholarCoreTests/TreeLayoutTests.swift
git commit -m "feat(mindmap): pure tidy-tree layout + tests"
```

---

## Task 6: `MindmapViewModel` rewrite (tree state, selection, keyboard ops, undo)

**Files:**
- Rewrite: `NimbleScholar/Mindmap/MindmapViewModel.swift` (replace entire file)

**Interfaces:**
- Consumes: `MindmapStore` tree ops + snapshot/restore (Tasks 2–3), `MindmapTree`, `TreeLayout`, `MindmapNodeSizing`, `CanvasTransform`, `LibraryViewModel.openReader` (existing).
- Produces (consumed by Tasks 7–8): published `maps`, `activeMapID`, `tree`, `layout`, `sizes`, `selectedNodeID`, `editingNodeID`, `transform`; computed `activeMap`, `rootID`; `MoveDirection` enum; `DropTarget` struct; methods `selectMap(_:)`, `createMap(name:)`, `renameActiveMap(to:)`, `deleteActiveMap()`, `addChildToSelected()`, `addSiblingToSelected()`, `addChild(to:)`, `addSibling(of:)`, `deleteSelectedSubtree()`, `deleteSubtree(_:)`, `toggleCollapse(_:)`, `reorder(_:before:)`, `reparent(_:to:index:)`, `beginEdit(_:)`, `commitEdit(_:)`, `cancelEdit()`, `select(_:)`, `navigate(_:)`, `attach(_:to:)`, `detach(_:from:)`, `undo()`, `redo()`, `canUndo`, `canRedo`, `hasChildren(_:)`, `isCollapsed(_:)`, `dropTarget(forDragged:at:)`, `updateTransform(_:)`, `fit(in:)`.

- [ ] **Step 1: Replace the file**

Replace the entire contents of `NimbleScholar/Mindmap/MindmapViewModel.swift`:

```swift
import SwiftUI
import CoreGraphics
import NimbleScholarCore

enum MoveDirection { case up, down, left, right }

/// Drives the auto-layout tree mindmap: maps, the active map's tree, computed layout, selection,
/// inline-edit state, keyboard/structural ops, and snapshot-based undo/redo. Positions come from
/// TreeLayout (never persisted); structural ops write to MindmapStore then reload + relayout.
@MainActor
final class MindmapViewModel: ObservableObject {
    @Published var maps: [Mindmap] = []
    @Published var activeMapID: Int64?
    @Published var tree = MindmapTree()
    @Published var layout: [Int64: CGPoint] = [:]
    @Published var sizes: [Int64: CGSize] = [:]
    @Published var selectedNodeID: Int64?
    @Published var editingNodeID: Int64?
    @Published var transform = CanvasTransform()

    struct DropTarget: Equatable { var parentID: Int64; var index: Int }

    private let store = AppEnvironment.shared.mindmaps
    private let activeKey = "activeMindmapID"
    private var undoStack: [MapSnapshot] = []
    private var redoStack: [MapSnapshot] = []

    init() { reloadMaps() }

    var activeMap: Mindmap? { maps.first { $0.id == activeMapID } }
    var rootID: Int64? { tree.rootID }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func hasChildren(_ id: Int64) -> Bool { tree.nodes.contains { $0.parentID == id } }
    func isCollapsed(_ id: Int64) -> Bool { tree.nodes.first { $0.id == id }?.collapsed ?? false }

    // MARK: Maps

    func reloadMaps() {
        maps = (try? store.mindmaps()) ?? []
        let saved = Int64(UserDefaults.standard.integer(forKey: activeKey))
        if activeMapID == nil {
            activeMapID = (saved != 0 && maps.contains { $0.id == saved }) ? saved : maps.first?.id
        } else if !maps.contains(where: { $0.id == activeMapID }) {
            activeMapID = maps.first?.id
        }
        loadActive()
    }

    func loadActive() {
        undoStack.removeAll(); redoStack.removeAll()
        guard let id = activeMapID else { tree = MindmapTree(); layout = [:]; sizes = [:]; selectedNodeID = nil; return }
        _ = try? store.ensureRoot(mapID: id, title: activeMap?.name.isEmpty == false ? activeMap!.name : "Central idea")
        reloadTree()
        selectedNodeID = tree.rootID
        if let m = activeMap {
            transform = CanvasTransform(zoom: CGFloat(m.zoom), pan: CGSize(width: m.offsetX, height: m.offsetY))
        }
    }

    func selectMap(_ id: Int64) {
        activeMapID = id
        UserDefaults.standard.set(Int(id), forKey: activeKey)
        loadActive()
    }

    func createMap(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = try? store.createMindmap(name: trimmed.isEmpty ? "Untitled idea" : trimmed),
              let id = m.id else { return }
        _ = try? store.ensureRoot(mapID: id, title: trimmed.isEmpty ? "Central idea" : trimmed)
        reloadMaps(); selectMap(id)
    }

    func renameActiveMap(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = activeMapID, !trimmed.isEmpty else { return }
        try? store.renameMindmap(id: id, name: trimmed); reloadMaps()
    }

    func deleteActiveMap() {
        guard let id = activeMapID else { return }
        try? store.deleteMindmap(id: id); activeMapID = nil; reloadMaps()
    }

    // MARK: Tree load + layout

    private func reloadTree() {
        guard let id = activeMapID else { tree = MindmapTree(); layout = [:]; sizes = [:]; return }
        tree = (try? store.tree(forMap: id)) ?? MindmapTree()
        if let sel = selectedNodeID, !tree.nodes.contains(where: { $0.id == sel }) { selectedNodeID = tree.rootID }
        relayout()
    }

    private func relayout() {
        var sz: [Int64: CGSize] = [:]
        for n in tree.nodes {
            guard let nid = n.id else { continue }
            sz[nid] = MindmapNodeSizing.size(text: n.text, chipCount: tree.paperIDsByNode[nid]?.count ?? 0)
        }
        sizes = sz
        if let root = tree.rootID {
            layout = TreeLayout.positions(rootID: root, childrenByParent: tree.childIDsByParent,
                                          collapsed: tree.collapsedSet, sizeOf: sz)
        } else { layout = [:] }
    }

    // MARK: Structural ops (each: push undo → store → reload)

    private func pushUndo() {
        guard let id = activeMapID, let snap = try? store.snapshot(mapID: id) else { return }
        undoStack.append(snap); redoStack.removeAll()
    }

    func addChild(to parentID: Int64) {
        pushUndo()
        guard let n = try? store.addChild(parentID: parentID, text: ""), let nid = n.id else { return }
        reloadTree(); selectedNodeID = nid; editingNodeID = nid
    }
    func addChildToSelected() { if let s = selectedNodeID { addChild(to: s) } }

    func addSibling(of nodeID: Int64) {
        if nodeID == tree.rootID { addChild(to: nodeID); return }   // root has no sibling
        pushUndo()
        guard let n = try? store.addSibling(of: nodeID, text: ""), let nid = n.id else { return }
        reloadTree(); selectedNodeID = nid; editingNodeID = nid
    }
    func addSiblingToSelected() { if let s = selectedNodeID { addSibling(of: s) } }

    func deleteSubtree(_ nodeID: Int64) {
        guard nodeID != tree.rootID else { return }
        let parent = tree.nodes.first { $0.id == nodeID }?.parentID
        pushUndo(); try? store.deleteNode(id: nodeID); reloadTree()
        selectedNodeID = parent ?? tree.rootID
    }
    func deleteSelectedSubtree() { if let s = selectedNodeID { deleteSubtree(s) } }

    func toggleCollapse(_ nodeID: Int64) {
        guard let n = tree.nodes.first(where: { $0.id == nodeID }) else { return }
        pushUndo(); try? store.setCollapsed(nodeID: nodeID, collapsed: !n.collapsed); reloadTree()
    }

    func reorder(_ nodeID: Int64, before: Bool) {
        pushUndo(); try? store.reorderSibling(nodeID: nodeID, before: before); reloadTree()
    }

    func reparent(_ nodeID: Int64, to newParentID: Int64, index: Int) {
        guard nodeID != tree.rootID, nodeID != newParentID, !isDescendant(newParentID, of: nodeID) else { return }
        pushUndo(); try? store.setParent(nodeID: nodeID, newParentID: newParentID, index: index)
        reloadTree(); selectedNodeID = nodeID
    }

    private func isDescendant(_ candidate: Int64, of ancestor: Int64) -> Bool {
        var cur: Int64? = candidate
        while let c = cur {
            if c == ancestor { return true }
            cur = tree.nodes.first { $0.id == c }?.parentID
        }
        return false
    }

    // MARK: Text edit

    func beginEdit(_ nodeID: Int64) { selectedNodeID = nodeID; editingNodeID = nodeID }
    func commitEdit(_ text: String) {
        guard let id = editingNodeID else { return }
        editingNodeID = nil
        pushUndo(); try? store.updateNodeText(id: id, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        reloadTree()
    }
    func cancelEdit() { editingNodeID = nil }

    // MARK: Selection / navigation

    func select(_ nodeID: Int64) { selectedNodeID = nodeID }

    func navigate(_ dir: MoveDirection) {
        guard let sel = selectedNodeID, let node = tree.nodes.first(where: { $0.id == sel }) else {
            selectedNodeID = tree.rootID; return
        }
        switch dir {
        case .left:
            if let p = node.parentID { selectedNodeID = p }
        case .right:
            if !node.collapsed, let first = tree.children(of: sel).first?.id { selectedNodeID = first }
        case .up, .down:
            guard let p = node.parentID else { return }
            let sibs = tree.children(of: p)
            guard let idx = sibs.firstIndex(where: { $0.id == sel }) else { return }
            let j = dir == .up ? idx - 1 : idx + 1
            if sibs.indices.contains(j) { selectedNodeID = sibs[j].id }
        }
    }

    // MARK: Papers (kept)

    func attach(_ paperID: Int64, to nodeID: Int64) {
        pushUndo(); try? store.attachPaper(nodeID: nodeID, paperID: paperID); reloadTree()
    }
    func detach(_ paperID: Int64, from nodeID: Int64) {
        pushUndo(); try? store.detachPaper(nodeID: nodeID, paperID: paperID); reloadTree()
    }

    // MARK: Undo / redo

    func undo() {
        guard let id = activeMapID, let prev = undoStack.popLast() else { return }
        if let cur = try? store.snapshot(mapID: id) { redoStack.append(cur) }
        try? store.restore(mapID: id, prev); reloadTree()
    }
    func redo() {
        guard let id = activeMapID, let next = redoStack.popLast() else { return }
        if let cur = try? store.snapshot(mapID: id) { undoStack.append(cur) }
        try? store.restore(mapID: id, next); reloadTree()
    }

    // MARK: Drag-reparent hit-test

    /// The node under `canvasPoint` to drop `nodeID` into (as its last child), or nil over
    /// self/descendant/empty space.
    func dropTarget(forDragged nodeID: Int64, at canvasPoint: CGPoint) -> DropTarget? {
        for n in tree.nodes {
            guard let nid = n.id, nid != nodeID, !isDescendant(nid, of: nodeID),
                  let c = layout[nid], let sz = sizes[nid] else { continue }
            let rect = CGRect(x: c.x - sz.width / 2, y: c.y - sz.height / 2, width: sz.width, height: sz.height)
            if rect.contains(canvasPoint) {
                return DropTarget(parentID: nid, index: tree.children(of: nid).count)
            }
        }
        return nil
    }

    // MARK: Viewport

    private var viewportWork: DispatchWorkItem?
    func updateTransform(_ t: CanvasTransform) {
        transform = t
        viewportWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistViewport() }
        viewportWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    private func persistViewport() {
        guard let id = activeMapID else { return }
        try? store.saveViewport(mapID: id, zoom: Double(transform.zoom),
                                offsetX: Double(transform.pan.width), offsetY: Double(transform.pan.height))
    }

    /// Frame the whole tree into `viewport` (centers + scales to fit, clamped).
    func fit(in viewport: CGSize) {
        guard !layout.isEmpty else { return }
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for (id, c) in layout {
            let sz = sizes[id] ?? CGSize(width: 200, height: 40)
            minX = min(minX, c.x - sz.width / 2); maxX = max(maxX, c.x + sz.width / 2)
            minY = min(minY, c.y - sz.height / 2); maxY = max(maxY, c.y + sz.height / 2)
        }
        let contentW = max(1, maxX - minX), contentH = max(1, maxY - minY)
        let margin: CGFloat = 40
        let zoom = CanvasTransform.clampZoom(min((viewport.width - margin) / contentW,
                                                 (viewport.height - margin) / contentH))
        let centerX = (minX + maxX) / 2, centerY = (minY + maxY) / 2
        let pan = CGSize(width: viewport.width / 2 - centerX * zoom,
                         height: viewport.height / 2 - centerY * zoom)
        updateTransform(CanvasTransform(zoom: zoom, pan: pan))
    }
}
```

- [ ] **Step 2: Self-verify compile-correctness (no build available)**

Confirm by reading: every `store.*` call matches a `MindmapStore` signature from Tasks 2–3; `MindmapTree`/`TreeLayout`/`MindmapNodeSizing`/`CanvasTransform` usages match Tasks 1/4/5 and the existing `CanvasTransform`; `DatabaseError` is not referenced here (only in the store). This file references `PaperShelf`/`MindmapCanvas`/`NodeView` indirectly only via `MindmapView` (Task 8), so it does not by itself complete the build — that's expected.

- [ ] **Step 3: Commit**

```bash
git add NimbleScholar/Mindmap/MindmapViewModel.swift
git commit -m "feat(mindmap): rewrite view model for auto-layout tree + undo"
```

---

## Task 7: `NodeView` rewrite (selection, inline edit, collapse, drag-to-reparent, chips)

**Files:**
- Rewrite: `NimbleScholar/Mindmap/NodeView.swift` (replace entire file; keeps `NodePaperChip`)

**Interfaces:**
- Consumes: `MindmapViewModel` (Task 6), `LibraryViewModel.openReader`/`papers`, `MindmapNode`, `Paper`, `AppEnvironment.shared.store.paper(id:)`.
- Produces: `NodeView(node:size:selected:editing:paperIDs:hasChildren:dragInfo:coordSpace:)` (Equatable); `NodeDragInfo` struct; `NodePaperChip` (unchanged behavior).

- [ ] **Step 1: Replace the file**

Replace the entire contents of `NimbleScholar/Mindmap/NodeView.swift`:

```swift
import SwiftUI
import CoreGraphics
import NimbleScholarCore

/// Transient drag state shared with the canvas overlay (the dragged node + its current
/// canvas-space point), so the canvas can draw a drop indicator while the node moves locally.
struct NodeDragInfo: Equatable { var nodeID: Int64; var canvasPoint: CGPoint }

/// One tree node card: selectable, inline-editable, collapsible, drag-to-reparent, with attached
/// paper chips. Equatable so moving/selecting one node doesn't re-render its siblings.
struct NodeView: View, Equatable {
    @EnvironmentObject var vm: MindmapViewModel
    @EnvironmentObject var libraryVM: LibraryViewModel

    let node: MindmapNode
    let size: CGSize
    let selected: Bool
    let editing: Bool
    let paperIDs: [Int64]
    let hasChildren: Bool
    @Binding var dragInfo: NodeDragInfo?
    let coordSpace: String

    @GestureState private var dragOffset: CGSize = .zero
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @State private var dropTargeted = false

    private var nodeID: Int64 { node.id ?? -1 }

    static func == (l: NodeView, r: NodeView) -> Bool {
        l.node == r.node && l.size == r.size && l.selected == r.selected
            && l.editing == r.editing && l.paperIDs == r.paperIDs && l.hasChildren == r.hasChildren
    }

    private var attachedPapers: [Paper] {
        let byID = Dictionary(uniqueKeysWithValues: libraryVM.papers.compactMap { p in p.id.map { ($0, p) } })
        return paperIDs.map { id in
            byID[id] ?? ((try? AppEnvironment.shared.store.paper(id: id)) ?? nil) ?? Paper(title: "Paper #\(id)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if hasChildren {
                    Button { vm.toggleCollapse(nodeID) } label: {
                        Image(systemName: node.collapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                if editing {
                    TextField("Idea", text: $draft)
                        .textFieldStyle(.plain).font(.callout.bold())
                        .focused($fieldFocused)
                        .onSubmit { vm.commitEdit(draft) }
                        .onExitCommand { vm.cancelEdit() }
                        .onChange(of: fieldFocused) { _, focused in if !focused { vm.commitEdit(draft) } }
                        .onAppear { draft = node.text; fieldFocused = true }
                } else {
                    Text(node.text.isEmpty ? "Untitled" : node.text)
                        .font(.callout.bold())
                        .foregroundStyle(node.text.isEmpty ? .secondary : .primary)
                }
            }
            ForEach(attachedPapers) { p in
                NodePaperChip(paper: p,
                              onOpen: { libraryVM.openReader(p) },
                              onRemove: { if let pid = p.id { vm.detach(pid, from: nodeID) } })
            }
        }
        .padding(10)
        .frame(width: size.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: selected || dropTargeted ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .offset(dragOffset)
        .gesture(reparentGesture)
        .onTapGesture { vm.select(nodeID) }
        .onTapGesture(count: 2) { vm.beginEdit(nodeID) }
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let pid = Int64(s) else { return false }
            vm.attach(pid, to: nodeID); return true
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button("Add Child") { vm.addChild(to: nodeID) }
            if nodeID != vm.rootID { Button("Add Sibling") { vm.addSibling(of: nodeID) } }
            Button("Rename") { vm.beginEdit(nodeID) }
            if hasChildren {
                Button(node.collapsed ? "Expand" : "Collapse") { vm.toggleCollapse(nodeID) }
            }
            if nodeID != vm.rootID {
                Divider()
                Button("Move Up") { vm.reorder(nodeID, before: true) }
                Button("Move Down") { vm.reorder(nodeID, before: false) }
                Divider()
                Button("Delete", role: .destructive) { vm.deleteSubtree(nodeID) }
            }
        }
    }

    private var borderColor: Color {
        if dropTargeted { return .accentColor }
        return selected ? .accentColor : .black.opacity(0.12)
    }

    /// Drag the node body to re-parent. Moves locally (no model write) and reports its canvas
    /// point to the overlay; commits the reparent only on release.
    private var reparentGesture: some Gesture {
        DragGesture(coordinateSpace: .named(coordSpace))
            .updating($dragOffset) { value, state, _ in state = value.translation }
            .onChanged { value in
                guard nodeID != vm.rootID else { return }
                dragInfo = NodeDragInfo(nodeID: nodeID, canvasPoint: vm.transform.canvas(from: value.location))
            }
            .onEnded { value in
                defer { dragInfo = nil }
                guard nodeID != vm.rootID else { return }
                let p = vm.transform.canvas(from: value.location)
                if let target = vm.dropTarget(forDragged: nodeID, at: p) {
                    vm.reparent(nodeID, to: target.parentID, index: target.index)
                }
            }
    }
}

/// A compact paper attached to a node. Click opens it in the reader; hover reveals remove.
struct NodePaperChip: View {
    let paper: Paper
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text").font(.caption2).foregroundStyle(.secondary)
            Text(paper.title).font(.caption2).lineLimit(1)
            Spacer(minLength: 0)
            if hovering {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill").font(.caption2) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.12)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen() }
        .help(paper.title)
    }
}
```

- [ ] **Step 2: Self-verify compile-correctness**

Confirm: `NodeView` properties match the call site Task 8 will write (`node:size:selected:editing:paperIDs:hasChildren:dragInfo:coordSpace:`); the collapse chevron uses the `hasChildren` prop (in `==`) so it refreshes when a node gains its first child; `@GestureState dragOffset` resets on end (local move, no model write); `vm.*` members used (`toggleCollapse`, `commitEdit`, `cancelEdit`, `beginEdit`, `select`, `attach`, `detach`, `addChild`, `addSibling`, `deleteSubtree`, `reorder`, `rootID`, `transform`, `dropTarget`, `reparent`) all exist on the Task 6 VM. `.onExitCommand` (Esc) and `.onSubmit` (Return) drive commit/cancel.

- [ ] **Step 3: Commit**

```bash
git add NimbleScholar/Mindmap/NodeView.swift
git commit -m "feat(mindmap): rewrite node card — edit, collapse, drag-reparent, chips"
```

---

## Task 8: `MindmapCanvas` rewrite + `MindmapView` toolbar

**Files:**
- Rewrite: `NimbleScholar/Mindmap/MindmapCanvas.swift` (replace entire file)
- Modify: `NimbleScholar/Mindmap/MindmapView.swift` (add the canvas toolbar above the canvas)

**Interfaces:**
- Consumes: `MindmapViewModel` (Task 6), `NodeView`/`NodeDragInfo` (Task 7), `CanvasTransform`.
- Produces: `MindmapCanvas` view; the `MindmapView` toolbar.

- [ ] **Step 1: Replace `MindmapCanvas.swift`**

Replace the entire contents of `NimbleScholar/Mindmap/MindmapCanvas.swift`:

```swift
import SwiftUI
import CoreGraphics
import NimbleScholarCore

/// The tree canvas: a committed layer (parent→child connectors in one Canvas pass + viewport-
/// culled NodeViews placed by TreeLayout) and an interactive overlay (drop indicator). Pan =
/// drag background; zoom = pinch / +- ; Fit frames the tree. Keyboard ops act on the selection.
struct MindmapCanvas: View {
    @EnvironmentObject var vm: MindmapViewModel
    @EnvironmentObject var libraryVM: LibraryViewModel

    @State private var panBase: CGSize?
    @State private var zoomBase: CGFloat?
    @State private var dragInfo: NodeDragInfo?
    @FocusState private var focused: Bool

    private let coordSpace = "mindmapTreeCanvas"

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                connectors
                nodes(in: geo.size)
                dropIndicator
            }
            .coordinateSpace(name: coordSpace)
            .clipped()
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onChange(of: vm.editingNodeID) { _, editing in if editing == nil { focused = true } }
            .overlay(alignment: .bottomTrailing) { zoomControls(viewport: geo.size) }
            .background(keyShortcuts)
            .simultaneousGesture(magnifyGesture)
            .onKeyPress(.tab) { vm.addChildToSelected(); return .handled }
            .onKeyPress(.return) { if vm.editingNodeID == nil { vm.addSiblingToSelected(); return .handled }; return .ignored }
            .onKeyPress(.deleteForward) { vm.deleteSelectedSubtree(); return .handled }
            .onKeyPress(KeyEquivalent("\u{7f}")) { vm.deleteSelectedSubtree(); return .handled }   // Backspace
            .onKeyPress(.space) { if let s = vm.selectedNodeID { vm.toggleCollapse(s) }; return .handled }
            .onKeyPress(.upArrow) { vm.navigate(.up); return .handled }
            .onKeyPress(.downArrow) { vm.navigate(.down); return .handled }
            .onKeyPress(.leftArrow) { vm.navigate(.left); return .handled }
            .onKeyPress(.rightArrow) { vm.navigate(.right); return .handled }
        }
    }

    // MARK: Background (pan)

    private var background: some View {
        Color(nsColor: .textBackgroundColor)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .gesture(panGesture)
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if panBase == nil { panBase = vm.transform.pan }
                var t = vm.transform
                t.pan = CGSize(width: (panBase?.width ?? 0) + value.translation.width,
                               height: (panBase?.height ?? 0) + value.translation.height)
                vm.transform = t
            }
            .onEnded { _ in panBase = nil; vm.updateTransform(vm.transform) }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomBase == nil { zoomBase = vm.transform.zoom }
                var t = vm.transform
                t.zoom = CanvasTransform.clampZoom((zoomBase ?? 1) * value.magnification)
                vm.transform = t
            }
            .onEnded { _ in zoomBase = nil; vm.updateTransform(vm.transform) }
    }

    // MARK: Committed layer — connectors + nodes

    private var connectors: some View {
        Canvas { ctx, _ in
            for n in vm.tree.nodes {
                guard let nid = n.id, let pid = n.parentID,
                      let cc = vm.layout[nid], let pc = vm.layout[pid] else { continue }
                let p1 = vm.transform.screen(from: pc)
                let p2 = vm.transform.screen(from: cc)
                var path = Path()
                path.move(to: p1)
                let midX = (p1.x + p2.x) / 2
                path.addCurve(to: p2, control1: CGPoint(x: midX, y: p1.y), control2: CGPoint(x: midX, y: p2.y))
                ctx.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }

    private func nodes(in size: CGSize) -> some View {
        let viewport = CGRect(origin: .zero, size: size)
        let visible = vm.tree.nodes.filter { n in
            guard let nid = n.id, let c = vm.layout[nid], let sz = vm.sizes[nid] else { return false }
            let rect = CGRect(x: c.x - sz.width / 2, y: c.y - sz.height / 2, width: sz.width, height: sz.height)
            return vm.transform.isVisible(canvasRect: rect, in: viewport)
        }
        return ForEach(visible) { n in
            let nid = n.id ?? -1
            NodeView(node: n,
                     size: vm.sizes[nid] ?? CGSize(width: 200, height: 40),
                     selected: vm.selectedNodeID == nid,
                     editing: vm.editingNodeID == nid,
                     paperIDs: vm.tree.paperIDsByNode[nid] ?? [],
                     hasChildren: !vm.tree.children(of: nid).isEmpty,
                     dragInfo: $dragInfo,
                     coordSpace: coordSpace)
                .equatable()
                .environmentObject(vm)
                .environmentObject(libraryVM)
                .position(vm.transform.screen(from: vm.layout[nid] ?? .zero))
        }
    }

    // MARK: Interactive overlay — drop indicator

    @ViewBuilder private var dropIndicator: some View {
        if let info = dragInfo, let target = vm.dropTarget(forDragged: info.nodeID, at: info.canvasPoint),
           let c = vm.layout[target.parentID], let sz = vm.sizes[target.parentID] {
            let screen = vm.transform.screen(from: c)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5]))
                .frame(width: sz.width * vm.transform.zoom, height: sz.height * vm.transform.zoom)
                .position(screen)
                .allowsHitTesting(false)
        }
    }

    // MARK: Zoom controls + hidden command shortcuts

    private func zoomControls(viewport: CGSize) -> some View {
        VStack(spacing: 4) {
            Button { zoomBy(1.2) } label: { Image(systemName: "plus") }
            Button { zoomBy(1 / 1.2) } label: { Image(systemName: "minus") }
            Button { vm.fit(in: viewport) } label: { Image(systemName: "scope") }
        }
        .buttonStyle(.bordered).padding(10)
    }

    private func zoomBy(_ factor: CGFloat) {
        var t = vm.transform
        t.zoom = CanvasTransform.clampZoom(t.zoom * factor)
        vm.updateTransform(t)
    }

    /// Hidden buttons carry the ⌘-modified shortcuts that `.onKeyPress` can't express cleanly.
    /// (Sibling reorder lives in the node context menu to avoid colliding with plain-arrow nav.)
    private var keyShortcuts: some View {
        Group {
            Button("") { vm.undo() }.keyboardShortcut("z", modifiers: [.command]).hidden()
            Button("") { vm.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).hidden()
        }
    }
}
```

- [ ] **Step 2: Add the canvas toolbar to `MindmapView.swift`**

In `NimbleScholar/Mindmap/MindmapView.swift`, the `VStack` currently is:

```swift
            VStack(spacing: 0) {
                MapBar().environmentObject(vm)
                Divider()
                if vm.activeMapID == nil {
                    MindmapEmptyState().environmentObject(vm)
                } else {
                    MindmapCanvas()
                        .environmentObject(vm)
                        .environmentObject(libraryVM)
                }
            }
```

Replace it with (inserts a `CanvasToolbar` between the divider and the canvas):

```swift
            VStack(spacing: 0) {
                MapBar().environmentObject(vm)
                Divider()
                if vm.activeMapID == nil {
                    MindmapEmptyState().environmentObject(vm)
                } else {
                    CanvasToolbar().environmentObject(vm)
                    Divider()
                    MindmapCanvas()
                        .environmentObject(vm)
                        .environmentObject(libraryVM)
                }
            }
```

Then append `CanvasToolbar` to the same file (after `MindmapEmptyState`):

```swift
/// Guaranteed-usable mirror of the keyboard ops (in case a key is captured by the system).
struct CanvasToolbar: View {
    @EnvironmentObject var vm: MindmapViewModel
    private var hasSelection: Bool { vm.selectedNodeID != nil }
    private var selectionIsRoot: Bool { vm.selectedNodeID == vm.rootID }

    var body: some View {
        HStack(spacing: 10) {
            Button { vm.addChildToSelected() } label: { Label("Child", systemImage: "arrow.turn.down.right") }
                .disabled(!hasSelection)
            Button { vm.addSiblingToSelected() } label: { Label("Sibling", systemImage: "arrow.down") }
                .disabled(!hasSelection || selectionIsRoot)
            Button { vm.deleteSelectedSubtree() } label: { Label("Delete", systemImage: "trash") }
                .disabled(!hasSelection || selectionIsRoot)
            Button { if let s = vm.selectedNodeID { vm.toggleCollapse(s) } } label: { Label("Collapse", systemImage: "rectangle.compress.vertical") }
                .disabled(!hasSelection)
            Divider().frame(height: 16)
            Button { vm.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(!vm.canUndo)
            Button { vm.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(!vm.canRedo)
            Spacer()
            Text("Tab: child · Return: sibling · arrows: move · Space: collapse")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}
```

- [ ] **Step 3: Self-verify compile-correctness**

Confirm: the `NodeView(...)` call matches Task 7's signature exactly (including `hasChildren:`); `$dragInfo` is a `Binding<NodeDragInfo?>`; `coordSpace` string is consistent and passed to `NodeView`; all `vm.*` members the canvas uses exist on Task 6's VM (`tree`, `layout`, `sizes`, `selectedNodeID`, `editingNodeID`, `transform`, `addChildToSelected`, `addSiblingToSelected`, `deleteSelectedSubtree`, `toggleCollapse`, `navigate`, `dropTarget`, `undo`, `redo`, `fit`, `updateTransform`); `.onKeyPress`, `MagnifyGesture`, `Canvas`, `.focusable`, `.focusEffectDisabled`, `.onChange(of:_:)` two-param are macOS 14 APIs.

- [ ] **Step 4: Build on macOS (deferred to the user / verification task)**

This task completes the feature, so it should compile. The implementer cannot build (no toolchain); the build + manual verification is Task 9 / the user's macOS run.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholar/Mindmap/MindmapCanvas.swift NimbleScholar/Mindmap/MindmapView.swift
git commit -m "feat(mindmap): tree canvas (two-layer render, keyboard, toolbar)"
```

---

## Task 9: End-to-end verification + docs

**Files:**
- Modify: `README.md`, `docs/ARCHITECTURE.md`, `CHANGELOG.md`

- [ ] **Step 1: Full Core test suite (macOS)**

Run: `cd NimbleScholarCore && swift test`
Expected: PASS — existing suites plus `TreeLayoutTests`, `MindmapNodeSizingTests`, and the new `MindmapStoreTests` cases (tree ops, snapshot/restore).

- [ ] **Step 2: Build + manual walkthrough (macOS)**

Run: `bash scripts/mac_bootstrap.sh full run`, switch to Mindmap mode, and verify:
1. A new map opens with an editable **root** node. Double-click → type → Return.
2. Select the root, press **Tab** → a child appears in edit mode; type → Return. Press **Tab** again → grandchild. Press **Return** on a child → a sibling.
3. **Arrows** move the selection (↑/↓ siblings, ← parent, → first child). **Space** collapses/expands a node with children (its subtree hides/shows and the tree re-tidies).
4. **Drag a node** onto another → a dashed drop indicator shows the target; release re-parents it; dropping onto its own descendant does nothing. **Dragging is smooth — no flicker.**
5. **Delete** removes the selected node + subtree (root refused). **⌘Z / ⌘⇧Z** undo/redo (including restoring a deleted subtree with its attached papers).
6. **Ctrl+↑/↓** reorders a node among its siblings. The **toolbar buttons** do the same as the shortcuts.
7. Drag a **shelf card onto a node** → chip; click chip → reader; ✕ → detach.
8. **Pan** (drag background) + **pinch / +−** zoom + **Fit** (scope button) frames the tree.
9. **Quit and relaunch** → the tree, collapsed state, and viewport persist.

If a keyboard shortcut misbehaves (macOS may capture Tab), confirm the equivalent **toolbar/context-menu** action works — that is the guaranteed path. Report any shortcut that needs tuning.

- [ ] **Step 3: Update docs**

In `README.md`, replace the existing "Mindmap" subsection body with the tree behavior: maps with a root; Tab = child, Return = sibling, arrows = navigate, Space = collapse; drag a node to re-parent; drag papers from the shelf onto nodes; undo/redo; Fit. In `docs/ARCHITECTURE.md`, update the `Core/Services/CanvasTransform.swift` row's neighbors to add `Core/Services/TreeLayout.swift` and `Core/Services/MindmapNodeSizing.swift`, and note the `v10-mindmap-tree` migration in the data-model section. In `CHANGELOG.md`, add a milestone entry dated 2026-06-17 describing the mindmap redesign (auto-layout tree, keyboard model, drag-to-reparent, undo/redo, flicker fix via structure-not-coordinates).

- [ ] **Step 4: Commit**

```bash
git add README.md docs/ARCHITECTURE.md CHANGELOG.md
git commit -m "docs(mindmap): document the auto-layout tree redesign"
```

---

## Notes for the implementer

- **Build order:** Tasks 6→7→8 form one compile unit (`MindmapView` references the rewritten canvas/node/VM). Implement them back-to-back; the project compiles again only at the end of Task 8. Core Tasks 1–5 build and test independently and keep the *existing* app compiling (additive changes only).
- **Flicker fix invariant:** never write `mindmap_nodes.x`/`y` from the tree code, and never write the model during a node drag — the drag uses a local `@GestureState` offset and commits a *structural* reparent on release. If you find yourself calling a store/VM mutation inside `.onChanged`, stop.
- **Keyboard is best-effort + fallback:** `.onKeyPress(.tab)`/`.return`/arrows/`.space` plus hidden `keyboardShortcut` buttons for ⌘Z/⌘⇧Z and Ctrl+↑/↓. The `CanvasToolbar` and node context menu mirror every op so the feature is fully usable even if a specific key is captured. Don't block on perfect key handling.
- **Dormant edges:** do not call `addEdge`/`deleteEdge`/`edges(forMap:)` or `graph(forMap:)` from the new tree UI; structure is `parent_id`. Those store methods remain for the (unused) `mindmap_edges` table.
- **Selection after structural ops:** the VM already moves selection sensibly (new node selected + editing; delete selects parent; reparent keeps the moved node). Keep that behavior.
</content>
