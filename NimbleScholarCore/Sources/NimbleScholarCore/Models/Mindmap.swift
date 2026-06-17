import GRDB

/// A named idea-graph. One row in `mindmaps`. `zoom`/`offset*` persist the last viewport.
public struct Mindmap: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var name: String
    public var zoom: Double = 1
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    public var createdAt: Int64 = 0
    public var updatedAt: Int64 = 0

    public static let databaseTableName = "mindmaps"
    enum CodingKeys: String, CodingKey {
        case id, name, zoom
        case offsetX = "offset_x", offsetY = "offset_y"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
    public init(id: Int64? = nil, name: String) { self.id = id; self.name = name }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

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
    public var content: String = ""
    public var createdAt: Int64 = 0
    public var updatedAt: Int64 = 0

    public static let databaseTableName = "mindmap_nodes"
    enum CodingKeys: String, CodingKey {
        case id, text, x, y, collapsed, content
        case mindmapID = "mindmap_id"
        case parentID = "parent_id", sortOrder = "sort_order"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
    public init(id: Int64? = nil, mindmapID: Int64, text: String = "", x: Double = 0, y: Double = 0) {
        self.id = id; self.mindmapID = mindmapID; self.text = text; self.x = x; self.y = y
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// An undirected connection between two nodes on a map. One row in `mindmap_edges`.
public struct MindmapEdge: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var mindmapID: Int64
    public var fromNodeID: Int64
    public var toNodeID: Int64

    public static let databaseTableName = "mindmap_edges"
    enum CodingKeys: String, CodingKey {
        case id
        case mindmapID = "mindmap_id"
        case fromNodeID = "from_node_id"
        case toNodeID = "to_node_id"
    }
    public init(id: Int64? = nil, mindmapID: Int64, fromNodeID: Int64, toNodeID: Int64) {
        self.id = id; self.mindmapID = mindmapID; self.fromNodeID = fromNodeID; self.toNodeID = toNodeID
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// The full contents of one map, loaded together (no N+1): nodes, edges, and the
/// paper ids attached to each node.
public struct MindmapGraph: Equatable {
    public var nodes: [MindmapNode]
    public var edges: [MindmapEdge]
    public var paperIDsByNode: [Int64: [Int64]]
    public init(nodes: [MindmapNode] = [], edges: [MindmapEdge] = [], paperIDsByNode: [Int64: [Int64]] = [:]) {
        self.nodes = nodes; self.edges = edges; self.paperIDsByNode = paperIDsByNode
    }
}

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
