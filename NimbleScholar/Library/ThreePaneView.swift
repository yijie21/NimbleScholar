import SwiftUI
import NimbleScholarCore

struct ThreePaneView: View {
    @EnvironmentObject var vm: LibraryViewModel

    var body: some View {
        HSplitView {
            List(vm.papers, selection: $vm.selection) { paper in
                HStack(spacing: 6) {
                    Circle().fill(.blue).frame(width: 7, height: 7).opacity(paper.isRead ? 0 : 1)
                    VStack(alignment: .leading) {
                        Text(paper.title).lineLimit(2).font(.headline)
                        Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .tag(paper.id)
                .paperContextMenu(paper)
            }
            .frame(minWidth: 240, idealWidth: 300, maxWidth: 440)

            Group {
                if let id = vm.selection, let paper = vm.papers.first(where: { $0.id == id }) {
                    PaperDetailView(paper: paper).environmentObject(vm)
                } else {
                    ContentUnavailableView("Select a paper", systemImage: "doc.text")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
