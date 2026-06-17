import XCTest
import CoreGraphics
@testable import NimbleScholarCore

final class TreeLayoutTests: XCTestCase {
    let size = CGSize(width: 200, height: 40)

    func testSingleNodeAtOrigin() {
        let p = TreeLayout.positions(rootID: 1, childrenByParent: [:], collapsed: [], sizeOf: [1: size])
        XCTAssertEqual(p.count, 1)
        XCTAssertNotNil(p[1])
    }

    func testParentCenteredOnChildren() {
        // root(1) with children 2 and 3
        let children: [Int64: [Int64]] = [1: [2, 3]]
        let sizes: [Int64: CGSize] = [1: size, 2: size, 3: size]
        let p = TreeLayout.positions(rootID: 1, childrenByParent: children, collapsed: [], sizeOf: sizes)
        XCTAssertEqual(p.count, 3)
        // children are deeper (larger x) than root
        XCTAssertGreaterThan(p[2]!.x, p[1]!.x)
        XCTAssertEqual(p[2]!.x, p[3]!.x, accuracy: 0.001)        // same depth → same x
        // root y is the midpoint of its two children's y
        XCTAssertEqual(p[1]!.y, (p[2]!.y + p[3]!.y) / 2, accuracy: 0.001)
        // children don't overlap vertically
        XCTAssertNotEqual(p[2]!.y, p[3]!.y)
    }

    func testCollapsedExcludesChildren() {
        let children: [Int64: [Int64]] = [1: [2], 2: [3]]
        let sizes: [Int64: CGSize] = [1: size, 2: size, 3: size]
        let p = TreeLayout.positions(rootID: 1, childrenByParent: children, collapsed: [2], sizeOf: sizes)
        XCTAssertNotNil(p[1]); XCTAssertNotNil(p[2])
        XCTAssertNil(p[3])                                       // 3 hidden under collapsed 2
    }
}
