import SwiftUI
import AppKit
import NimbleScholarCore

struct PaperDetailView: View {
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.openWindow) private var openWindow
    let paper: Paper
    @State private var newTag = ""

    private var imageURL: URL? {
        let s = paper.teaserURL.isEmpty ? paper.pipelineURL : paper.teaserURL
        return s.isEmpty ? nil : URL(string: s)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let img = imageURL {
                    AsyncImage(url: img) { $0.resizable().scaledToFit() } placeholder: { Color.gray.opacity(0.1) }
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Text(paper.title).font(.title2).bold()
                Text([paper.authors, paper.venue, paper.year].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        if let id = paper.id { openWindow(id: "reader", value: id) }
                    } label: { Label("Read", systemImage: "book") }
                    .buttonStyle(.borderedProminent)
                    Button("Browser") {
                        if let u = URL(string: paper.pdfURL.isEmpty ? paper.url : paper.pdfURL) {
                            NSWorkspace.shared.open(u)
                        }
                    }
                }
                FlowTags(tags: vm.tags(for: paper), onRemove: { vm.removeTag($0, from: paper) })
                TextField("+ tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .onSubmit {
                        if !newTag.isEmpty { vm.addTag(newTag, to: paper); newTag = "" }
                    }
                if !paper.abstract.isEmpty {
                    Text(paper.abstract).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FlowTags: View {
    let tags: [String]
    let onRemove: (String) -> Void
    var body: some View {
        HStack {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Circle().fill(TagColor.color(for: tag)).frame(width: 6, height: 6)
                    Text(tag).font(.caption)
                    Button { onRemove(tag) } label: { Image(systemName: "xmark").font(.system(size: 8)) }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.quaternary))
            }
        }
    }
}
