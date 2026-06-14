import SwiftUI
import NimbleScholarCore

struct ThreePaneView: View {
    @EnvironmentObject var vm: LibraryViewModel

    var body: some View {
        NavigationSplitView {
            List(vm.papers, selection: $vm.selection) { paper in
                VStack(alignment: .leading) {
                    Text(paper.title).lineLimit(2).font(.headline)
                    Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .tag(paper.id)
                .paperContextMenu(paper)
            }
            .frame(minWidth: 260)
        } detail: {
            if let id = vm.selection, let paper = vm.papers.first(where: { $0.id == id }) {
                PaperDetailView(paper: paper).environmentObject(vm)
            } else {
                Text("Select a paper").foregroundStyle(.secondary)
            }
        }
    }
}
