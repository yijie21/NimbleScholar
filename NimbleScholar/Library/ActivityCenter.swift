import SwiftUI

/// Tracks in-flight downloads/work so the UI can show a status bar. Two modes:
/// individual ops (a spinner + label) and a batch (a determinate progress bar).
@MainActor
final class ActivityCenter: ObservableObject {
    static let shared = ActivityCenter()

    @Published private(set) var ops = 0
    @Published private(set) var detail = ""
    @Published private(set) var batchLabel = ""
    @Published private(set) var batchTotal = 0
    @Published private(set) var batchDone = 0
    /// Per-paper work labels (e.g. "Downloading PDF…"), so each library item can show its own state.
    @Published private(set) var itemLabels: [Int64: String] = [:]

    /// One-line failure message shown in the status bar (auto-clears; ✕ dismisses).
    @Published private(set) var errorMessage: String?
    private var errorClear: Task<Void, Never>?

    func reportError(_ message: String) {
        errorMessage = message
        errorClear?.cancel()
        errorClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled { self?.errorMessage = nil }
        }
    }
    func clearError() {
        errorClear?.cancel()
        errorMessage = nil
    }

    var isActive: Bool { ops > 0 || batchTotal > 0 }

    func begin(_ label: String) { ops += 1; detail = label }
    func end() { ops = max(0, ops - 1); if ops == 0 && batchTotal == 0 { detail = "" } }

    // MARK: - Per-item state
    func beginItem(_ id: Int64?, _ label: String) { if let id { itemLabels[id] = label } }
    func endItem(_ id: Int64?) { if let id { itemLabels[id] = nil } }
    func itemLabel(_ id: Int64?) -> String? { id.flatMap { itemLabels[$0] } }

    func beginBatch(_ label: String, total: Int) {
        batchLabel = label; batchTotal = max(total, 0); batchDone = 0
    }
    func stepBatch() {
        batchDone += 1
        if batchDone >= batchTotal { endBatch() }
    }
    func endBatch() {
        batchTotal = 0; batchDone = 0; batchLabel = ""
        if ops == 0 { detail = "" }
    }
}

/// Window-bottom status bar: shows batch progress, ongoing downloads, or "Up to date".
struct StatusBar: View {
    @ObservedObject private var activity = ActivityCenter.shared

    var body: some View {
        HStack(spacing: 8) {
            if let err = activity.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(err).lineLimit(1).foregroundStyle(.primary)
                Button { activity.clearError() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Dismiss")
            } else if activity.batchTotal > 0 {
                ProgressView(value: Double(activity.batchDone), total: Double(max(activity.batchTotal, 1)))
                    .frame(width: 140)
                Text("\(activity.batchLabel) — \(activity.batchDone)/\(activity.batchTotal)")
                    .lineLimit(1)
            } else if activity.ops > 0 {
                ProgressView().controlSize(.small)
                Text(activity.detail.isEmpty ? "Working…" : activity.detail).lineLimit(1)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Up to date")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
