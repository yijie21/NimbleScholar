import XCTest
import GRDB
@testable import NimbleScholarCore

final class MindmapStoreTests: XCTestCase {
    func makeStores() throws -> (LibraryStore, MindmapStore) {
        let lib = try LibraryStore(dbQueue: DatabaseQueue())   // in-memory; runs migrator
        return (lib, MindmapStore(library: lib))
    }

    func testCreateListRenameDeleteMap() throws {
        let (_, store) = try makeStores()
        XCTAssertEqual(try store.mindmaps().count, 0)
        let m = try store.createMindmap(name: "Backbone idea")
        XCTAssertNotNil(m.id)
        XCTAssertEqual(try store.mindmaps().map(\.name), ["Backbone idea"])

        try store.renameMindmap(id: m.id!, name: "Renamed")
        XCTAssertEqual(try store.mindmaps().first?.name, "Renamed")

        try store.saveViewport(mapID: m.id!, zoom: 1.5, offsetX: 10, offsetY: -20)
        let reloaded = try store.mindmaps().first!
        XCTAssertEqual(reloaded.zoom, 1.5, accuracy: 0.0001)
        XCTAssertEqual(reloaded.offsetX, 10, accuracy: 0.0001)
        XCTAssertEqual(reloaded.offsetY, -20, accuracy: 0.0001)

        try store.deleteMindmap(id: m.id!)
        XCTAssertEqual(try store.mindmaps().count, 0)
    }

    func testNodeCRUDAndMove() throws {
        let (_, store) = try makeStores()
        let m = try store.createMindmap(name: "M")
        let n = try store.createNode(mapID: m.id!, text: "Backbone", x: 5, y: 7)
        XCTAssertNotNil(n.id)
        XCTAssertEqual(try store.nodes(forMap: m.id!).count, 1)

        try store.updateNodeText(id: n.id!, text: "Backbone v2")
        try store.moveNode(id: n.id!, x: 100, y: 200)
        let reloaded = try store.nodes(forMap: m.id!).first!
        XCTAssertEqual(reloaded.text, "Backbone v2")
        XCTAssertEqual(reloaded.x, 100, accuracy: 0.0001)
        XCTAssertEqual(reloaded.y, 200, accuracy: 0.0001)

        try store.deleteNode(id: n.id!)
        XCTAssertEqual(try store.nodes(forMap: m.id!).count, 0)
    }

    func testEdgesDedupeAndSelfLoop() throws {
        let (_, store) = try makeStores()
        let m = try store.createMindmap(name: "M")
        let a = try store.createNode(mapID: m.id!, text: "A", x: 0, y: 0)
        let b = try store.createNode(mapID: m.id!, text: "B", x: 1, y: 1)

        XCTAssertNil(try store.addEdge(mapID: m.id!, from: a.id!, to: a.id!))   // self-loop rejected
        let e = try store.addEdge(mapID: m.id!, from: a.id!, to: b.id!)
        XCTAssertNotNil(e)
        XCTAssertNil(try store.addEdge(mapID: m.id!, from: a.id!, to: b.id!))   // duplicate
        XCTAssertNil(try store.addEdge(mapID: m.id!, from: b.id!, to: a.id!))   // duplicate (undirected)
        XCTAssertEqual(try store.edges(forMap: m.id!).count, 1)

        try store.deleteEdge(id: e!.id!)
        XCTAssertEqual(try store.edges(forMap: m.id!).count, 0)
    }

    func testDeletingNodeRemovesItsEdges() throws {
        let (_, store) = try makeStores()
        let m = try store.createMindmap(name: "M")
        let a = try store.createNode(mapID: m.id!, text: "A", x: 0, y: 0)
        let b = try store.createNode(mapID: m.id!, text: "B", x: 1, y: 1)
        _ = try store.addEdge(mapID: m.id!, from: a.id!, to: b.id!)
        try store.deleteNode(id: a.id!)
        XCTAssertEqual(try store.edges(forMap: m.id!).count, 0)   // cascade
    }

