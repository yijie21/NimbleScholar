import Foundation

/// Connection config for an OpenAI-compatible chat endpoint (local server or cloud).
public struct ChatConfig: Equatable {
    public var baseURL: String      // e.g. "http://localhost:11434/v1" or "https://api.openai.com/v1"
    public var model: String
    public var apiKey: String?
    public init(baseURL: String, model: String, apiKey: String? = nil) {
        self.baseURL = baseURL; self.model = model; self.apiKey = apiKey
    }
}

/// One message in a chat request.
public struct ChatTurn: Equatable {
    public let role: String         // "system" | "user" | "assistant"
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

/// A minimal client for the OpenAI-compatible `/chat/completions` API.
public enum ChatClient {
    public enum ChatError: Error, Equatable { case badURL, http(Int) }

    /// Build the POST request for `<baseURL>/chat/completions`.
    public static func makeRequest(config: ChatConfig, messages: [ChatTurn], stream: Bool) throws -> URLRequest {
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        guard let url = URL(string: base + "/chat/completions") else { throw ChatError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = config.apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": config.model,
            "stream": stream,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Extract the content delta from one SSE line. Returns nil for `[DONE]`, blank, or non-data lines.
    public static func parseStreamChunk(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" || payload.isEmpty { return nil }
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String else { return nil }
        return content
    }

    /// Stream content deltas from the chat endpoint. Cancels the network task if the consumer stops.
    public static func stream(config: ChatConfig, messages: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try makeRequest(config: config, messages: messages, stream: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw ChatError.http(http.statusCode)
                    }
                    for try await line in bytes.lines {
                        if let delta = parseStreamChunk(line) { continuation.yield(delta) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
