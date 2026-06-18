import SwiftUI
import NimbleScholarCore

/// Add a new link: paste a URL (+ optional tags). The app creates the card immediately and fetches
/// its title/figure in the background.
struct AddLinkSheet: View {
    @EnvironmentObject var vm: LinksViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var tags = ""

    private var isValid: Bool {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: u)?.scheme != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Link").font(.headline)
            TextField("URL (https://…)", text: $url).textFieldStyle(.roundedBorder)
            TextField("Tags (comma-separated, optional)", text: $tags).textFieldStyle(.roundedBorder)
            Text("The title and figure are fetched automatically.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { vm.addLink(url: url, tags: tags); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Edit a saved link's title/URL/description and its tags.
struct LinkEditSheet: View {
    @EnvironmentObject var vm: LinksViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var link: SavedLink
    @State private var newTag = ""

    init(link: SavedLink) { _link = State(initialValue: link) }

    // Existing link tags not already on this link.
    private var suggestions: [String] { vm.tagSuggestions(for: link) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Link").font(.headline)

            field("Title") { TextField("Title", text: $link.title).textFieldStyle(.roundedBorder) }
            field("URL") { TextField("URL", text: $link.url).textFieldStyle(.roundedBorder) }
            field("Description") {
                TextField("Description", text: $link.detail, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
            }

            field("Tags") {
                VStack(alignment: .leading, spacing: 8) {
                    // Tags apply immediately (the "Add" button, not Return — Return is the sheet's
                    // Save action), so an assigned tag can never be lost by closing the sheet.
                    HStack {
                        TextField("+ tag", text: $newTag).textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200).onSubmit { addTyped() }
                        Button("Add") { addTyped() }
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        if !suggestions.isEmpty {
                            Menu {
                                ForEach(suggestions, id: \.self) { t in
                                    Button { vm.addTag(t, to: link) } label: { Label(t, systemImage: "tag") }
                                }
                            } label: { Image(systemName: "tag") }
                            .menuStyle(.borderlessButton).fixedSize().help("Add an existing tag")
                        }
                    }
                    let current = vm.tags(for: link)
                    if !current.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(current, id: \.self) { t in
                                    HStack(spacing: 4) {
                                        Circle().fill(TagColor.color(for: t)).frame(width: 6, height: 6)
                                        Text(t).font(.caption)
                                        Button { vm.removeTag(t, from: link) } label: {
                                            Image(systemName: "xmark.circle.fill")
                                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(.quaternary))
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Delete", role: .destructive) { vm.delete(link); dismiss() }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { vm.save(link); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 520)
    }

    @ViewBuilder private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func addTyped() {
        for part in newTag.split(separator: ",") {
            let n = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty { vm.addTag(n, to: link) }   // applied immediately + normalized by the store
        }
        newTag = ""
    }
}
