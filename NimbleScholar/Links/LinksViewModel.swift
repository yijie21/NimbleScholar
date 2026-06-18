import SwiftUI
import AppKit
import NimbleScholarCore

/// The current filter in the Links section (independent from paper scopes/tags).
enum LinkScope: Hashable {
    case all, untagged
    case tag(String)
}

/// Drives the Links section: the visible saved links for the current scope/search, their tag map,
/// tag counts, and add/edit/delete. Owns its own GRDB observation so the card grid refreshes live
/// on any write (including captures from the embedded server). Entirely separate from papers.
@MainActor
final class LinksViewModel: ObservableObject {
    @Published var links: [SavedLink] = []
    @Published var tagCounts: [TagCount] = []
    @Published var tagsByLink: [Int64: [String]] = [:]
    @Published var query = "" { didSet { if query != oldValue { scheduleSearchReload() } } }
    @Published var scope: LinkScope = .all { didSet { reload() } }
    @Published var editingLink: SavedLink? = nil

    private let store = AppEnvironment.shared.store
    private var observation: ObservationToken?
    private var searchDebounce: Task<Void, Never>?
    private var reloadCoalesce: Task<Void, Never>?

    init() { observation = store.observeLinkChanges { [weak self] in self?.reload() } }

    /// Debounce search so typing doesn't query the DB on every keystroke.
    private func scheduleSearchReload() {
        searchDebounce?.cancel()
        searchDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            if Task.isCancelled { return }
            self?.reload()
        }
    }

    var scopeTitle: String {
        switch scope {
        case .all: return "All links"
        case .untagged: return "Untagged"
        case .tag(let t): return t
        }
    }

    /// Coalesce reloads within one frame so a mutation's explicit reload and the observation's reload
    /// (fired by the same write) collapse into one DB fetch.
    func reload() {
        reloadCoalesce?.cancel()
        reloadCoalesce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000)
            if Task.isCancelled { return }
            self?.performReload()
        }
    }

    private func performReload() {
        let q = query.trimmingCharacters(in: .whitespaces)
        let qq = q.isEmpty ? nil : q
        switch scope {
        case .all:           links = (try? store.searchLinks(query: qq, tag: nil)) ?? []
        case .untagged:      links = (try? store.untaggedLinks(query: qq)) ?? []
        case .tag(let t):    links = (try? store.searchLinks(query: qq, tag: t)) ?? []
        }
        tagCounts = (try? store.linkTagCounts()) ?? []
        tagsByLink = (try? store.allTagsByLink()) ?? [:]
    }

    // MARK: Tags

    func tags(for link: SavedLink) -> [String] { link.id.flatMap { tagsByLink[$0] } ?? [] }
    private func allTagNames() -> [String] { tagCounts.map(\.name) }

    /// Existing link tags not already on this link, optionally filtered by typed text.
    func tagSuggestions(for link: SavedLink, matching: String = "") -> [String] {
        let current = Set(tags(for: link))
        let q = matching.trimmingCharacters(in: .whitespaces).lowercased()
        return allTagNames().filter { !current.contains($0) && (q.isEmpty || $0.contains(q)) }
    }

    func addTag(_ tag: String, to link: SavedLink) {
        guard let id = link.id else { return }
        try? store.setLinkTags(linkID: id, tags: tags(for: link) + [tag]); reload()
    }
    func removeTag(_ name: String, from link: SavedLink) {
        guard let id = link.id else { return }
        try? store.setLinkTags(linkID: id, tags: tags(for: link).filter { $0 != name }); reload()
    }

    func deleteTag(_ name: String) {
        try? store.deleteLinkTag(name)
        if case .tag(let t) = scope, t == name { scope = .all } else { reload() }
    }
    func renameTag(_ old: String, to new: String) {
        try? store.renameLinkTag(old, to: new)
        if case .tag(let t) = scope, t == old { scope = .tag(TagNormalizer.normalize(new).first ?? old) }
        else { reload() }
    }

    // MARK: CRUD

    /// Add a new link by URL: create the row immediately (so it appears at once), then enrich it
    /// in the background with the page's title + og:image figure.
    func addLink(url: String, tags: String = "") {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = try? store.existingLink(forURL: trimmed) {   // dedupe by URL
            if !tags.isEmpty, let id = existing.id { try? store.setLinkTags(linkID: id, tags: TagNormalizer.normalize(tags)) }
            enrich(existing); reload(); return
        }
        var link = SavedLink(url: trimmed)
        link.title = trimmed
        link.source = link.isGitHub ? "github" : "web"
        guard let saved = try? store.createLink(link) else { return }
        if !tags.isEmpty, let id = saved.id { try? store.setLinkTags(linkID: id, tags: TagNormalizer.normalize(tags)) }
        enrich(saved); reload()
    }

    func save(_ link: SavedLink) {
        _ = try? (link.id == nil ? store.createLink(link) : store.updateLink(link)); reload()
    }
    func delete(_ link: SavedLink) {
        if let id = link.id { try? store.deleteLink(id: id) }; reload()
    }
    func open(_ link: SavedLink) {
        if let u = URL(string: link.url) { NSWorkspace.shared.open(u) }
    }

    /// Fetch the page's <meta> (og:title / og:image / og:description) and fill any empty fields.
    private func enrich(_ link: SavedLink) {
        guard let id = link.id else { return }
        let url = link.url
        let store = self.store
        Task {
            guard let meta = try? await AppEnvironment.resolveMetadata(for: url),
                  var fresh = try? store.link(id: id) else { return }
            var changed = false
            if (fresh.title.isEmpty || fresh.title == fresh.url), !meta.title.isEmpty { fresh.title = meta.title; changed = true }
            if fresh.imageURL.isEmpty, !meta.teaserURL.isEmpty { fresh.imageURL = meta.teaserURL; changed = true }
            if fresh.detail.isEmpty, !meta.abstract.isEmpty { fresh.detail = meta.abstract; changed = true }
            if changed { _ = try? store.updateLink(fresh) }   // observation refreshes the grid
        }
    }
}
