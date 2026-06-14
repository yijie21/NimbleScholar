import Foundation
import FlyingFox

/// JSON returned to the browser extension / bookmarklet on capture.
struct CaptureResponse: Codable {
    let ok: Bool
    let id: Int64?
    let error: String?
}

public final class CaptureServer {
    let server: HTTPServer
    let handler: CaptureHandler

    public init(port: UInt16 = 8765, handler: CaptureHandler) {
        self.handler = handler
        // Bind to IPv4 127.0.0.1 explicitly. FlyingFox's `.loopback` resolves to IPv6
        // `::1` only, which the browser extension / curl (both IPv4 127.0.0.1) can't reach.
        // `.inet(ip4:port:)` parses the IP string and can throw; "127.0.0.1" is always
        // valid, so try! never fires.
        self.server = HTTPServer(address: try! .inet(ip4: "127.0.0.1", port: port))
        Task { await registerRoutes() }
    }

    private func registerRoutes() async {
        let h = handler

        await server.appendRoute("OPTIONS *") { _ in
            HTTPResponse(statusCode: .noContent, headers: Self.cors)
        }

        await server.appendRoute("POST /api/capture") { req in
            do {
                let body = try await req.bodyData
                let payload = try JSONDecoder().decode(CapturePayload.self, from: body)
                let paper = try await h.capture(payload)
                let json = try JSONEncoder().encode(CaptureResponse(ok: true, id: paper.id, error: nil))
                return HTTPResponse(statusCode: .ok, headers: Self.json, body: json)
            } catch {
                let json = try? JSONEncoder().encode(CaptureResponse(ok: false, id: nil, error: "capture failed"))
                return HTTPResponse(statusCode: .badRequest, headers: Self.json,
                                    body: json ?? Data(#"{"ok":false}"#.utf8))
            }
        }
    }

    static let cors: [HTTPHeader: String] = [
        HTTPHeader("Access-Control-Allow-Origin"): "*",
        HTTPHeader("Access-Control-Allow-Methods"): "GET, POST, PUT, DELETE, OPTIONS",
        HTTPHeader("Access-Control-Allow-Headers"): "Content-Type",
    ]
    static var json: [HTTPHeader: String] {
        var h = cors; h[.contentType] = "application/json"; return h
    }

    public func run() async throws { try await server.run() }
    public func waitUntilListening() async throws { try await server.waitUntilListening() }
}
