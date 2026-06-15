import SwiftUI
import NimbleScholarCore

struct RowsView: View {
    @EnvironmentObject var vm: LibraryViewModel

    var body: some View {
        if vm.papers.isEmpty {
            EmptyLibraryView()
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vm.papers) { paper in
                    RowCard(paper: paper).environmentObject(vm)
                }
            }
            .padding(20)
        }
    }
}

/// One wide row card with inline editing. Hovering tints the card + lifts its shadow;
/// the selected row keeps an accent ring.
private struct RowCard: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper
    @State private var hovering = false

    private var selected: Bool { vm.selection == paper.id }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PaperThumbnail(paper: paper)
                .frame(width: 160, height: 110)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) { PaperStatusBadge(paper: paper) }
                .overlay(alignment: .topLeading) { ImportanceStar(paper: paper, onImage: true).font(.caption).padding(6) }
            VStack(alignment: .leading, spacing: 6) {
                Text(paper.title).font(.headline)
                Text([paper.authors, paper.venue, paper.year].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                InlineSummaryField(paper: paper)
                InlineTagEditor(paper: paper)
            }
            Spacer()
            Button("Read") { vm.openReader(paper) }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(hovering ? 0.06 : 0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Color.accentColor : .black.opacity(0.06),
                              lineWidth: selected ? 2 : 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.16 : 0.06),
                radius: hovering ? 7 : 2, y: hovering ? 3 : 1)
        .animation(.easeOut(duration: 0.13), value: hovering)
        .animation(.easeOut(duration: 0.13), value: selected)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { vm.openReader(paper) }
        .onTapGesture { vm.selection = paper.id }
        .paperContextMenu(paper)
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

/// Tag chips with remove buttons + an add field with existing-tag autocomplete.
struct InlineTagEditor: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper

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
            TagInputField(paper: paper, fieldWidth: 90)
        }
    }
}
