import XCTest
import GRDB
@testable import NimbleScholarCore

final class ToReadTagTests: XCTestCase {
    func testRemoveTagFromPaper() throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let p = try store.create(Paper(title: "X"))
        try store.setTags(paperID: p.id!, tags: ["to-read", "vla"])
        try store.removeTag("to-read", fromPaper: p.id!)
        XCTAssertEqual(Set(try store.tags(forPaper: p.id!)), ["vla"])
        // removing a tag the paper doesn't have is a no-op
        try store.removeTag("nope", fromPaper: p.id!)
        XCTAssertEqual(Set(try store.tags(forPaper: p.id!)), ["vla"])
    }
}
