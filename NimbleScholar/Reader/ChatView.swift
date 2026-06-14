import SwiftUI
import PDFKit
import NimbleScholarCore

/// Per-reader AI chat: persisted history for the paper, streaming replies, paper+selection context.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var streaming = false
    @Published var error: String?

    let paper: Paper
    private let store = AppEnvironment.shared.store
    weak var pdfView: PDFView?

    init(paper: Paper) {
        self.paper = paper
        messages = (try? store.chatMessages(forPaper: paper.id ?? -1)) ?? []
    }

    var isConfigured: Bool { UserDefaults.standard.bool(forKey: "aiEnabled") }

    private func config() -> ChatConfig {
        let d = UserDefaults.standard
        let key = d.string(forKey: "aiAPIKey") ?? ""
        return ChatConfig(
            baseURL: d.string(forKey: "aiBaseURL") ?? "http://localhost:11434/v1",
            model: d.string(forKey: "aiModel") ?? "llama3",
            apiKey: key.isEmpty ? nil : key)
    }

    func clear() {
        if let id = paper.id { try? store.clearChat(paperID: id) }
        messages = []
    }

    func summarize() { send("Summarize this paper in a few clear bullet points.") }
    func explainSelection() {
        let sel = pdfView?.currentSelection?.string ?? ""
        send(sel.isEmpty ? "Explain the key idea of this paper simply."
                         : "Explain this passage in simple terms:\n\n\"\(sel)\"")
    }

    func send(_ text: String? = nil) {
        let userText = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty, !streaming, let pid = paper.id else { return }
        input = ""; error = nil

        let userMsg = (try? store.appendChatMessage(ChatMessage(paperId: pid, role: "user", content: userText)))
            ?? ChatMessage(paperId: pid, role: "user", content: userText)
        messages.append(userMsg)

        var turns: [ChatTurn] = [ChatTurn(role: "system", content: systemContext())]
        turns += messages.map { ChatTurn(role: $0.role, content: $0.content) }

        messages.append(ChatMessage(paperId: pid, role: "assistant", content: ""))
        let idx = messages.count - 1
        streaming = true

        Task {
            do {
                for try await delta in ChatClient.stream(config: config(), messages: turns) {
                    messages[idx].content += delta
                }
            } catch {
                self.error = "\(error)"
            }
            streaming = false
            let reply = messages[idx].content
            if reply.isEmpty {
                messages.remove(at: idx)
            } else {
                _ = try? store.appendChatMessage(ChatMessage(paperId: pid, role: "assistant", content: reply))
            }
        }
    }

    private func systemContext() -> String {
        var ctx = "You are a helpful research assistant answering questions about a single paper.\n\n"
        ctx += "Title: \(paper.title)\n"
        if !paper.authors.isEmpty { ctx += "Authors: \(paper.authors)\n" }
        if !paper.abstract.isEmpty { ctx += "Abstract: \(paper.abstract)\n" }
        if let body = pdfView?.document?.string, !body.isEmpty {
            ctx += "\nPaper text (may be truncated):\n" + String(body.prefix(24_000))
        }
        return ctx
    }
}

struct ChatView: View {
    @ObservedObject var vm: ChatViewModel

    var body: some View {
        if !vm.isConfigured {
            ContentUnavailableView {
                Label("AI chat is off", systemImage: "sparkles")
            } description: {
                Text("Enable it and set an endpoint in Settings → AI.")
            }
        } else {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(vm.messages.enumerated()), id: \.offset) { _, m in
                                MessageBubble(message: m)
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: vm.messages.count) { _, n in proxy.scrollTo(n - 1, anchor: .bottom) }
                }
                if let e = vm.error {
                    Text(e).font(.caption).foregroundStyle(.red)
                        .padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack(spacing: 10) {
                    Button("Summarize") { vm.summarize() }.font(.caption)
                    Button("Explain selection") { vm.explainSelection() }.font(.caption)
                    Spacer()
                    Button("Clear") { vm.clear() }.font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8).padding(.top, 6)
                HStack(spacing: 6) {
                    TextField("Ask about this paper…", text: $vm.input, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...4)
                        .onSubmit { vm.send() }
                    Button { vm.send() } label: { Image(systemName: "paperplane.fill") }
                        .disabled(vm.streaming || vm.input.isEmpty)
                }
                .padding(8)
            }
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        let isUser = message.role == "user"
        Text(message.content.isEmpty ? "…" : message.content)
            .font(.callout)
            .textSelection(.enabled)
            .padding(8)
            .background(isUser ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
