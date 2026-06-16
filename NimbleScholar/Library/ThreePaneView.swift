import SwiftUI
import NimbleScholarCore

struct ThreePaneView: View {
    @EnvironmentObject var vm: LibraryViewModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(vm.papers, selection: $vm.multiSelection) { paper in
                    HStack(spacing: 6) {
                        ImportanceStar(paper: paper).font(.caption)
                        Circle().fill(.blue).frame(width: 7, height: 7).opacity(vm.isUnread(paper) ? 1 : 0)
                        VStack(alignment: .leading) {
                            Text(paper.title).lineLimit(2).font(.headline)
                            Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        PaperStatusInline(paper: paper)
                    }
                    .tag(paper.id ?? -1)
                    .paperContextMenu(paper)
                    // Double-click opens the in-window reader; single click still selects (the List's
                    // own selection), so this rides alongside as a simultaneous gesture.
                    .simultaneousGesture(TapGesture(count: 2).onEnded { vm.openReader(paper) })
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
            // Fixed so the detail content can't make the list jitter; narrows while
            // reading to give the PDF more room. (Animated by the parent's single
            // .animation(value: readingPaperID), so no per-view animation here.)
            .frame(width: vm.readingPaperID != nil ? 240 : 320)

            Group {
                if vm.multiSelection.count == 1, let id = vm.multiSelection.first,
                   let paper = vm.papers.first(where: { $0.id == id }) {
                    if vm.readingPaperID == id {
                        EmbeddedReader(paperID: id) { vm.closeReader() }
                            .transition(.opacity)
                    } else {
                        PaperDetailView(paper: paper).environmentObject(vm)
                    }
                } else {
                    ContentUnavailableView("Select a paper", systemImage: "doc.text")
                }
            }
            // Local, cheap fade ONLY for the detail content swap (not the whole split view).
            .animation(.easeOut(duration: 0.15), value: vm.readingPaperID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
