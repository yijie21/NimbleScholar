import SwiftUI
import NimbleScholarCore

struct GalleryView: View {
    @EnvironmentObject var vm: LibraryViewModel
    // Fixed-width columns so every card is identical regardless of figure shape.
    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 230), spacing: 18)]

    var body: some View {
        if vm.papers.isEmpty {
            EmptyLibraryView()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                    ForEach(vm.papers) { paper in
                        GalleryCard(paper: paper).environmentObject(vm)
                    }
                }
                .padding(20)
            }
        }
    }
}

/// One gallery card. Owns its own hover state so moving the mouse over it lifts the card
/// (subtle scale + shadow); the selected card keeps an accent ring.
private struct GalleryCard: View {
    @EnvironmentObject var vm: LibraryViewModel
    let paper: Paper
    @State private var hovering = false

    private var selected: Bool { vm.selection == paper.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Fixed-size figure box: a fixed frame with the image as a *clipped overlay*,
            // so a tall/wide/odd-aspect figure can never change the card's size.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .overlay(PaperThumbnail(paper: paper))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) { PaperStatusBadge(paper: paper) }
                .overlay(alignment: .topLeading) { ImportanceStar(paper: paper, onImage: true).font(.caption).padding(6) }
            Text(paper.title).font(.subheadline).bold().lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(width: 230, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Color.accentColor : .black.opacity(0.06),
                              lineWidth: selected ? 2 : 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.20 : 0.07),
                radius: hovering ? 9 : 2, y: hovering ? 4 : 1)
        .scaleEffect(hovering ? 1.025 : 1)
        .animation(.easeOut(duration: 0.13), value: hovering)
        .animation(.easeOut(duration: 0.13), value: selected)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { vm.openReader(paper) }
        .onTapGesture { vm.selection = paper.id }
        .paperContextMenu(paper)
    }
}
