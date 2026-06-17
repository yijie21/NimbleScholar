# Mindmap Refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three mindmap refinements — (1) Tab-children spawn beside their parent (cap fit-zoom at 1.0× + small seed gap), (2) connector lines follow a dragged node in real time, (3) nodes gain a heading + content where collapse shows the heading only (hiding content, papers, and the child subtree).

**Architecture:** Core adds a `content` column (`v11` migration) + `updateNodeContent` + a heading/content/collapsed-aware `MindmapNodeSizing`. The app rewrites the node card to show heading + content, edits each field separately (VM tracks an `editing` target), gates collapse on "anything to hide", reports the dragged node's live center so the connectors `Canvas` follows it, and caps the fit zoom.

**Tech Stack:** Swift 5.9 / SwiftUI (macOS 14), GRDB 6.27, CoreGraphics. No new dependencies.

## Global Constraints

- Platform floor **macOS 14.0**, Swift tools **5.9**. **No new dependencies.**
- New migration named exactly **`v11-mindmap-content`**, additive/idempotent, registered after `v10-mindmap-tree` and before `return m` in `LibraryStore.migrator`.
- Flicker invariant stays: no per-frame **model** write during a drag; the connector follow re-renders only the single `Canvas`, not the nodes.
- Snapshot/restore must carry `content` (else undo blanks notes).
- **No Swift toolchain in this environment** — implementers WRITE tests but CANNOT run them; build/`swift test` happen on macOS. Don't fabricate test output; state execution is deferred.
- Core tests: `cd NimbleScholarCore && swift test`. App build: `bash scripts/mac_bootstrap.sh full run` (macOS).
- Builds on branch `feat/mindmap`.

## File Structure

**Core (modified):**
- `Models/Mindmap.swift` — `MindmapNode.content`.
- `Store/LibraryStore.swift` — `v11-mindmap-content` migration.
- `Store/MindmapStore.swift` — `updateNodeContent`; `content` in snapshot/restore INSERT.
- `Services/MindmapNodeSizing.swift` — new `size(heading:content:chipCount:collapsed:)`.
- Tests: `MindmapStoreTests.swift`, `MindmapNodeSizingTests.swift`.

**App (modified — coupled, compile together):**
- `Mindmap/MindmapViewModel.swift` — fit-zoom cap, `seedGap*`, `NodeField`/`NodeEdit` + `editing`, content edit, `canCollapse`, new sizing calls.
- `Mindmap/NodeView.swift` — `NodeDragInfo` (+live center), heading/content layout + editing, `canCollapse`/`editingField` params.
- `Mindmap/MindmapCanvas.swift` — connectors follow live center, drop indicator from `dragInfo.target`, `editing` gate, NodeView call site.

**Docs:** `README.md`, `docs/ARCHITECTURE.md`, `CHANGELOG.md`.

---

