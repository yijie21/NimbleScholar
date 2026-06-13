import XCTest
import GRDB
import FlyingFox
@testable import NimbleScholarCore

final class CaptureServerTests: XCTestCase {
    func testPostApiCaptureCreatesPaper() async throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let handler = CaptureHandler(store: store) { _ in
            var m = PaperMetadata(); m.title = "Served"; return m
        }
        let server = CaptureServer(port: 8799, handler: handler)
        let task = Task { try await server.run() }
        defer { task.cancel() }
        try await server.waitUntilListening()

        var req = URLRequest(url: URL(string: "http://127.0.0.1:8799/api/capture")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = #"{"url":"https://arxiv.org/abs/2606.01234","tags":"x"}"#.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"ok\":true"))
        XCTAssertEqual(try store.allPapers().count, 1)
    }
}
