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
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var loaded = false

    init(link: SavedLink) { _link = State(initialValue: link) }

    private var suggestions: [String] {
        vm.tagCounts.map(\.name).filter { !tags.contains($0) }
    }

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
                    HStack {
                        TextField("+ tag", text: $newTag).textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200).onSubmit { addTyped() }
                        if !suggestions.isEmpty {
                            Menu {
                                ForEach(suggestions, id: \.self) { t in
                                    Button { add(t) } label: { Label(t, systemImage: "tag") }
                                }
                            } label: { Image(systemName: "tag") }
                            .menuStyle(.borderlessButton).fixedSize().help("Add an existing tag")
                        }
                    }
                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(tags, id: \.self) { t in
                                    HStack(spacing: 4) {
                                        Circle().fill(TagColor.color(for: t)).frame(width: 6, height: 6)
                                        Text(t).font(.caption)
                                        Button { tags.removeAll { $0 == t } } label: {
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
                Button("Save") { vm.save(link); vm.setTags(tags, for: link); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { if !loaded { tags = vm.tags(for: link); loaded = true } }
    }

    @ViewBuilder private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func add(_ raw: String) {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !n.isEmpty, !tags.contains(n) else { return }
        tags.append(n)
    }
    private func addTyped() {
        for part in newTag.split(separator: ",") { add(String(part)) }
        newTag = ""
    }
}
