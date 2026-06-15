import SwiftUI
import AppKit
import NimbleScholarCore

enum LibraryScope: Hashable {
    case all, unread, untagged, recent, important
    case tag(String)
}

/// Drives the library window: the visible papers for the current scope/search/sort, a batched
/// paper→tags map (avoids N+1), tag counts, and selection. It owns a GRDB change observation so
/// the UI refreshes live on any write (including captures from the embedded server).
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

    /// The tag that marks a paper "unread" (drives the blue dot + Unread filter).
    static let toReadTag = "to-read"

    @Published var papers: [Paper] = []
    @Published var tagCounts: [TagCount] = []
    @Published var tagsByPaper: [Int64: [String]] = [:]   // batched once per reload (no N+1)
    @Published var query = "" { didSet { reload() } }
    @Published var scope: LibraryScope = .all { didSet { reload() } }
    @Published var sort: SortMode = .updated {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: "librarySort")
            papers = floatImportant(sorted(papers))
        }
    }
    @Published var selection: Paper.ID? = nil
    @Published var multiSelection: Set<Int64> = []   // three-pane multi-selection
    @Published var editingPaper: Paper? = nil
    @Published var readingPaperID: Int64? = nil   // non-nil → in-window reading mode

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
        case .important: return "Important"
        case .tag(let t): return t
        }
    }

    func reload() {
        let result: [Paper]
        switch scope {
        case .all:           result = (try? store.searchPapers(query: query, tag: nil)) ?? []
        case .unread:        result = (try? store.searchPapers(query: query, tag: Self.toReadTag)) ?? []
        case .important:     result = ((try? store.searchPapers(query: query, tag: nil)) ?? []).filter { $0.isImportant }
        case .tag(let t):    result = (try? store.searchPapers(query: query, tag: t)) ?? []
        case .untagged:      result = (try? store.untaggedPapers(query: query)) ?? []
        case .recent:        result = ((try? store.searchPapers(query: query, tag: nil)) ?? [])
                                 .sorted { $0.createdAt > $1.createdAt }
        }
        let ordered = (scope == .recent) ? Array(result.prefix(30)) : sorted(result)
        papers = floatImportant(ordered)
        tagCounts = (try? store.tagCounts()) ?? []
        tagsByPaper = (try? store.allTagsByPaper()) ?? [:]
        ThumbnailCache.shared.prewarm(papers)
        autoCompleteIncomplete()
    }

    private func sorted(_ list: [Paper]) -> [Paper] {
        if scope == .recent { return list }   // already newest-first
        switch sort {
        case .updated: return list.sorted { $0.updatedAt > $1.updatedAt }
        case .year:    return list.sorted { $0.year > $1.year }
        case .title:   return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    /// Stable: keeps important papers first while preserving the active sort within groups.
    private func floatImportant(_ list: [Paper]) -> [Paper] {
        list.sorted { $0.isImportant && !$1.isImportant }
    }

    // MARK: - Tags

    func tags(for paper: Paper) -> [String] {
        guard let id = paper.id else { return [] }
        return tagsByPaper[id] ?? []
    }

    /// All tag names ever used, most-used first (for pickers/autocomplete).
    var allTagNames: [String] { tagCounts.map { $0.name } }

    /// Existing tags not already on `paper`, optionally filtered by typed text
    /// (case-insensitive substring), most-used first — powers tag autocomplete.
    func tagSuggestions(for paper: Paper, matching text: String = "") -> [String] {
        let applied = Set(tags(for: paper).map { $0.lowercased() })
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tagCounts
            .map { $0.name }
            .filter { !applied.contains($0.lowercased()) }
            .filter { q.isEmpty || $0.lowercased().contains(q) }
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
    func toggleImportant(_ paper: Paper) {
        if let id = paper.id { try? store.setImportant(paperID: id, important: !paper.isImportant); reload() }
    }

    func openReader(_ paper: Paper) {
        guard let id = paper.id else { return }
        selection = id
        multiSelection = [id]          // so the three-pane detail shows this paper
        readingPaperID = id
    }
    func closeReader() { readingPaperID = nil }

    /// A paper counts as "unread" while it still carries the to-read tag.
    func isUnread(_ paper: Paper) -> Bool { tags(for: paper).contains(Self.toReadTag) }

    /// Clear the to-read tag (used when a paper is opened via Read/Browser).
    func markRead(_ paper: Paper) {
        guard let id = paper.id else { return }
        try? store.removeTag(Self.toReadTag, fromPaper: id)
        reload()
    }

    /// Toggle the to-read tag (context-menu Mark as Read/Unread).
    func toggleToRead(_ paper: Paper) {
        if isUnread(paper) { removeTag(Self.toReadTag, from: paper) }
        else { addTag(Self.toReadTag, to: paper) }
    }

    /// Download (if needed) then reveal the cached PDF in Finder.
    func revealPDF(_ paper: Paper) {
        Task { if let url = await ensurePDF(for: paper) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    }
    /// Download (if needed) then open the cached PDF in the system default PDF app.
    func openPDFExternally(_ paper: Paper) {
        Task { if let url = await ensurePDF(for: paper) { NSWorkspace.shared.open(url) } }
    }
    /// Re-fetch metadata + figure from the source and update the paper.
    func refetchMetadata(_ paper: Paper) {
        Task {
            let meta = (try? await AppEnvironment.resolveMetadata(for: paper.url)) ?? PaperMetadata()
            var p = paper
            if !meta.title.isEmpty { p.title = meta.title }
            if !meta.authors.isEmpty { p.authors = meta.authors }
            if !meta.abstract.isEmpty { p.abstract = meta.abstract }
            if !meta.year.isEmpty { p.year = meta.year }
            _ = try? store.update(p)
            if !p.hasFigure, let figs = await fetchFigure(for: p) {
                p.teaserURL = figs.teaser ?? ""; p.pipelineURL = figs.pipeline ?? ""
                _ = try? store.update(p)
            }
            await MainActor.run { reload() }
        }
    }
    func save(_ paper: Paper) {
        _ = try? (paper.id == nil ? store.create(paper) : store.update(paper))
        reload()
    }

    /// Import a local PDF: copy it into the cache and create a paper from its filename.
    func importPDF(at source: URL) {
        let cache = AppEnvironment.shared.downloader.cacheDir
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let dest = cache.appendingPathComponent(source.lastPathComponent)
        if !FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.copyItem(at: source, to: dest)
        }
        var p = Paper(title: source.deletingPathExtension().lastPathComponent)
        p.pdfPath = dest.path
        p.source = "local"
        _ = try? store.create(p)
        reload()
    }

    // MARK: - Bulk actions

    /// Ensure a local PDF exists and persist its path (so thumbnails/reader find it).
    @discardableResult
    func ensurePDF(for paper: Paper) async -> URL? {
        ActivityCenter.shared.begin("Downloading PDF — \(paper.title)")
        ActivityCenter.shared.beginItem(paper.id, "Downloading PDF…")
        defer { ActivityCenter.shared.end(); ActivityCenter.shared.endItem(paper.id) }
        guard let url = try? await AppEnvironment.shared.downloader.ensureLocalPDF(for: paper) else { return nil }
        if paper.pdfPath != url.path {
            var p = paper; p.pdfPath = url.path; _ = try? store.update(p)
        }
        return url
    }
    func downloadAllPDFs() async {
        for p in papers { _ = await ensurePDF(for: p) }
    }

    // MARK: - Auto-complete (figure + PDF) so every paper reaches "ready"

    private var inflight = Set<Int64>()      // papers being processed right now
    private var attempted = Set<Int64>()     // papers already auto-processed this session
    private var autoCompleteRunning = false

    /// True when the paper still needs work: no local PDF, or no figure yet but a figure
    /// source (arXiv HTML/ar5iv, or an HTML landing page) we can scrape.
    private func needsCompletion(_ p: Paper) -> Bool {
        if !p.hasLocalPDF { return true }
        if !p.hasFigure, canFetchFigure(p) { return true }
        if !p.linksScanned, canScanLinks(p) { return true }
        return false
    }

    /// We can look for project/code links once there's a PDF to read, an arXiv id, or a
    /// landing page to scrape.
    private func canScanLinks(_ p: Paper) -> Bool {
        p.hasLocalPDF || ArxivService.extractID(from: p.url) != nil || landingPageURL(for: p) != nil
    }

    private func canFetchFigure(_ p: Paper) -> Bool {
        ArxivService.extractID(from: p.url) != nil || landingPageURL(for: p) != nil
    }

    /// Scrape a teaser/pipeline figure for a paper: arXiv HTML/ar5iv by id, else its HTML
    /// landing page. Returns nil when there's no source or nothing usable was found.
    private func fetchFigure(for p: Paper) async -> FigureChooser.Result? {
        let figs: FigureChooser.Result?
        if let aid = ArxivService.extractID(from: p.url) {
            figs = try? await AppEnvironment.fetchArxivFigures(aid)
        } else if let page = landingPageURL(for: p) {
            figs = try? await AppEnvironment.fetchPageFigures(page)
        } else {
            return nil
        }
        guard let figs, figs.teaser != nil || figs.pipeline != nil else { return nil }
        return figs
    }

    /// Force a fresh figure scrape for EVERY paper that has a source, overwriting whatever is
    /// stored — repairs papers whose figure URL is stale/broken (so they stop showing the PDF
    /// page). Toolbar "Re-fetch all figures".
    func refetchAllFigures() {
        Task {
            let targets = ((try? store.allPapers()) ?? papers).filter { canFetchFigure($0) }
            guard !targets.isEmpty else { return }
            ActivityCenter.shared.beginBatch("Re-fetching figures", total: targets.count)
            for p in targets {
                ActivityCenter.shared.beginItem(p.id, "Fetching figure…")
                if let figs = await fetchFigure(for: p) {
                    var x = p; x.teaserURL = figs.teaser ?? ""; x.pipelineURL = figs.pipeline ?? ""
                    _ = try? store.update(x)
                }
                ActivityCenter.shared.endItem(p.id)
                ActivityCenter.shared.stepBatch()
            }
            ActivityCenter.shared.endBatch()
            reload()
        }
    }

    /// The HTML landing page to scrape a figure from. arXiv is handled by id elsewhere; this
    /// covers non-arXiv papers: an HTML URL is used directly, and a CVF raw-PDF URL
    /// (`…/papers/Name.pdf`) is mapped to its abstract page (`…/html/Name.html`).
    private func landingPageURL(for p: Paper) -> String? {
        let u = p.url
        guard !u.isEmpty, ArxivService.extractID(from: u) == nil else { return nil }
        if u.lowercased().hasSuffix(".pdf") {
            guard u.contains("/papers/") else { return nil }
            return u.replacingOccurrences(of: "/papers/", with: "/html/")
                    .replacingOccurrences(of: ".pdf", with: ".html")
        }
        return u
    }

    /// After every reload, fetch missing figures and PDFs for incomplete papers in the
    /// background (one at a time, with per-item + status-bar progress). Each paper is
    /// auto-attempted once per session; `retry(_:)` re-arms a specific one.
    func autoCompleteIncomplete() {
        guard !autoCompleteRunning else { return }
        let todo = papers.filter { p in
            guard let id = p.id, !inflight.contains(id), !attempted.contains(id) else { return false }
            return needsCompletion(p)
        }
        guard !todo.isEmpty else { return }
        for p in todo { if let id = p.id { attempted.insert(id) } }
        autoCompleteRunning = true
        Task {
            await complete(todo)
            autoCompleteRunning = false
            autoCompleteIncomplete()   // pick up anything captured while we were working
        }
    }

    /// Clear the once-per-session guard and re-run completion (toolbar "Load missing…").
    func retryAllIncomplete() {
        attempted.removeAll()
        autoCompleteIncomplete()
    }

    /// Re-arm a single paper (tapping its orange badge) and resume completion.
    func retry(_ paper: Paper) {
        if let id = paper.id { attempted.remove(id) }
        autoCompleteIncomplete()
    }

    private func complete(_ list: [Paper]) async {
        ActivityCenter.shared.beginBatch("Preparing papers", total: list.count)
        for p in list {
            guard let id = p.id else { continue }
            inflight.insert(id)
            var cur = p
            // 1. Figure: arXiv HTML/ar5iv by id, else the paper's HTML landing page.
            if !cur.hasFigure, canFetchFigure(cur) {
                ActivityCenter.shared.beginItem(id, "Fetching figure…")
                if let figs = await fetchFigure(for: cur) {
                    cur.teaserURL = figs.teaser ?? ""; cur.pipelineURL = figs.pipeline ?? ""
                    _ = try? store.update(cur)
                }
            }
            // 2. PDF (also gives a thumbnail when there's no figure).
            if !cur.hasLocalPDF {
                ActivityCenter.shared.beginItem(id, "Downloading PDF…")
                if let url = try? await AppEnvironment.shared.downloader.ensureLocalPDF(for: cur) {
                    cur.pdfPath = url.path
                    _ = try? store.update(cur)
                }
            }
            // 3. Project / code links (once per paper).
            if !cur.linksScanned, canScanLinks(cur) {
                ActivityCenter.shared.beginItem(id, "Finding links…")
                let links = await LinkFinder.find(for: cur, session: AppEnvironment.shared.networkSession)
                if let project = links.projectURL { cur.projectURL = project }
                if let code = links.codeURL { cur.codeURL = code }
                cur.linksScanned = true
                _ = try? store.update(cur)
            }
            ActivityCenter.shared.endItem(id)
            inflight.remove(id)
            ActivityCenter.shared.stepBatch()
        }
        ActivityCenter.shared.endBatch()
    }

    // MARK: - Multi-selection bulk actions

    private func selectedPapers() -> [Paper] { papers.filter { $0.id.map(multiSelection.contains) ?? false } }

    func bulkDelete() {
        for p in selectedPapers() { if let id = p.id { try? store.deletePaper(id: id) } }
        multiSelection.removeAll(); reload()
    }
    func bulkAddTag(_ tag: String) {
        for p in selectedPapers() where p.id != nil {
            let current = (try? store.tags(forPaper: p.id!)) ?? []
            try? store.setTags(paperID: p.id!, tags: current + [tag])
        }
        reload()
    }
    func bulkDownloadPDFs() async {
        for p in selectedPapers() { _ = await ensurePDF(for: p) }
    }
}
