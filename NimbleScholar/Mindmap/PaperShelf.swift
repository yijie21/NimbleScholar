import SwiftUI
import NimbleScholarCore

/// Narrow shelf of papers to drag onto nodes. A search field on top (FTS, debounced,
/// narrowed by the library's current tag scope) over collapsible cards.
struct PaperShelf: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    @State private var query = ""
    @State private var results: [Paper] = []
    @State private var expanded: Set<Int64> = []

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
                        ShelfCard(paper: paper, expanded: binding(for: paper))
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

    private func binding(for paper: Paper) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(paper.id ?? -1) },
            set: { isOn in
                guard let id = paper.id else { return }
                if isOn { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private func search() async {
        let scopeTag: String? = { if case .tag(let t) = libraryVM.scope { return t } else { return nil } }()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = (try? AppEnvironment.shared.store.searchPapers(query: q.isEmpty ? nil : q, tag: scopeTag)) ?? []
    }
}

/// One shelf card. Collapsed = thumbnail + title; expanded adds authors + a larger figure.
/// Draggable: carries the paper id as a String for the canvas/node drop targets.
struct ShelfCard: View {
    let paper: Paper
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Color.clear.frame(width: 44, height: 44)
                    .overlay(PaperThumbnail(paper: paper))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(paper.title).font(.caption).bold().lineLimit(expanded ? 5 : 2)
                    if !paper.year.isEmpty {
                        Text(paper.year).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if expanded {
                if !paper.authors.isEmpty {
                    Text(paper.authors).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
                Color.clear.frame(height: 90)
                    .overlay(PaperThumbnail(paper: paper, contentMode: .fit))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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
