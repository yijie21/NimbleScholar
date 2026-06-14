import Foundation

public final class CaptureHandler {
    public typealias Resolver = (String) async throws -> PaperMetadata
    /// Optional arXiv figure fetcher (by arXiv id). Left nil in unit tests to stay offline.
    public typealias FigureFetcher = (String) async throws -> FigureChooser.Result

    let store: LibraryStore
    let resolve: Resolver
    let fetchFigures: FigureFetcher?

    public init(store: LibraryStore, resolve: @escaping Resolver, fetchFigures: FigureFetcher? = nil) {
        self.store = store; self.resolve = resolve; self.fetchFigures = fetchFigures
    }

    @discardableResult
    public func capture(_ payload: CapturePayload) async throws -> Paper {
        let meta = (try? await resolve(payload.url)) ?? PaperMetadata()
        var p = Paper(title: payload.title?.nonEmpty ?? meta.title.nonEmpty ?? payload.url)
        p.authors = payload.authors?.nonEmpty ?? meta.authors
        p.year = meta.year
        p.doi = payload.doi?.nonEmpty ?? meta.doi
        p.url = payload.url
        p.abstract = payload.abstract?.nonEmpty ?? meta.abstract
        p.source = payload.source ?? ""
        p.teaserURL = payload.teaser_url?.nonEmpty ?? meta.teaserURL
        p.pdfURL = payload.pdf_url?.nonEmpty
            ?? ArxivService.normalizedPDFURL(absOrID: payload.url)
            ?? meta.pdfURL
        var saved: Paper
        if let existing = try store.existingPaper(forCaptureURL: payload.url) {
            // Update the existing row in place — don't create a duplicate, keep tags/annotations.
            p.id = existing.id
            p.createdAt = existing.createdAt
            if p.teaserURL.isEmpty { p.teaserURL = existing.teaserURL }
            if p.pipelineURL.isEmpty { p.pipelineURL = existing.pipelineURL }
            if p.pdfPath.isEmpty { p.pdfPath = existing.pdfPath }
            p.isRead = existing.isRead
            saved = try store.update(p)
        } else {
            saved = try store.create(p)
            if let tags = payload.tags {
                try store.setTags(paperID: saved.id!, tags: TagNormalizer.normalize(tags))
            }
        }

        // Best-effort arXiv figure enrichment so cards show a teaser image.
        if saved.teaserURL.isEmpty,
           let id = ArxivService.extractID(from: payload.url),
           let fetch = fetchFigures,
           let figs = try? await fetch(id) {
            saved.teaserURL = figs.teaser ?? ""
            saved.pipelineURL = figs.pipeline ?? ""
            if !(saved.teaserURL.isEmpty && saved.pipelineURL.isEmpty) {
                saved = try store.update(saved)
            }
        }
        return saved
    }
}

extension String { var nonEmpty: String? { isEmpty ? nil : self } }
