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
                        if !paper.teaserURL.isEmpty, let u = URL(string: paper.teaserURL) {
                            AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.1) }
                                .frame(width: 160, height: 110)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(paper.title).font(.headline)
                            Text(paper.authors).font(.caption).foregroundStyle(.secondary)
                            if !paper.summary.isEmpty { Text(paper.summary).font(.callout) }
                            FlowTags(tags: vm.tags(for: paper), onRemove: { vm.removeTag($0, from: paper) })
                        }
                        Spacer()
                        Button("Read") { if let id = paper.id { openWindow(id: "reader", value: id) } }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 1))
                    .onTapGesture { vm.selection = paper.id }
                    .paperContextMenu(paper)
                }
            }
            .padding(20)
        }
    }
}
