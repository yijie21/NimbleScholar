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
}
