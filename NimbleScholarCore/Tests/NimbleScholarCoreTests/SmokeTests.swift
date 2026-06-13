import XCTest
@testable import NimbleScholarCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertEqual(NimbleScholarCore.version, "0.1.0")
    }
}
