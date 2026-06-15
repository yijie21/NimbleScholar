import XCTest
import GRDB
@testable import NimbleScholarCore

final class CodeReadyTests: XCTestCase {
    func testCodeReadyRoundTrips() throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        var p = Paper(title: "X")
        p.codeURL = "https://github.com/a/b"
        p.codeReady = true
        let saved = try store.create(p)
        XCTAssertTrue(try XCTUnwrap(store.paper(id: saved.id!)).codeReady)
    }
    func testCodeReadyDefaultsFalse() throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let saved = try store.create(Paper(title: "Y"))
        XCTAssertFalse(try XCTUnwrap(store.paper(id: saved.id!)).codeReady)
    }
}
