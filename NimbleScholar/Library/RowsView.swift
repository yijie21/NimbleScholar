import SwiftUI
import NimbleScholarCore

struct RowsView: View {
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vm.papers) { paper in
                    HStack(alignment: .top, spacing: 14) {
                        PaperThumbnail(paper: paper)
                            .frame(width: 160, height: 110)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(paper.title).font(.headline)
                            Text([paper.authors, paper.venue, paper.year].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            InlineSummaryField(paper: paper)
                            InlineTagEditor(paper: paper)
                        }
                        Spacer()
                        Button("Read") { if let id = paper.id { openWindow(id: "reader", value: id) } }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 1))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { if let id = paper.id { openWindow(id: "reader", value: id) } }
                    .onTapGesture { vm.selection = paper.id }
                    .paperContextMenu(paper)
                }
            }
            .padding(20)
        }
    }
}

/// One-sentence summary, editable inline, saved on commit.
struct InlineSummaryField: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper
    @State private var text: String = ""

    var body: some View {
        TextField("One-sentence summary…", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.callout)
            .lineLimit(1...3)
            .onAppear { text = paper.summary }
            .onSubmit { vm.saveSummary(text, for: paper) }
    }
}

/// Tag chips with remove buttons + an add field.
struct InlineTagEditor: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper
    @State private var newTag = ""

    var body: some View {
        HStack(spacing: 6) {
            ForEach(vm.tags(for: paper), id: \.self) { tag in
                HStack(spacing: 3) {
                    Circle().fill(TagColor.color(for: tag)).frame(width: 6, height: 6)
                    Text(tag).font(.caption)
                    Button { vm.removeTag(tag, from: paper) } label: { Image(systemName: "xmark").font(.system(size: 7)) }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(.quaternary))
            }
            TextField("+ tag", text: $newTag)
                .textFieldStyle(.plain)
                .font(.caption)
                .frame(width: 60)
                .onSubmit {
                    if !newTag.isEmpty { vm.addTag(newTag, to: paper); newTag = "" }
                }
        }
    }
}
