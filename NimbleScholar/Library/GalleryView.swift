import SwiftUI
import NimbleScholarCore

struct GalleryView: View {
    @EnvironmentObject var vm: LibraryViewModel
    @Environment(\.openWindow) private var openWindow
    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(vm.papers) { paper in
                    VStack(alignment: .leading, spacing: 6) {
                        AsyncImage(url: URL(string: paper.teaserURL.isEmpty ? paper.pipelineURL : paper.teaserURL)) {
                            $0.resizable().scaledToFill()
                        } placeholder: { Color.gray.opacity(0.1) }
                        .frame(height: 130)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(paper.title).font(.subheadline).bold().lineLimit(2)
                        Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { vm.selection = paper.id }
                    .contextMenu {
                        Button("Read") { if let id = paper.id { openWindow(id: "reader", value: id) } }
                    }
                }
            }
            .padding(20)
        }
    }
}
