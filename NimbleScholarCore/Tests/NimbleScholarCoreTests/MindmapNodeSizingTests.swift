import XCTest
import CoreGraphics
@testable import NimbleScholarCore

final class MindmapNodeSizingTests: XCTestCase {
    func testWidthIsFixed() {
        XCTAssertEqual(MindmapNodeSizing.size(text: "x", chipCount: 0).width, MindmapNodeSizing.width)
        XCTAssertEqual(MindmapNodeSizing.size(text: String(repeating: "y", count: 200), chipCount: 5).width, MindmapNodeSizing.width)
    }
    func testHeightGrowsWithTextAndChips() {
        let short = MindmapNodeSizing.size(text: "hi", chipCount: 0).height
        let long = MindmapNodeSizing.size(text: String(repeating: "word ", count: 30), chipCount: 0).height
        let withChips = MindmapNodeSizing.size(text: "hi", chipCount: 3).height
        XCTAssertGreaterThan(long, short)
        XCTAssertGreaterThan(withChips, short)
    }
}
