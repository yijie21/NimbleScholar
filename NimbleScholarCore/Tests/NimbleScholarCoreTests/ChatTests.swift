import XCTest
import GRDB
@testable import NimbleScholarCore

final class ChatTests: XCTestCase {
    func testChatHistoryRoundTripAndClear() throws {
        let store = try LibraryStore(dbQueue: DatabaseQueue())
        let p = try store.create(Paper(title: "P"))
        try store.appendChatMessage(ChatMessage(paperId: p.id!, role: "user", content: "hi"))
        try store.appendChatMessage(ChatMessage(paperId: p.id!, role: "assistant", content: "hello"))
        let msgs = try store.chatMessages(forPaper: p.id!)
        XCTAssertEqual(msgs.map(\.role), ["user", "assistant"])
        XCTAssertEqual(msgs.map(\.content), ["hi", "hello"])
        try store.clearChat(paperID: p.id!)
        XCTAssertEqual(try store.chatMessages(forPaper: p.id!).count, 0)
    }

    func testMakeRequestBuildsOpenAICall() throws {
        let cfg = ChatConfig(baseURL: "http://localhost:11434/v1", model: "llama3", apiKey: "secret")
        let req = try ChatClient.makeRequest(
            config: cfg, messages: [ChatTurn(role: "user", content: "hi")], stream: true)
        XCTAssertEqual(req.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "llama3")
        XCTAssertEqual(body?["stream"] as? Bool, true)
    }

    func testMakeRequestOmitsAuthWhenNoKey() throws {
        let cfg = ChatConfig(baseURL: "http://localhost:1234/v1/", model: "m")  // trailing slash trimmed
        let req = try ChatClient.makeRequest(config: cfg, messages: [], stream: false)
        XCTAssertEqual(req.url?.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testParseStreamChunk() {
        XCTAssertEqual(
            ChatClient.parseStreamChunk(#"data: {"choices":[{"delta":{"content":"Hel"}}]}"#), "Hel")
        XCTAssertNil(ChatClient.parseStreamChunk("data: [DONE]"))
        XCTAssertNil(ChatClient.parseStreamChunk(""))
        XCTAssertNil(ChatClient.parseStreamChunk("event: ping"))
        XCTAssertNil(ChatClient.parseStreamChunk(#"data: {"choices":[{"delta":{}}]}"#))
    }
}
