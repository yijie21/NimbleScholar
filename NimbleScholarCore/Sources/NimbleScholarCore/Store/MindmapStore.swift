import Foundation
import GRDB

/// Mindmap persistence. Shares `LibraryStore`'s `DatabaseQueue` (so the `v9-mindmap`
/// migration stays in the one migrator), but keeps mindmap CRUD out of `LibraryStore`.
/// Thread-safe: GRDB serializes the queue.
public final class MindmapStore: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) { self.dbQueue = dbQueue }
    public convenience init(library: LibraryStore) { self.init(dbQueue: library.dbQueue) }

    private func now() -> Int64 { Int64(Date().timeIntervalSince1970) }

    // MARK: - Maps

    /// All maps, most recently updated first.
    public func mindmaps() throws -> [Mindmap] {
        try dbQueue.read { try Mindmap.order(sql: "updated_at DESC, id DESC").fetchAll($0) }
    }

    @discardableResult
    public func createMindmap(name: String) throws -> Mindmap {
        var m = Mindmap(name: name)
        let ts = now(); m.createdAt = ts; m.updatedAt = ts
        try dbQueue.write { try m.insert($0) }
        return m
    }

    public func renameMindmap(id: Int64, name: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE mindmaps SET name = ?, updated_at = ? WHERE id = ?",
                           arguments: [name, now(), id])
        }
    }

    public func deleteMindmap(id: Int64) throws {
        _ = try dbQueue.write { try Mindmap.deleteOne($0, key: id) }
    }

    /// Persist the last viewport. Does NOT bump updated_at (so panning doesn't reorder the list).
    public func saveViewport(mapID: Int64, zoom: Double, offsetX: Double, offsetY: Double) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE mindmaps SET zoom = ?, offset_x = ?, offset_y = ? WHERE id = ?",
                           arguments: [zoom, offsetX, offsetY, mapID])
        }
    }

    // MARK: - Nodes

    public func nodes(forMap mapID: Int64) throws -> [MindmapNode] {
        try dbQueue.read {
            try MindmapNode.filter(sql: "mindmap_id = ?", arguments: [mapID])
                .order(sql: "created_at ASC, id ASC").fetchAll($0)
        }
    }

    @discardableResult
    public func createNode(mapID: Int64, text: String = "", x: Double, y: Double) throws -> MindmapNode {
        var n = MindmapNode(mindmapID: mapID, text: text, x: x, y: y)
        let ts = now(); n.createdAt = ts; n.updatedAt = ts
        try dbQueue.write { try n.insert($0) }
        return n
    }

    public func updateNodeText(id: Int64, text: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE mindmap_nodes SET text = ?, updated_at = ? WHERE id = ?",
                           arguments: [text, now(), id])
        }
    }

    public func moveNode(id: Int64, x: Double, y: Double) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE mindmap_nodes SET x = ?, y = ?, updated_at = ? WHERE id = ?",
                           arguments: [x, y, now(), id])
        }
    }

    public func deleteNode(id: Int64) throws {
        _ = try dbQueue.write { try MindmapNode.deleteOne($0, key: id) }
    }

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

    // MARK: - Edges

    public func edges(forMap mapID: Int64) throws -> [MindmapEdge] {
        try dbQueue.read {
            try MindmapEdge.filter(sql: "mindmap_id = ?", arguments: [mapID])
                .order(sql: "id ASC").fetchAll($0)
        }
    }

    /// Connect two nodes. Returns nil (no-op) for a self-loop or a duplicate
    /// (treated as undirected: A–B == B–A).
    @discardableResult
    public func addEdge(mapID: Int64, from: Int64, to: Int64) throws -> MindmapEdge? {
        guard from != to else { return nil }
        return try dbQueue.write { db -> MindmapEdge? in
            let exists = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(
                    SELECT 1 FROM mindmap_edges
                    WHERE mindmap_id = ?
                      AND ((from_node_id = ? AND to_node_id = ?)
                        OR (from_node_id = ? AND to_node_id = ?)))
                """, arguments: [mapID, from, to, to, from]) ?? false
            if exists { return nil }
            var e = MindmapEdge(mindmapID: mapID, fromNodeID: from, toNodeID: to)
            try e.insert(db)
            return e
        }
    }

    public func deleteEdge(id: Int64) throws {
        _ = try dbQueue.write { try MindmapEdge.deleteOne($0, key: id) }
    }

    // MARK: - Papers + graph

    public func attachPaper(nodeID: Int64, paperID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO mindmap_node_papers(node_id, paper_id) VALUES (?, ?)",
                           arguments: [nodeID, paperID])
        }
    }

    public func detachPaper(nodeID: Int64, paperID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM mindmap_node_papers WHERE node_id = ? AND paper_id = ?",
                           arguments: [nodeID, paperID])
        }
    }

    public func paperIDs(forNode nodeID: Int64) throws -> [Int64] {
        try dbQueue.read { db in
            try Int64.fetchAll(db, sql: "SELECT paper_id FROM mindmap_node_papers WHERE node_id = ? ORDER BY paper_id ASC",
                               arguments: [nodeID])
        }
    }

    /// Load a whole map (nodes + edges + node→paper links) in a few queries (no N+1).
    public func graph(forMap mapID: Int64) throws -> MindmapGraph {
        try dbQueue.read { db in
            let nodes = try MindmapNode.filter(sql: "mindmap_id = ?", arguments: [mapID])
                .order(sql: "created_at ASC, id ASC").fetchAll(db)
            let edges = try MindmapEdge.filter(sql: "mindmap_id = ?", arguments: [mapID])
                .order(sql: "id ASC").fetchAll(db)
            let rows = try Row.fetchAll(db, sql: """
                SELECT np.node_id AS nid, np.paper_id AS pid
                FROM mindmap_node_papers np
                JOIN mindmap_nodes n ON n.id = np.node_id
                WHERE n.mindmap_id = ?
                ORDER BY np.paper_id ASC
                """, arguments: [mapID])
            var byNode: [Int64: [Int64]] = [:]
            for r in rows {
                let nid: Int64 = r["nid"]
                byNode[nid, default: []].append(r["pid"])
            }
            return MindmapGraph(nodes: nodes, edges: edges, paperIDsByNode: byNode)
        }
    }
}
