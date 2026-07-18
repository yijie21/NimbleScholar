import XCTest
@testable import NimbleScholarCore

final class ProxyPACTests: XCTestCase {
    func testScriptRoutesProxyThenDirect() {
        let script = ProxyPAC.script(host: "127.0.0.1", port: 7892)
        XCTAssertEqual(script,
            "function FindProxyForURL(url, host) { return \"PROXY 127.0.0.1:7892; DIRECT\"; }")
    }

    func testHostIsTrimmed() {
        XCTAssertEqual(ProxyPAC.script(host: "  proxy.example.com \n", port: 8080),
            "function FindProxyForURL(url, host) { return \"PROXY proxy.example.com:8080; DIRECT\"; }")
    }

    func testInvalidPortsRejected() {
        XCTAssertNil(ProxyPAC.script(host: "127.0.0.1", port: 0))
        XCTAssertNil(ProxyPAC.script(host: "127.0.0.1", port: -1))
        XCTAssertNil(ProxyPAC.script(host: "127.0.0.1", port: 70000))
    }

    func testHostsThatCouldEscapeThePACStringRejected() {
        XCTAssertNil(ProxyPAC.script(host: "", port: 7892))
        XCTAssertNil(ProxyPAC.script(host: "   ", port: 7892))
        XCTAssertNil(ProxyPAC.script(host: "127.0.0.1\"; evil()", port: 7892))
        XCTAssertNil(ProxyPAC.script(host: "host; DIRECT", port: 7892))
        XCTAssertNil(ProxyPAC.script(host: "::1", port: 7892))            // IPv6 literal
        XCTAssertNil(ProxyPAC.script(host: "host name", port: 7892))
        XCTAssertNil(ProxyPAC.script(host: String(repeating: "a", count: 300), port: 7892))
    }
}
