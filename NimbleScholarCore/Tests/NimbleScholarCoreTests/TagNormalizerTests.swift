import XCTest
@testable import NimbleScholarCore

final class TagNormalizerTests: XCTestCase {
    func testNormalizeSplitsLowercasesDedupesCollapses() {
        let result = TagNormalizer.normalize("  LLM, llm; Reading List ,, vla ")
        XCTAssertEqual(result, ["llm", "reading list", "vla"])
    }
}
