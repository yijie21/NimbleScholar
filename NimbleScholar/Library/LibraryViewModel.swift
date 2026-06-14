import SwiftUI
import NimbleScholarCore

enum LibraryScope: Hashable {
    case all, unread, untagged, recent
    case tag(String)
}

@MainActor
final class LibraryViewModel: ObservableObject {
    enum SortMode: String, CaseIterable, Identifiable {
        case updated, year, title
        var id: String { rawValue }
        var label: String {
            switch self {
            case .updated: return "Recently updated"
            case .year: return "Newest year"
            case .title: return "Title A–Z"
            }
        }
    }

    @Published var papers: [Paper] = []
    @Published var tagCounts: [TagCount] = []
    @Published var tagsByPaper: [Int64: [String]] = [:]   // batched once per reload (no N+1)
    @Published var query = "" { didSet { reload() } }
    @Published var scope: LibraryScope = .all { didSet { reload() } }
    @Published var sort: SortMode = .updated {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: "librarySort")
            papers = sorted(papers)
        }
    }
    @Published var selection: Paper.ID? = nil
    @Published var editingPaper: Paper? = nil

    private let store = AppEnvironment.shared.store
    private var observation: ObservationToken?

    init() {
        if let raw = UserDefaults.standard.string(forKey: "librarySort"),
           let s = SortMode(rawValue: raw) { sort = s }
        observation = store.observeChanges { [weak self] in self?.reload() }
    }

    var scopeTitle: String {
        switch scope {
        case .all: return "All papers"
        case .unread: return "Unread"
        case .untagged: return "Untagged"
        case .recent: return "Recently added"
        case .tag(let t): return t
        }
    }

    func reload() {
        let result: [Paper]
        switch scope {
        case .all:           result = (try? store.searchPapers(query: query, tag: nil)) ?? []
        case .unread:        result = ((try? store.searchPapers(query: query, tag: nil)) ?? []).filter { !$0.isRead }
        case .tag(let t):    result = (try? store.searchPapers(query: query, tag: t)) ?? []
        case .untagged:      result = (try? store.untaggedPapers(query: query)) ?? []
        case .recent:        result = ((try? store.searchPapers(query: query, tag: nil)) ?? [])
                                 .sorted { $0.createdAt > $1.createdAt }
        }
        papers = (scope == .recent) ? Array(result.prefix(30)) : sorted(result)
        tagCounts = (try? store.tagCounts()) ?? []
        tagsByPaper = (try? store.allTagsByPaper()) ?? [:]
        ThumbnailCache.shared.prewarm(papers)
    }

    private func sorted(_ list: [Paper]) -> [Paper] {
        if scope == .recent { return list }   // already newest-first
        switch sort {
        case .updated: return list.sorted { $0.updatedAt > $1.updatedAt }
        case .year:    return list.sorted { $0.year > $1.year }
        case .title:   return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    // MARK: - Tags

    func tags(for paper: Paper) -> [String] {
        guard let id = paper.id else { return [] }
        return tagsByPaper[id] ?? []
    }
    func addTag(_ tag: String, to paper: Paper) {
        guard let id = paper.id else { return }
        let current = (try? store.tags(forPaper: id)) ?? []
        try? store.setTags(paperID: id, tags: current + [tag]); reload()
    }
    func removeTag(_ tag: String, from paper: Paper) {
        guard let id = paper.id else { return }
        let current = ((try? store.tags(forPaper: id)) ?? []).filter { $0 != tag }
        try? store.setTags(paperID: id, tags: current)
        reload()
    }
    func renameTag(_ old: String, to new: String) {
        try? store.renameTag(old, to: new)
        if case .tag(let t) = scope, t == old { scope = .tag(new) } else { reload() }
    }
    func deleteTag(_ name: String) {
        try? store.deleteTag(name)
        if case .tag(let t) = scope, t == name { scope = .all } else { reload() }
    }

    // MARK: - Paper mutations

    func saveSummary(_ text: String, for paper: Paper) {
        var p = paper; p.summary = text; _ = try? store.update(p); reload()
    }
    func delete(_ paper: Paper) {
        if let id = paper.id { try? store.deletePaper(id: id); reload() }
    }
    func toggleRead(_ paper: Paper) {
        if let id = paper.id { try? store.setRead(paperID: id, read: !paper.isRead); reload() }
    }
    func save(_ paper: Paper) {
        _ = try? (paper.id == nil ? store.create(paper) : store.update(paper))
        reload()
    }

    // MARK: - Bulk actions

    /// Ensure a local PDF exists and persist its path (so thumbnails/reader find it).
    @discardableResult
    func ensurePDF(for paper: Paper) async -> URL? {
        guard let url = try? await AppEnvironment.shared.downloader.ensureLocalPDF(for: paper) else { return nil }
        if paper.pdfPath != url.path {
            var p = paper; p.pdfPath = url.path; _ = try? store.update(p)
        }
        return url
    }
    func downloadAllPDFs() async {
        for p in papers { _ = await ensurePDF(for: p) }
    }
    func refreshAllFigures() async {
        for p in papers where p.teaserURL.isEmpty {
            guard let id = ArxivService.extractID(from: p.url),
                  let figs = try? await AppEnvironment.fetchArxivFigures(id),
                  figs.teaser != nil || figs.pipeline != nil else { continue }
            var x = p; x.teaserURL = figs.teaser ?? ""; x.pipelineURL = figs.pipeline ?? ""
            _ = try? store.update(x)
        }
    }
}
