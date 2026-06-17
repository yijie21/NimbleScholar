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
}
