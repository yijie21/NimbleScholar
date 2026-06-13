import SwiftUI
import NimbleScholarCore

struct CaptureSheet: View {
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var tags = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Capture URL").font(.headline)
            TextField("https://arxiv.org/abs/…", text: $url).textFieldStyle(.roundedBorder)
            TextField("Tags (comma separated)", text: $tags).textFieldStyle(.roundedBorder)
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
        let urlValue = url
        let tagsValue = tags
        Task {
            var payload = CapturePayload()
            payload.url = urlValue
            payload.tags = tagsValue
            let handler = CaptureHandler(store: AppEnvironment.shared.store) { u in
                try await AppEnvironment.resolveMetadata(for: u)
            }
            _ = try? await handler.capture(payload)
            await MainActor.run {
                vm.reload()
                busy = false
                dismiss()
            }
        }
    }
}
