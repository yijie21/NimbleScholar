# Nimble Scholar — AI Chat in the Reader (Design)

**Date:** 2026-06-14
**Status:** Approved for implementation

## Summary

Add an AI chat panel to the reader window so the user can ask questions about the open paper,
summarize it, or explain a selected passage. Uses a **configurable OpenAI-compatible** backend
(local server or cloud). **Chat history is persisted per paper** in the SQLite store.

## Goals / scope (v1)

- One ongoing **conversation per paper**, saved to the DB and reloaded on open.
- Streaming replies.
- Context: paper title/abstract + extracted full text (truncated to a budget) + the current PDF
  text selection.
- Quick actions: "Summarize paper", "Explain selection".
- "Clear chat" resets the conversation.

## Non-goals (v1)

- Multiple named conversations per paper, RAG/embeddings, tool use, image input.
- Cross-paper chat. Keychain storage for the API key (use `@AppStorage`; note it's plaintext).

## Data model

Migration `v4-chat`:
```
chat_messages(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  paper_id INTEGER NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
  role TEXT NOT NULL,            -- "user" | "assistant"
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
```
`ChatMessage` GRDB record. Store methods: `chatMessages(forPaper:)`, `appendChatMessage(_:)`,
`clearChat(paperID:)`.

## Core: `ChatClient` (testable)

- `ChatConfig { baseURL, model, apiKey? }`.
- `ChatTurn { role, content }`.
- `makeRequest(config:messages:stream:) throws -> URLRequest` — POST `<baseURL>/chat/completions`,
  JSON body `{ model, messages, stream }`, `Authorization: Bearer <key>` when present. **Unit-tested**
  (URL, headers, body).
- `parseStreamChunk(_ line:) -> String?` — extract `choices[0].delta.content` from an SSE
  `data: {...}` line; nil for `data: [DONE]` / no content. **Unit-tested.**
- `stream(config:messages:) -> AsyncThrowingStream<String, Error>` — URLSession `.bytes` SSE loop
  yielding content deltas. Verified on Mac.

## Settings — AI tab

`@AppStorage`: `aiEnabled` (Bool), `aiBaseURL` (String, default `http://localhost:11434/v1`),
`aiModel` (String), `aiAPIKey` (String, secure field). A note that the key is stored in app
preferences and that local endpoints need no key.

## Reader UI

- `ChatViewModel` (per reader, `@MainActor`): holds `[ChatMessage]`, loads saved history on init,
  `send(_:)` builds the message array (system context + history + new), streams the reply
  (appending deltas to a live assistant message), and persists user + final assistant messages.
- Paper context: title + authors + abstract + `PDFDocument.string` truncated to ~24k chars, plus
  the reader's `currentSelection?.string`.
- `InspectorPanel`: add a third **"Chat"** tab — transcript (scrolling), input field + Send,
  Summarize / Explain-selection buttons, Clear. Disabled with a hint if `aiEnabled` is off.

## Testing

`swift test`: `chatMessages` round-trip + `clearChat`; `ChatClient.makeRequest` (URL/headers/body);
`ChatClient.parseStreamChunk` (delta extraction, `[DONE]`, malformed lines). Streaming + UI on Mac.

## Rollout

Phase A core (storage + client, tested) → Phase B Settings → Phase C reader UI. Commit per task;
build on Mac at the UI boundary. Migration additive.
