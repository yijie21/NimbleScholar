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
}
