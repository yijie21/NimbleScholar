import SwiftUI
import NimbleScholarCore

struct ThreePaneView: View {
    @EnvironmentObject var vm: LibraryViewModel

    var body: some View {
        HSplitView {
            if vm.readingPaperID == nil || vm.showPaperList {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search papers, authors, DOI, tags", text: $vm.query)
                        .textFieldStyle(.plain)
                    if !vm.query.isEmpty {
                        Button { vm.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                Divider()
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
                    // No plain tap gesture here on purpose: it would suppress the List's native
                    // single-click selection. A *simultaneous* double-click gesture coexists with
                    // it — single click selects (and switches the reader while reading, via the
                    // selection didSet); double click opens the reader from browse mode.
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
            }

            Group {
                if let rid = vm.readingPaperID {
                    // Keyed by paper id so switching papers rebuilds the ReaderViewModel —
                    // a plain @StateObject would keep showing the previous document.
                    EmbeddedReader(paperID: rid) { vm.closeReader() }
                        .id(rid)
                        .transition(.opacity)
                } else if vm.multiSelection.count == 1, let id = vm.multiSelection.first,
                          let paper = vm.papers.first(where: { $0.id == id }) {
                    PaperDetailView(paper: paper).environmentObject(vm)
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