    func testAttachDetachAndGraph() throws {
        let (lib, store) = try makeStores()
        let paperA = try lib.create(Paper(title: "Backbone Net"))
        let paperB = try lib.create(Paper(title: "Big Dataset"))
        let m = try store.createMindmap(name: "Idea")
        let n1 = try store.createNode(mapID: m.id!, text: "backbone", x: 0, y: 0)
        let n2 = try store.createNode(mapID: m.id!, text: "dataset", x: 50, y: 0)
        _ = try store.addEdge(mapID: m.id!, from: n1.id!, to: n2.id!)

        try store.attachPaper(nodeID: n1.id!, paperID: paperA.id!)
        try store.attachPaper(nodeID: n1.id!, paperID: paperA.id!)   // idempotent
        try store.attachPaper(nodeID: n2.id!, paperID: paperB.id!)
        XCTAssertEqual(try store.paperIDs(forNode: n1.id!), [paperA.id!])

        let g = try store.graph(forMap: m.id!)
        XCTAssertEqual(g.nodes.count, 2)
        XCTAssertEqual(g.edges.count, 1)
        XCTAssertEqual(g.paperIDsByNode[n1.id!], [paperA.id!])
        XCTAssertEqual(g.paperIDsByNode[n2.id!], [paperB.id!])

        try store.detachPaper(nodeID: n1.id!, paperID: paperA.id!)
        XCTAssertEqual(try store.paperIDs(forNode: n1.id!), [])
    }

    func testDeletingPaperDetachesFromNodes() throws {
        let (lib, store) = try makeStores()
        let p = try lib.create(Paper(title: "P"))
        let m = try store.createMindmap(name: "M")
        let n = try store.createNode(mapID: m.id!, text: "x", x: 0, y: 0)
        try store.attachPaper(nodeID: n.id!, paperID: p.id!)
        try lib.deletePaper(id: p.id!)                       // FK cascade
        XCTAssertEqual(try store.paperIDs(forNode: n.id!), [])
    }

    func testDeletingMapRemovesEverything() throws {
        let (lib, store) = try makeStores()
        let p = try lib.create(Paper(title: "P"))
        let m = try store.createMindmap(name: "M")
        let a = try store.createNode(mapID: m.id!, text: "a", x: 0, y: 0)
        let b = try store.createNode(mapID: m.id!, text: "b", x: 1, y: 1)
        _ = try store.addEdge(mapID: m.id!, from: a.id!, to: b.id!)
        try store.attachPaper(nodeID: a.id!, paperID: p.id!)
        try store.deleteMindmap(id: m.id!)
        XCTAssertEqual(try store.nodes(forMap: m.id!).count, 0)
        XCTAssertEqual(try store.edges(forMap: m.id!).count, 0)
        XCTAssertEqual(try lib.allPapers().count, 1)         // the paper itself survives
    }

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

    func testSetParentKeepsSourceContiguous() throws {
        let (_, store) = try makeStores()
        let m = try store.createMindmap(name: "M")
        let root = try store.ensureRoot(mapID: m.id!, title: "M")
        let a = try store.addChild(parentID: root.id!, text: "A")   // sort_order 0
        let b = try store.addChild(parentID: root.id!, text: "B")   // sort_order 1
        let c = try store.addChild(parentID: root.id!, text: "C")   // sort_order 2
        // move B out to A; root should keep A,C contiguous (0,1), not (0,2)
        try store.setParent(nodeID: b.id!, newParentID: a.id!, index: 0)
        let tree = try store.tree(forMap: m.id!)
        let rootKids = tree.nodes.filter { $0.parentID == root.id! }.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(rootKids.map { $0.text }, ["A", "C"])
        XCTAssertEqual(rootKids.map { $0.sortOrder }, [0, 1])     // contiguous, gap closed
        XCTAssertEqual(tree.children(of: a.id!).map { $0.text }, ["B"])
        _ = c
    }

    func testEnsureRootAdoptsOrphanNodes() throws {
        let (_, store) = try makeStores()
        let m = try store.createMindmap(name: "M")
        // simulate a v9 map upgraded to v10: three free-form nodes, all parent_id NULL
        func insertOrphan(_ text: String) throws -> Int64 {
            var n = MindmapNode(mindmapID: m.id!, text: text)
            n.parentID = nil; n.sortOrder = 0
            try store.dbQueue.write { try n.insert($0) }
            return n.id!
        }
        let a = try insertOrphan("A"); _ = try insertOrphan("B"); _ = try insertOrphan("C")
        let root = try store.ensureRoot(mapID: m.id!, title: "M")
        XCTAssertEqual(root.id, a)                                   // first (lowest id) becomes root
        let tree = try store.tree(forMap: m.id!)
        XCTAssertEqual(tree.nodes.filter { $0.parentID == nil }.count, 1)   // exactly one root now
        XCTAssertEqual(Set(tree.children(of: root.id!).map { $0.text }), ["B", "C"])  // others adopted
    }

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
}
