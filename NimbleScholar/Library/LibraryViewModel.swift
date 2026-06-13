import SwiftUI
import NimbleScholarCore

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
    @Published var query = "" { didSet { reload() } }
    @Published var selectedTag: String? = nil { didSet { reload() } }
    @Published var sort: SortMode = .updated { didSet { papers = sorted(papers) } }
    @Published var selection: Paper.ID? = nil

    private let store = AppEnvironment.shared.store

    func reload() {
        papers = sorted((try? store.searchPapers(query: query, tag: selectedTag)) ?? [])
        tagCounts = (try? store.tagCounts()) ?? []
    }

    private func sorted(_ list: [Paper]) -> [Paper] {
        switch sort {
        case .updated: return list.sorted { $0.updatedAt > $1.updatedAt }
        case .year:    return list.sorted { $0.year > $1.year }
        case .title:   return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    func tags(for paper: Paper) -> [String] {
        guard let id = paper.id else { return [] }
        return (try? store.tags(forPaper: id)) ?? []
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
        if selectedTag == tag { selectedTag = nil } else { reload() }
    }

    func saveSummary(_ text: String, for paper: Paper) {
        var p = paper; p.summary = text; _ = try? store.update(p); reload()
    }

    func delete(_ paper: Paper) {
        if let id = paper.id { try? store.deletePaper(id: id); reload() }
    }

    func save(_ paper: Paper) {
        _ = try? (paper.id == nil ? store.create(paper) : store.update(paper))
        reload()
    }
}
