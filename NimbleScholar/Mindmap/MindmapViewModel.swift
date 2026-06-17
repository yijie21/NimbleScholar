import SwiftUI
import CoreGraphics
import NimbleScholarCore

enum NodeField: Equatable { case heading, content }
struct NodeEdit: Equatable { var nodeID: Int64; var field: NodeField }

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
    @Published var editing: NodeEdit?
    @Published var transform = CanvasTransform()

    struct DropTarget: Equatable { var parentID: Int64; var index: Int }

    private let store = AppEnvironment.shared.mindmaps
    private let activeKey = "activeMindmapID"
    private let seedGapX: CGFloat = 210   // place a child just right of its parent (≈10px gap at 200px width)
    private let seedGapY: CGFloat = 60    // vertical spacing between seeded siblings
    private var undoStack: [MapSnapshot] = []
    private var redoStack: [MapSnapshot] = []

    init() { reloadMaps() }

    var activeMap: Mindmap? { maps.first { $0.id == activeMapID } }
    var rootID: Int64? { tree.rootID }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
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
            sz[nid] = MindmapNodeSizing.size(heading: n.text, content: n.content,
                                             chipCount: tree.paperIDsByNode[nid]?.count ?? 0, collapsed: n.collapsed)
        }
        sizes = sz
        layout = Dictionary(uniqueKeysWithValues:
            tree.nodes.compactMap { n in n.id.map { ($0, CGPoint(x: n.x, y: n.y)) } })
    }

    // MARK: Structural ops (each: push undo → store → reload)

    private func pushUndo() {
        guard let id = activeMapID, let snap = try? store.snapshot(mapID: id) else { return }
        undoStack.append(snap); redoStack.removeAll()
    }

    /// Seed position for a freshly created child of `parentID` (beside the parent, stacked by index).
    private func seedChildPosition(parentID: Int64, siblingIndex: Int) -> CGPoint {
        let p = layout[parentID] ?? .zero
        return CGPoint(x: p.x + seedGapX, y: p.y + CGFloat(siblingIndex) * seedGapY)
    }

    func addChild(to parentID: Int64) {
        pushUndo()
        let index = tree.children(of: parentID).count   // new child's 0-based index (pre-insert count)
        guard let n = try? store.addChild(parentID: parentID, text: ""), let nid = n.id else { return }
        let seed = seedChildPosition(parentID: parentID, siblingIndex: index)
        try? store.moveNode(id: nid, x: Double(seed.x), y: Double(seed.y))
        reloadTree(); selectedNodeID = nid; editing = NodeEdit(nodeID: nid, field: .heading)
    }
    func addChildToSelected() { if let s = selectedNodeID { addChild(to: s) } }

    func addSibling(of nodeID: Int64) {
        if nodeID == tree.rootID { addChild(to: nodeID); return }   // root has no sibling
        pushUndo()
        guard let n = try? store.addSibling(of: nodeID, text: ""), let nid = n.id else { return }
        let ref = layout[nodeID] ?? .zero
        try? store.moveNode(id: nid, x: Double(ref.x), y: Double(ref.y + seedGapY))
        reloadTree(); selectedNodeID = nid; editing = NodeEdit(nodeID: nid, field: .heading)
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
            sz[nid] = MindmapNodeSizing.size(heading: n.text, content: n.content,
                                             chipCount: tree.paperIDsByNode[nid]?.count ?? 0, collapsed: n.collapsed)
        }
        let positions = TreeLayout.positions(rootID: root, childrenByParent: tree.childIDsByParent,
                                             collapsed: tree.collapsedSet, sizeOf: sz)
        pushUndo()
        try? store.setPositions(mapID: id, positions: positions)
        reloadTree()
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

    /// A node can collapse when it has anything to hide: children, content, or attached papers.
    func canCollapse(_ id: Int64) -> Bool {
        if tree.nodes.contains(where: { $0.parentID == id }) { return true }
        if let n = tree.nodes.first(where: { $0.id == id }), !n.content.isEmpty { return true }
        return !(tree.paperIDsByNode[id]?.isEmpty ?? true)
    }

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
        let fitScale = min((viewport.width - margin) / contentW, (viewport.height - margin) / contentH)
        let zoom = CanvasTransform.clampZoom(min(1.0, fitScale))
        let centerX = (minX + maxX) / 2, centerY = (minY + maxY) / 2
        let pan = CGSize(width: viewport.width / 2 - centerX * zoom,
                         height: viewport.height / 2 - centerY * zoom)
        updateTransform(CanvasTransform(zoom: zoom, pan: pan))
    }
}
