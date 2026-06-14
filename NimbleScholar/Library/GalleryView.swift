import SwiftUI
import NimbleScholarCore

struct GalleryView: View {
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.openWindow) private var openWindow
    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        if vm.papers.isEmpty {
            EmptyLibraryView()
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(vm.papers) { paper in
                    VStack(alignment: .leading, spacing: 6) {
                        PaperThumbnail(paper: paper)
                            .frame(height: 130)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) { PaperStatusBadge(paper: paper) }
                        Text(paper.title).font(.subheadline).bold().lineLimit(2)
                        Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(10)
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