## Task 1: Core — `content` column, model, store, snapshot

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Models/Mindmap.swift`
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift`
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Store/MindmapStore.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapStoreTests.swift`

**Interfaces:**
- Produces: `MindmapNode.content: String`; `MindmapStore.updateNodeContent(id:content:)`; `content` persisted through `tree(forMap:)` and snapshot/restore.

- [ ] **Step 1: Write the failing test**

Append to `MindmapStoreTests.swift` (inside the class):

```swift
    func testNodeContentAndSnapshot() throws {
        let (_, store) = try makeStores()
        let m = try store.createMindmap(name: "M")
        let root = try store.ensureRoot(mapID: m.id!, title: "M")
        let a = try store.addChild(parentID: root.id!, text: "A")
        try store.updateNodeContent(id: a.id!, content: "a long note about A")
        let aBack = try store.tree(forMap: m.id!).nodes.first { $0.id == a.id! }!
        XCTAssertEqual(aBack.content, "a long note about A")

        let snap = try store.snapshot(mapID: m.id!)
        try store.updateNodeContent(id: a.id!, content: "changed")   // mutate
        try store.restore(mapID: m.id!, snap)                        // undo
        let restored = try store.tree(forMap: m.id!).nodes.first { $0.id == a.id! }!
        XCTAssertEqual(restored.content, "a long note about A")      // content survives undo
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd NimbleScholarCore && swift test --filter testNodeContentAndSnapshot`
Expected: FAIL — `value of type 'MindmapNode' has no member 'content'`.

- [ ] **Step 3: Add `content` to the model**

In `Models/Mindmap.swift`, in `MindmapNode`, add the stored property (after `collapsed`):

```swift
    public var collapsed: Bool = false
    public var content: String = ""
```

and add `content` to its `CodingKeys` (it maps to a same-named column):

```swift
    enum CodingKeys: String, CodingKey {
        case id, text, x, y, collapsed, content
        case mindmapID = "mindmap_id"
        case parentID = "parent_id", sortOrder = "sort_order"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
```

- [ ] **Step 4: Add the migration**

In `LibraryStore.swift`, inside `migrator`, immediately after the `m.registerMigration("v10-mindmap-tree")` block and before `return m`:

```swift
        m.registerMigration("v11-mindmap-content") { db in
            try db.alter(table: "mindmap_nodes") { t in
                t.add(column: "content", .text).notNull().defaults(to: "")
            }
        }
```

- [ ] **Step 5: Add `updateNodeContent` and put `content` in restore**

In `MindmapStore.swift`, add (next to `updateNodeText`, in the `// MARK: - Tree` section):

```swift
    public func updateNodeContent(id: Int64, content: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE mindmap_nodes SET content = ?, updated_at = ? WHERE id = ?",
                           arguments: [content, now(), id])
        }
    }
```

Then, in `restore(mapID:_:)`, update the explicit-id INSERT to include `content`. Replace the existing node-insert loop body:

```swift
            for n in snapshot.nodes {
                try db.execute(sql: """
                    INSERT INTO mindmap_nodes (id, mindmap_id, text, content, x, y, parent_id, sort_order, collapsed, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?)
                    """, arguments: [n.id, mapID, n.text, n.content, n.x, n.y, n.sortOrder, n.collapsed ? 1 : 0, n.createdAt, n.updatedAt])
            }
```

(`snapshot(mapID:)` fetches full `MindmapNode` rows, so `content` is captured automatically once the model has the column.)

- [ ] **Step 6: Run test to verify it passes**

Run: `cd NimbleScholarCore && swift test --filter testNodeContentAndSnapshot`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Models/Mindmap.swift \
        NimbleScholarCore/Sources/NimbleScholarCore/Store/LibraryStore.swift \
        NimbleScholarCore/Sources/NimbleScholarCore/Store/MindmapStore.swift \
        NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapStoreTests.swift
git commit -m "feat(mindmap): node content column (v11) + updateNodeContent + snapshot"
```

---

## Task 2: Core — heading/content/collapsed-aware sizing

**Files:**
- Modify: `NimbleScholarCore/Sources/NimbleScholarCore/Services/MindmapNodeSizing.swift`
- Test: `NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapNodeSizingTests.swift`

**Interfaces:**
- Produces: `MindmapNodeSizing.size(heading:content:chipCount:collapsed:) -> CGSize` (replaces `size(text:chipCount:)`).

> NOTE: This replaces the old `size(text:chipCount:)`, so the app's `MindmapViewModel` callers stop compiling until Task 3. The Core package itself compiles and its tests pass after this task.

- [ ] **Step 1: Replace the tests**

Replace the body of `MindmapNodeSizingTests.swift` with:

```swift
import XCTest
import CoreGraphics
@testable import NimbleScholarCore

final class MindmapNodeSizingTests: XCTestCase {
    func testWidthIsFixed() {
        XCTAssertEqual(MindmapNodeSizing.size(heading: "x", content: "", chipCount: 0, collapsed: false).width,
                       MindmapNodeSizing.width)
    }
    func testCollapsedIsHeadingOnly() {
        let collapsed = MindmapNodeSizing.size(heading: "hi", content: "a long body note here", chipCount: 3, collapsed: true)
        let headingOnly = MindmapNodeSizing.size(heading: "hi", content: "", chipCount: 0, collapsed: false)
        XCTAssertEqual(collapsed.height, headingOnly.height, accuracy: 0.0001)   // content + chips don't count when collapsed
    }
    func testExpandedGrowsWithContentAndChips() {
        let base = MindmapNodeSizing.size(heading: "hi", content: "", chipCount: 0, collapsed: false).height
        let withContent = MindmapNodeSizing.size(heading: "hi", content: String(repeating: "word ", count: 30), chipCount: 0, collapsed: false).height
        let withChips = MindmapNodeSizing.size(heading: "hi", content: "", chipCount: 3, collapsed: false).height
        XCTAssertGreaterThan(withContent, base)
        XCTAssertGreaterThan(withChips, base)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd NimbleScholarCore && swift test --filter MindmapNodeSizingTests`
Expected: FAIL — `incorrect argument label` / no matching `size` overload.

- [ ] **Step 3: Replace the implementation**

Replace the body of `MindmapNodeSizing.swift`:

```swift
import CoreGraphics

/// Pure node-size estimate for the tree layout (real text measurement is a later refinement).
/// Fixed width. Collapsed → heading height only; expanded → heading + content lines + chips.
public enum MindmapNodeSizing {
    public static let width: CGFloat = 200
    private static let charsPerLine = 22
    private static let lineHeight: CGFloat = 18
    private static let verticalPadding: CGFloat = 18
    private static let chipHeight: CGFloat = 22

    private static func lines(_ s: String) -> Int {
        max(1, Int((Double(s.count) / Double(charsPerLine)).rounded(.up)))
    }

    public static func size(heading: String, content: String, chipCount: Int, collapsed: Bool) -> CGSize {
        var height = CGFloat(lines(heading)) * lineHeight + verticalPadding
        if !collapsed {
            if !content.isEmpty { height += CGFloat(lines(content)) * lineHeight + 4 }
            height += CGFloat(max(0, chipCount)) * chipHeight
        }
        return CGSize(width: width, height: height)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd NimbleScholarCore && swift test --filter MindmapNodeSizingTests`
Expected: PASS.

- [ ] **Step 5: Run the whole Core suite**

Run: `cd NimbleScholarCore && swift test`
Expected: PASS (Core compiles; nothing in Core calls the old `size(text:chipCount:)`).

- [ ] **Step 6: Commit**

```bash
git add NimbleScholarCore/Sources/NimbleScholarCore/Services/MindmapNodeSizing.swift \
        NimbleScholarCore/Tests/NimbleScholarCoreTests/MindmapNodeSizingTests.swift
git commit -m "feat(mindmap): heading/content/collapsed-aware node sizing"
```

---

## Task 3: VM — fit-zoom cap, seed gap, edit target, content edit, canCollapse, sizing

**Files:**
- Modify: `NimbleScholar/Mindmap/MindmapViewModel.swift`

**Interfaces:**
- Consumes: `MindmapStore.updateNodeContent` (Task 1), `MindmapNodeSizing.size(heading:content:chipCount:collapsed:)` (Task 2).
- Produces (consumed by Tasks 4–5): `enum NodeField { case heading, content }` (Equatable); `struct NodeEdit { var nodeID: Int64; var field: NodeField }` (Equatable); `@Published var editing: NodeEdit?` (REPLACES `editingNodeID`); `beginEdit(_:)`, `beginEditContent(_:)`, `commitHeading(_:)`, `commitContent(_:)`, `cancelEdit()`; `canCollapse(_:) -> Bool`.

> NOTE: removing `editingNodeID` and changing sizing calls breaks `NodeView`/`MindmapCanvas` until Tasks 4–5. Expected.

- [ ] **Step 1: Add the edit-target types and replace `editingNodeID`**

In `MindmapViewModel.swift`, near the top of the file (after the `import`s, before or near the `MoveDirection` enum), add:

```swift
enum NodeField: Equatable { case heading, content }
struct NodeEdit: Equatable { var nodeID: Int64; var field: NodeField }
```

Replace the published property declaration `@Published var editingNodeID: Int64?` with:

```swift
    @Published var editing: NodeEdit?
```

- [ ] **Step 2: Replace the edit methods**

Replace `beginEdit`/`commitEdit`/`cancelEdit` (the `// MARK: Text edit` block) with:

```swift
    func beginEdit(_ nodeID: Int64) { selectedNodeID = nodeID; editing = NodeEdit(nodeID: nodeID, field: .heading) }
    func beginEditContent(_ nodeID: Int64) { selectedNodeID = nodeID; editing = NodeEdit(nodeID: nodeID, field: .content) }
    func commitHeading(_ text: String) {
        guard let e = editing, e.field == .heading else { return }
        editing = nil
        pushUndo(); try? store.updateNodeText(id: e.nodeID, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        reloadTree()
    }
    func commitContent(_ text: String) {
        guard let e = editing, e.field == .content else { return }
        editing = nil
        pushUndo(); try? store.updateNodeContent(id: e.nodeID, content: text.trimmingCharacters(in: .whitespacesAndNewlines))
        reloadTree()
    }
    func cancelEdit() { editing = nil }
```

- [ ] **Step 3: Update `addChild`/`addSibling` to use the new edit target**

In `addChild(to:)`, change the trailing `selectedNodeID = nid; editingNodeID = nid` to:

```swift
        reloadTree(); selectedNodeID = nid; editing = NodeEdit(nodeID: nid, field: .heading)
```

In `addSibling(of:)`, change the trailing `selectedNodeID = nid; editingNodeID = nid` to:

```swift
        reloadTree(); selectedNodeID = nid; editing = NodeEdit(nodeID: nid, field: .heading)
```

- [ ] **Step 4: Add `canCollapse` and update sizing calls**

Add `canCollapse` (e.g. just below `commitContent`/`cancelEdit`):

```swift
    /// A node can collapse when it has anything to hide: children, content, or attached papers.
    func canCollapse(_ id: Int64) -> Bool {
        if tree.nodes.contains(where: { $0.parentID == id }) { return true }
        if let n = tree.nodes.first(where: { $0.id == id }), !n.content.isEmpty { return true }
        return !(tree.paperIDsByNode[id]?.isEmpty ?? true)
    }
```

In `relayout()`, replace the size computation line:

```swift
            sz[nid] = MindmapNodeSizing.size(heading: n.text, content: n.content,
                                             chipCount: tree.paperIDsByNode[nid]?.count ?? 0, collapsed: n.collapsed)
```

In `tidy()`, replace the size computation line inside its loop:

```swift
            sz[nid] = MindmapNodeSizing.size(heading: n.text, content: n.content,
                                             chipCount: tree.paperIDsByNode[nid]?.count ?? 0, collapsed: n.collapsed)
```

- [ ] **Step 5: Cap fit zoom + tighten the seed gap**

Change the two seed constants:

```swift
    private let seedGapX: CGFloat = 210   // place a child just right of its parent (≈10px gap at 200px width)
    private let seedGapY: CGFloat = 60    // vertical spacing between seeded siblings
```

In `fit(in:)`, replace the zoom computation so it only scales DOWN (never zooms a small tree up):

```swift
        let fitScale = min((viewport.width - margin) / contentW, (viewport.height - margin) / contentH)
        let zoom = CanvasTransform.clampZoom(min(1.0, fitScale))
```

(Replaces the existing `let zoom = CanvasTransform.clampZoom(min((viewport.width - margin) / contentW, (viewport.height - margin) / contentH))`.)

- [ ] **Step 6: Self-verify compile-correctness (no build)**

Confirm by reading: no remaining `editingNodeID` references in the VM; `editing`/`NodeEdit`/`NodeField` declared; `commitHeading`/`commitContent`/`beginEditContent`/`canCollapse` present; `relayout`/`tidy` call the new `size(heading:content:chipCount:collapsed:)`; `fit` caps at 1.0. NodeView/Canvas still reference `editingNodeID`/old sizing/old NodeView params → they break until Tasks 4–5 (expected).

- [ ] **Step 7: Commit**

```bash
git add NimbleScholar/Mindmap/MindmapViewModel.swift
git commit -m "feat(mindmap): VM edit-target, content edit, canCollapse, fit cap, seed gap"
```

---

## Task 4: NodeView — heading/content layout, content editing, live drag center

**Files:**
- Modify: `NimbleScholar/Mindmap/NodeView.swift`

**Interfaces:**
- Consumes: `vm.editing`, `vm.beginEdit`, `vm.beginEditContent`, `vm.commitHeading`, `vm.commitContent`, `vm.cancelEdit`, `vm.canCollapse`, `vm.toggleCollapse`, `vm.layout`, `vm.transform`, `vm.dropTarget`, `vm.reparent(_:to:index:at:)`, `vm.move(_:to:)`, `MindmapViewModel.DropTarget`, `NodeField` (Task 3).
- Produces (consumed by Task 5): `struct NodeDragInfo { var nodeID: Int64; var center: CGPoint; var target: MindmapViewModel.DropTarget? }`; `NodeView(node:size:selected:editingField:paperIDs:canCollapse:dragInfo:coordSpace:)` (Equatable).

- [ ] **Step 1: Replace `NodeDragInfo` and the `NodeView` declaration/Equatable**

In `NodeView.swift`, replace the `NodeDragInfo` struct:

```swift
/// Transient drag state shared with the canvas (the dragged node, its live canvas center, and the
/// current re-parent target). The connectors layer reads `center` so edges follow the drag in real
/// time; the drop indicator reads `target`.
struct NodeDragInfo: Equatable {
    var nodeID: Int64
    var center: CGPoint
    var target: MindmapViewModel.DropTarget?
}
```

Replace the `NodeView` stored properties + Equatable (the `let editing: Bool` / `let hasChildren: Bool` lines and `==`):

```swift
    let node: MindmapNode
    let size: CGSize
    let selected: Bool
    let editingField: NodeField?
    let paperIDs: [Int64]
    let canCollapse: Bool
    @Binding var dragInfo: NodeDragInfo?
    let coordSpace: String

    @GestureState private var dragOffset: CGSize = .zero
    @State private var draft = ""
    @State private var contentDraft = ""
    @FocusState private var headingFocused: Bool
    @FocusState private var contentFocused: Bool
    @State private var dropTargeted = false

    private let reparentThreshold: CGFloat = 24   // min drag distance (screen pts) to re-parent
    private var nodeID: Int64 { node.id ?? -1 }
    private var isEditingHeading: Bool { editingField == .heading }
    private var isEditingContent: Bool { editingField == .content }

    static func == (l: NodeView, r: NodeView) -> Bool {
        l.node == r.node && l.size == r.size && l.selected == r.selected
            && l.editingField == r.editingField && l.paperIDs == r.paperIDs && l.canCollapse == r.canCollapse
    }
```

- [ ] **Step 2: Replace the body's heading/content layout**

Replace the `body`'s `VStack { ... }` content (the `HStack` heading row + the chips `ForEach`) with heading row + content + chips:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if canCollapse {
                    Button { vm.toggleCollapse(nodeID) } label: {
                        Image(systemName: node.collapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                if isEditingHeading {
                    TextField("Idea", text: $draft)
                        .textFieldStyle(.plain).font(.callout.bold())
                        .focused($headingFocused)
                        .onSubmit { vm.commitHeading(draft) }
                        .onExitCommand { vm.cancelEdit() }
                        .onChange(of: headingFocused) { _, f in if !f { vm.commitHeading(draft) } }
                        .onAppear { draft = node.text; headingFocused = true }
                } else {
                    Text(node.text.isEmpty ? "Untitled" : node.text)
                        .font(.callout.bold())
                        .foregroundStyle(node.text.isEmpty ? .secondary : .primary)
                        .onTapGesture(count: 2) { vm.beginEdit(nodeID) }
                }
            }
            if !node.collapsed {
                if isEditingContent {
                    TextField("Note", text: $contentDraft, axis: .vertical)
                        .textFieldStyle(.plain).font(.caption)
                        .focused($contentFocused)
                        .onExitCommand { vm.cancelEdit() }
                        .onChange(of: contentFocused) { _, f in if !f { vm.commitContent(contentDraft) } }
                        .onAppear { contentDraft = node.content; contentFocused = true }
                } else {
                    Text(node.content.isEmpty ? "Add note…" : node.content)
                        .font(.caption)
                        .foregroundStyle(node.content.isEmpty ? .tertiary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture(count: 2) { vm.beginEditContent(nodeID) }
                }
                ForEach(attachedPapers) { p in
                    NodePaperChip(paper: p,
                                  onOpen: { libraryVM.openReader(p) },
                                  onRemove: { if let pid = p.id { vm.detach(pid, from: nodeID) } })
                }
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
        .gesture(moveOrReparentGesture)
        .onTapGesture { vm.select(nodeID) }
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let pid = Int64(s) else { return false }
            vm.attach(pid, to: nodeID); return true
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button("Add Child") { vm.addChild(to: nodeID) }
            if nodeID != vm.rootID { Button("Add Sibling") { vm.addSibling(of: nodeID) } }
            Button("Edit Heading") { vm.beginEdit(nodeID) }
            Button("Edit Note") { vm.beginEditContent(nodeID) }
            if canCollapse {
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
```

(The node-wide `.onTapGesture(count: 2)` is removed — double-tap now lives on the heading and content text specifically. The single-tap select stays.)

- [ ] **Step 3: Report the live center on every drag frame**

Replace `moveOrReparentGesture`'s `.onChanged` so it publishes the live center every frame (and the target when past the threshold):

```swift
            .onChanged { value in
                let zoom = vm.transform.zoom
                let old = vm.layout[nodeID] ?? .zero
                let center = CGPoint(x: old.x + value.translation.width / zoom,
                                     y: old.y + value.translation.height / zoom)
                let dragged = hypot(value.translation.width, value.translation.height)
                let cursor = vm.transform.canvas(from: value.location)
                let target: MindmapViewModel.DropTarget? =
                    (dragged >= reparentThreshold && nodeID != vm.rootID)
                    ? vm.dropTarget(forDragged: nodeID, at: cursor) : nil
                dragInfo = NodeDragInfo(nodeID: nodeID, center: center, target: target)
            }
```

(`.onEnded` is unchanged — it still computes `dropPoint`/`cursor` and calls `vm.reparent(...)` or `vm.move(...)`, then `defer { dragInfo = nil }`.)

- [ ] **Step 4: Self-verify compile-correctness**

Confirm: `NodeView` signature is `node:size:selected:editingField:paperIDs:canCollapse:dragInfo:coordSpace:` (Task 5 must match it); `NodeDragInfo` carries `center` + `target`; `.onChanged` does NO model mutation (only the `dragInfo` binding + `@GestureState`); content editing commits on blur/Esc; the collapse chevron + content/chips gate on `node.collapsed`; `vm.commitHeading`/`commitContent`/`beginEditContent`/`canCollapse` exist (Task 3). `MindmapViewModel.DropTarget` is referenced fully-qualified.

- [ ] **Step 5: Commit**

```bash
git add NimbleScholar/Mindmap/NodeView.swift
git commit -m "feat(mindmap): node heading/content layout, content editing, live drag center"
```

---

## Task 5: Canvas — connectors follow the drag, edit gate, NodeView call site

**Files:**
- Modify: `NimbleScholar/Mindmap/MindmapCanvas.swift`

**Interfaces:**
- Consumes: `NodeView(node:size:selected:editingField:paperIDs:canCollapse:dragInfo:coordSpace:)` + `NodeDragInfo{nodeID,center,target}` (Task 4); `vm.editing`, `vm.canCollapse` (Task 3).

- [ ] **Step 1: Make the connectors follow the live drag center**

In `MindmapCanvas.swift`, replace the `connectors` computed property:

```swift
    private var connectors: some View {
        Canvas { ctx, _ in
            func pos(_ id: Int64) -> CGPoint? {
                if let d = dragInfo, d.nodeID == id { return d.center }   // dragged node: live position
                return vm.layout[id]
            }
            for n in vm.tree.nodes {
                guard let nid = n.id, let pid = n.parentID,
                      let cc = pos(nid), let pc = pos(pid) else { continue }
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
```

- [ ] **Step 2: Drop indicator reads `dragInfo.target`**

Replace the `dropIndicator` computed property:

```swift
    @ViewBuilder private var dropIndicator: some View {
        if let info = dragInfo, let target = info.target,
           let c = vm.layout[target.parentID], let sz = vm.sizes[target.parentID] {
            let screen = vm.transform.screen(from: c)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5]))
                .frame(width: sz.width * vm.transform.zoom, height: sz.height * vm.transform.zoom)
                .position(screen)
                .allowsHitTesting(false)
        }
    }
```

- [ ] **Step 3: Update the NodeView call site**

In `nodes(in:)`, replace the `NodeView(...)` call:

```swift
        return ForEach(visible) { n in
            let nid = n.id ?? -1
            NodeView(node: n,
                     size: vm.sizes[nid] ?? CGSize(width: 200, height: 40),
                     selected: vm.selectedNodeID == nid,
                     editingField: vm.editing?.nodeID == nid ? vm.editing?.field : nil,
                     paperIDs: vm.tree.paperIDsByNode[nid] ?? [],
                     canCollapse: vm.canCollapse(nid),
                     dragInfo: $dragInfo,
                     coordSpace: coordSpace)
                .equatable()
                .environmentObject(vm)
                .environmentObject(libraryVM)
                .position(vm.transform.screen(from: vm.layout[nid] ?? .zero))
        }
```

- [ ] **Step 4: Gate keyboard/refocus on `vm.editing`**

Replace the refocus `onChange` and the nine `onKeyPress` lines (they reference `vm.editingNodeID`) with the `vm.editing` versions:

```swift
            .onChange(of: vm.editing) { _, editing in if editing == nil { focused = true } }
            .onChange(of: vm.activeMapID, initial: true) { _, _ in didFitMapID = nil; fitIfNeeded(geo.size) }
            .onChange(of: vm.layout) { _, _ in fitIfNeeded(geo.size) }
            .overlay(alignment: .bottomTrailing) { zoomControls(viewport: geo.size) }
            .background(keyShortcuts)
            .simultaneousGesture(magnifyGesture)
            .onKeyPress(.tab) { guard vm.editing == nil else { return .ignored }; vm.addChildToSelected(); return .handled }
            .onKeyPress(.return) { if vm.editing == nil { vm.addSiblingToSelected(); return .handled }; return .ignored }
            .onKeyPress(.deleteForward) { guard vm.editing == nil else { return .ignored }; vm.deleteSelectedSubtree(); return .handled }
            .onKeyPress(KeyEquivalent("\u{7f}")) { guard vm.editing == nil else { return .ignored }; vm.deleteSelectedSubtree(); return .handled }   // Backspace
            .onKeyPress(.space) { guard vm.editing == nil else { return .ignored }; if let s = vm.selectedNodeID { vm.toggleCollapse(s) }; return .handled }
            .onKeyPress(.upArrow) { guard vm.editing == nil else { return .ignored }; vm.navigate(.up); return .handled }
            .onKeyPress(.downArrow) { guard vm.editing == nil else { return .ignored }; vm.navigate(.down); return .handled }
            .onKeyPress(.leftArrow) { guard vm.editing == nil else { return .ignored }; vm.navigate(.left); return .handled }
            .onKeyPress(.rightArrow) { guard vm.editing == nil else { return .ignored }; vm.navigate(.right); return .handled }
```

- [ ] **Step 5: Self-verify compile-correctness**

Confirm: the `connectors` `Canvas` reads `dragInfo` (`@State`) so it re-renders each drag frame and the dragged node's edges use `d.center`; `dropIndicator` uses `info.target`; the `NodeView(...)` call matches Task 4's signature (`editingField:`/`canCollapse:`); no `vm.editingNodeID` references remain; `.onChange(of: vm.editing)` compiles (`NodeEdit` is `Equatable`). The feature compiles after this task.

- [ ] **Step 6: Commit**

```bash
git add NimbleScholar/Mindmap/MindmapCanvas.swift
git commit -m "feat(mindmap): connectors follow live drag; edit-target gate; NodeView call site"
```

---

## Task 6: Verification + docs

**Files:** `README.md`, `docs/ARCHITECTURE.md`, `CHANGELOG.md`

- [ ] **Step 1: Full Core test suite (macOS)**

Run: `cd NimbleScholarCore && swift test`
Expected: PASS — incl. `testNodeContentAndSnapshot` and the updated `MindmapNodeSizingTests`.

- [ ] **Step 2: Build + manual walkthrough (macOS)**

Run: `bash scripts/mac_bootstrap.sh full run`, switch to Mindmap, and verify:
1. New map opens at ~100% zoom; **Tab** spawns a child **just beside** its parent (not far away).
2. **Drag a node** → its parent/child connector lines **follow in real time** (no lag, no flicker); release snaps clean.
3. **Double-click the heading** edits the title; **double-click the body** ("Add note…") edits the content; Esc cancels, click-away commits.
4. **Collapse** a node that has content / papers / children → it shows **just the heading** (▶); expand (▾) shows content + chips + child subtree again.
5. The collapse chevron appears even on a **leaf node that only has a note or papers**.
6. **⌘Z** undoes a content edit (note comes back); quit & relaunch → content + collapsed state persist.
7. Existing behavior intact: arrows/Delete/Tidy/undo/pan/zoom/Fit, paper drag-attach + chip open.

- [ ] **Step 3: Update docs**

In `README.md` Mindmap subsection: note each node has a **heading + optional note (content)**; **collapse shows the heading only** (hiding the note, papers, and child subtree); double-click the heading vs. the note to edit each; dragging a node moves its connector lines with it. In `docs/ARCHITECTURE.md`: note the `v11-mindmap-content` migration (adds `content`) and that `MindmapNodeSizing` is heading/content/collapsed-aware. In `CHANGELOG.md`: add a 2026-06-17 entry — node heading + content with collapse-to-heading; connector lines follow drags; Tab-children spawn beside their parent (fit-zoom capped at 1.0).

- [ ] **Step 4: Commit**

```bash
git add README.md docs/ARCHITECTURE.md CHANGELOG.md
git commit -m "docs(mindmap): heading/content, collapse-to-heading, edge-follow, seed fixes"
```

---

## Notes for the implementer

- **Build order:** Tasks 3→4→5 are one compile unit (VM↔NodeView↔Canvas reference each other). Implement back-to-back; the app compiles again at the end of Task 5. Core Tasks 1–2 build/test on their own (Task 2 intentionally breaks the *app's* sizing callers, fixed in Task 3).
- **Flicker invariant:** the edge-follow re-renders only the connectors `Canvas` (it reads the `dragInfo` `@State`); the `NodeView`s stay `Equatable`-isolated. Never write the model in a drag `.onChanged`.
- **Seed distance:** the dominant fix is the fit-zoom cap at 1.0 (a lone-root map previously zoomed to 2.5×, exaggerating the offset). Keep `seedGapX` ≥ ~205 so a 200px-wide child doesn't overlap its parent.
- **Content commit:** the content field commits on blur (click-away) or Esc-cancel; Return inside the vertical-axis note inserts a newline (that's fine). The heading field commits on Return/blur.
- **Don't reintroduce `editingNodeID`:** every reference becomes `vm.editing` (an optional `NodeEdit`); NodeView receives `editingField: NodeField?`.
</content>
