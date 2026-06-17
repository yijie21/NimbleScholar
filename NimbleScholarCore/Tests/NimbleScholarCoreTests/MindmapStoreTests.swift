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
}
