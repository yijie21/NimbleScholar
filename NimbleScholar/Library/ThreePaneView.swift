import SwiftUI
import NimbleScholarCore

struct ThreePaneView: View {
    @EnvironmentObject var vm: LibraryViewModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(vm.papers, selection: $vm.multiSelection) { paper in
                    HStack(spacing: 6) {
                        Circle().fill(.blue).frame(width: 7, height: 7).opacity(paper.isRead ? 0 : 1)
                        VStack(alignment: .leading) {
                            Text(paper.title).lineLimit(2).font(.headline)
                            Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        PaperStatusInline(paper: paper)
                    }
                    .tag(paper.id ?? -1)
                    .paperContextMenu(paper)
                }
                if vm.multiSelection.count > 1 {
                    HStack {
                        Text("\(vm.multiSelection.count) selected").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Download") { Task { await vm.bulkDownloadPDFs() } }
                        Button("Delete", role: .destructive) { vm.bulkDelete() }
                    }
                    .padding(8)
                    .background(.bar)
                }
            }
            .frame(minWidth: 240, idealWidth: 300, maxWidth: 440)

            Group {
                if vm.multiSelection.count == 1, let id = vm.multiSelection.first,
                   let paper = vm.papers.first(where: { $0.id == id }) {
                    PaperDetailView(paper: paper).environmentObject(vm)
                } else {
                    ContentUnavailableView("Select a paper", systemImage: "doc.text")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
