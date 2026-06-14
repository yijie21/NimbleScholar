import SwiftUI
import NimbleScholarCore

struct CaptureSheet: View {
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultCaptureTags") private var defaultTags = "to-read"
    @State private var url = ""
    @State private var tags = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 14) {
            Text("Capture URL").font(.headline)
            TextField("https://arxiv.org/abs/…", text: $url).textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                TextField("Tags (comma separated)", text: $tags).textFieldStyle(.roundedBorder)
                    .onAppear { if tags.isEmpty { tags = defaultTags } }
                let available = vm.allTagNames.filter { !currentTags.contains($0.lowercased()) }
                if !available.isEmpty {
                    Menu {
                        ForEach(available, id: \.self) { t in
                            Button { append(t) } label: { Label(t, systemImage: "tag") }
                        }
                    } label: { Image(systemName: "tag") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Add an existing tag")
                }
            }
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

    /// Tags already in the comma field (lowercased) so the menu hides duplicates.
    private var currentTags: Set<String> {
        Set(tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    }

    /// Append an existing tag to the comma-separated field.
    private func append(_ tag: String) {
        let trimmed = tags.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { tags = tag }
        else if trimmed.hasSuffix(",") { tags = trimmed + " " + tag }
        else { tags = trimmed + ", " + tag }
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
