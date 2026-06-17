import XCTest
import CoreGraphics
@testable import NimbleScholarCore

final class MindmapNodeSizingTests: XCTestCase {
    func testWidthIsFixed() {
        XCTAssertEqual(MindmapNodeSizing.size(heading: "x", content: "", chipCount: 0, collapsed: false).width,
                       MindmapNodeSizing.width)
    }
    func testCollapsedIsHeadingOnly() {
        let collapsed = MindmapNodeSizing.size(heading: "hi", content: "a long body note here", chipCount: 3, collapsed: true)
        let headingOnly = MindmapNodeSizing.size(heading: "hi", content: "", chipCount: 0, collapsed: false)
        XCTAssertEqual(collapsed.height, headingOnly.height, accuracy: 0.0001)   // content + chips don't count when collapsed
    }
    func testExpandedGrowsWithContentAndChips() {
        let base = MindmapNodeSizing.size(heading: "hi", content: "", chipCount: 0, collapsed: false).height
        let withContent = MindmapNodeSizing.size(heading: "hi", content: String(repeating: "word ", count: 30), chipCount: 0, collapsed: false).height
        let withChips = MindmapNodeSizing.size(heading: "hi", content: "", chipCount: 3, collapsed: false).height
        XCTAssertGreaterThan(withContent, base)
        XCTAssertGreaterThan(withChips, base)
    }
}
