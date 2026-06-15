import XCTest
@testable import NimbleScholarCore

final class UpdateFeedTests: XCTestCase {
    func testDownloadPrefix() {
        XCTAssertEqual(UpdateFeed.downloadPrefix,
            "https://github.com/yijie21/NimbleScholar/releases/download/updates/")
    }

    func testAppcastURLString() {
        XCTAssertEqual(UpdateFeed.appcastURLString,
            "https://github.com/yijie21/NimbleScholar/releases/download/updates/appcast.xml")
    }

    func testAppcastURLIsHTTPS() {
        XCTAssertEqual(UpdateFeed.appcastURL.scheme, "https")
    }
}
