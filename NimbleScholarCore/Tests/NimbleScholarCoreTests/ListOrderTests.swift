import XCTest
@testable import NimbleScholarCore

final class ListOrderTests: XCTestCase {
    private func paper(_ id: Int64, title: String = "t") -> Paper {
        var p = Paper(title: title)
        p.id = id
        return p
    }

    func testSameIDsKeepCurrentOrderWithFreshContents() {
        let current = [paper(1, title: "a"), paper(2, title: "b"), paper(3, title: "c")]
        let fresh = [paper(3, title: "c2"), paper(1, title: "a2"), paper(2, title: "b2")]
        let merged = ListOrder.preservingOrder(current: current, fresh: fresh)
        XCTAssertEqual(merged?.map { $0.id }, [1, 2, 3])
        XCTAssertEqual(merged?.map { $0.title }, ["a2", "b2", "c2"])
    }

    func testAddedPaperForcesResort() {
        XCTAssertNil(ListOrder.preservingOrder(current: [paper(1)], fresh: [paper(1), paper(2)]))
    }

    func testRemovedPaperForcesResort() {
        XCTAssertNil(ListOrder.preservingOrder(current: [paper(1), paper(2)], fresh: [paper(2)]))
    }

    func testDifferentIDsSameCountForcesResort() {
        XCTAssertNil(ListOrder.preservingOrder(current: [paper(1)], fresh: [paper(2)]))
    }

    func testMissingIDForcesResort() {
        var noID = Paper(title: "x")
        noID.id = nil
        XCTAssertNil(ListOrder.preservingOrder(current: [noID], fresh: [noID]))
    }

    func testEmptyListsKeepOrder() {
        XCTAssertEqual(ListOrder.preservingOrder(current: [], fresh: [])?.count, 0)
    }
}
