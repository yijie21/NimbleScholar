import SwiftUI
import CoreGraphics
import NimbleScholarCore

/// Drives the mindmap canvas: the list of maps, the active map's graph, and the live
/// canvas transform. Edits mutate in-memory state and write through to MindmapStore;
/// node-drag positions and the viewport are debounced before hitting SQLite.
@MainActor
final class MindmapViewModel: ObservableObject {
    @Published var maps: [Mindmap] = []
    @Published var activeMapID: Int64?
    @Published var graph = MindmapGraph()
    @Published var transform = CanvasTransform()

    private let store = AppEnvironment.shared.mindmaps
    private let activeKey = "activeMindmapID"

    init() { reloadMaps() }

    var activeMap: Mindmap? { maps.first { $0.id == activeMapID } }

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
        flushMoves()
        guard let id = activeMapID, let map = maps.first(where: { $0.id == id }) else {
            graph = MindmapGraph(); return
        }
        graph = (try? store.graph(forMap: id)) ?? MindmapGraph()
        transform = CanvasTransform(zoom: CGFloat(map.zoom),
                                    pan: CGSize(width: map.offsetX, height: map.offsetY))
    }

    // MARK: Maps

    func selectMap(_ id: Int64) {
        flushMoves()
        activeMapID = id
        UserDefaults.standard.set(Int(id), forKey: activeKey)
        loadActive()
    }

    func createMap(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = try? store.createMindmap(name: trimmed.isEmpty ? "Untitled idea" : trimmed) else { return }
        reloadMaps()
        if let id = m.id { selectMap(id) }
    }

    func renameActiveMap(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = activeMapID, !trimmed.isEmpty else { return }
        try? store.renameMindmap(id: id, name: trimmed)
        reloadMaps()
    }

    func deleteActiveMap() {
        guard let id = activeMapID else { return }
        try? store.deleteMindmap(id: id)
        activeMapID = nil
        reloadMaps()
    }

    // MARK: Nodes

    func addNode(at canvasPoint: CGPoint, text: String = "", attaching paperID: Int64? = nil) {
        guard let mapID = activeMapID,
              let node = try? store.createNode(mapID: mapID, text: text,
                                               x: Double(canvasPoint.x), y: Double(canvasPoint.y))
        else { return }
        if let pid = paperID, let nid = node.id { try? store.attachPaper(nodeID: nid, paperID: pid) }
        loadActive()
    }

    func setNodeText(_ id: Int64, _ text: String) {
        try? store.updateNodeText(id: id, text: text)
        if let idx = graph.nodes.firstIndex(where: { $0.id == id }) { graph.nodes[idx].text = text }
    }

    func moveNode(_ id: Int64, to p: CGPoint) {
        if let idx = graph.nodes.firstIndex(where: { $0.id == id }) {
            graph.nodes[idx].x = Double(p.x); graph.nodes[idx].y = Double(p.y)
        }
        pendingMoves[id] = p
        scheduleFlushMoves()
    }

    func deleteNode(_ id: Int64) {
        pendingMoves[id] = nil
        try? store.deleteNode(id: id)
        loadActive()
    }

    // MARK: Edges

    func connect(_ from: Int64, _ to: Int64) {
        guard let mapID = activeMapID else { return }
        _ = try? store.addEdge(mapID: mapID, from: from, to: to)
        loadActive()
    }

    func deleteEdge(_ id: Int64) {
        try? store.deleteEdge(id: id)
        loadActive()
    }

    // MARK: Papers

    func attach(_ paperID: Int64, to nodeID: Int64) {
        try? store.attachPaper(nodeID: nodeID, paperID: paperID)
        loadActive()
    }

    func detach(_ paperID: Int64, from nodeID: Int64) {
        try? store.detachPaper(nodeID: nodeID, paperID: paperID)
        loadActive()
    }

    // MARK: Hit-testing (for edge-drag connect)

    /// The node whose ~constant-size screen card contains `screenPoint`, or nil.
    func nodeID(at screenPoint: CGPoint, transform: CanvasTransform) -> Int64? {
        let w: CGFloat = 200, h: CGFloat = 120
        for n in graph.nodes {
            let c = transform.screen(from: CGPoint(x: n.x, y: n.y))
            if CGRect(x: c.x - w/2, y: c.y - h/2, width: w, height: h).contains(screenPoint) {
                return n.id
            }
        }
        return nil
    }

    // MARK: - Debounced persistence

    private var pendingMoves: [Int64: CGPoint] = [:]
    private var moveWork: DispatchWorkItem?

    private func scheduleFlushMoves() {
        moveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushMoves() }
        moveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Persist any pending node positions now (called on drag end, map switch, reload).
    func flushMoves() {
        moveWork?.cancel(); moveWork = nil
        let moves = pendingMoves; pendingMoves.removeAll()
        for (id, p) in moves { try? store.moveNode(id: id, x: Double(p.x), y: Double(p.y)) }
    }

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
                                offsetX: Double(transform.pan.width),
                                offsetY: Double(transform.pan.height))
    }
}
