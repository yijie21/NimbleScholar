import XCTest
import GRDB
@testable import NimbleScholarCore

final class ProjectCodeLinksTests: XCTestCase {
    func testLinksRoundTripThroughStore() throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        var p = Paper(title: "X")
        p.projectURL = "https://proj.github.io"
        p.codeURL = "https://github.com/a/b"
        p.linksScanned = true
        let saved = try store.create(p)
        let back = try XCTUnwrap(store.paper(id: saved.id!))
        XCTAssertEqual(back.projectURL, "https://proj.github.io")
        XCTAssertEqual(back.codeURL, "https://github.com/a/b")
        XCTAssertTrue(back.linksScanned)
    }
}
