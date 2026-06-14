import SwiftUI
import NimbleScholarCore

struct GalleryView: View {
    @EnvironmentObject var vm: LibraryViewModel
    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 18)]

    var body: some View {
        if vm.papers.isEmpty {
            EmptyLibraryView()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
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
    @Environment(\.openWindow) private var openWindow
    let paper: Paper
    @State private var hovering = false

    private var selected: Bool { vm.selection == paper.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaperThumbnail(paper: paper)
                .frame(maxWidth: .infinity)        // constrain width to the cell (no overflow)
                .frame(height: 130)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) { PaperStatusBadge(paper: paper) }
            Text(paper.title).font(.subheadline).bold().lineLimit(2)
            Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .onTapGesture(count: 2) { if let id = paper.id { openWindow(id: "reader", value: id) } }
        .onTapGesture { vm.selection = paper.id }
        .paperContextMenu(paper)
    }
}
