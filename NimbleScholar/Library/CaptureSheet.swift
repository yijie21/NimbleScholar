import SwiftUI
import NimbleScholarCore

struct CaptureSheet: View {
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var tags = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 14) {
            Text("Capture URL").font(.headline)
            TextField("https://arxiv.org/abs/…", text: $url).textFieldStyle(.roundedBorder)
            TextField("Tags (comma separated)", text: $tags).textFieldStyle(.roundedBorder)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(busy ? "Saving…" : "Capture") { capture() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || url.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func capture() {
        busy = true
        error = nil
        let urlValue = url
        let tagsValue = tags
        Task {
            var payload = CapturePayload()
            payload.url = urlValue
            payload.tags = tagsValue
            let handler = CaptureHandler(
                store: AppEnvironment.shared.store,
                resolve: { u in try await AppEnvironment.resolveMetadata(for: u) },
                fetchFigures: AppEnvironment.fetchArxivFigures
            )
            do {
                _ = try await handler.capture(payload)
                await MainActor.run { vm.reload(); busy = false; dismiss() }
            } catch {
                await MainActor.run {
                    self.error = "Capture failed: \(error.localizedDescription)"
                    self.busy = false
                }
            }
        }
    }
}
