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
}
