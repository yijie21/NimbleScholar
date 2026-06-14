import XCTest
@testable import NimbleScholarCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertEqual(NimbleScholar.coreVersion, "1.0.0")
    }
}
