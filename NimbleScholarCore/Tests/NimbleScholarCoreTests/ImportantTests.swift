import XCTest
import GRDB
@testable import NimbleScholarCore

final class ImportantTests: XCTestCase {
    func testSetImportantRoundTrips() throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let saved = try store.create(Paper(title: "X"))
        XCTAssertFalse(try XCTUnwrap(store.paper(id: saved.id!)).isImportant)
        try store.setImportant(paperID: saved.id!, important: true)
        XCTAssertTrue(try XCTUnwrap(store.paper(id: saved.id!)).isImportant)
        try store.setImportant(paperID: saved.id!, important: false)
        XCTAssertFalse(try XCTUnwrap(store.paper(id: saved.id!)).isImportant)
    }
}
