import SwiftUI
import NimbleScholarCore

/// Narrow shelf of papers to drag onto nodes. A search field on top (FTS, debounced, narrowed by
/// the library's current tag scope) over cards, each showing the paper's figure. Hover a figure to
/// reveal a magnifier; clicking it opens a large preview (`previewPaper`, presented by MindmapView).
struct PaperShelf: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    @Binding var previewPaper: Paper?
    @State private var query = ""
    @State private var results: [Paper] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search papers", text: $query).textFieldStyle(.plain)
            }
            .padding(8)
            Divider()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(results) { paper in
                        ShelfCard(paper: paper) { previewPaper = $0 }
                    }
                }
                .padding(8)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 200_000_000)   // debounce typing
            if Task.isCancelled { return }
            await search()
        }
        .onReceive(libraryVM.$papers) { _ in Task { await search() } }
        .onChange(of: libraryVM.scope) { _, _ in Task { await search() } }
    }

    private func search() async {
        let scopeTag: String? = { if case .tag(let t) = libraryVM.scope { return t } else { return nil } }()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = (try? AppEnvironment.shared.store.searchPapers(query: q.isEmpty ? nil : q, tag: scopeTag)) ?? []
    }
}

/// One shelf card: the paper's figure + title. Hovering the figure reveals a magnifier that opens a
/// large preview. Draggable: carries the paper id as a String for the canvas/node drop targets.
struct ShelfCard: View {
    let paper: Paper
    let onPreview: (Paper) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .overlay(PaperThumbnail(paper: paper))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if hovering {
                        Button { onPreview(paper) } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .help("Preview figure")
                    }
                }
                .onHover { hovering = $0 }
            Text(paper.title).font(.caption).bold().lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !paper.year.isEmpty {
                Text(paper.year).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.06)))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .draggable(paper.id.map(String.init) ?? "")
    }
}

/// A large, dimmed figure preview shown over the mindmap. Click the backdrop or the ✕ to dismiss.
struct FigurePreviewOverlay: View {
    let paper: Paper
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            VStack(spacing: 12) {
                PaperThumbnail(paper: paper, contentMode: .fit)
                    .frame(maxWidth: 720, maxHeight: 520)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(paper.title).font(.headline).foregroundStyle(.white)
                    .multilineTextAlignment(.center).lineLimit(3).frame(maxWidth: 720)
            }
            .padding(28)
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white, .black.opacity(0.45))
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .contentShape(Rectangle())
            .onTapGesture { }   // absorb taps on the content so they don't dismiss
        }
    }
}
