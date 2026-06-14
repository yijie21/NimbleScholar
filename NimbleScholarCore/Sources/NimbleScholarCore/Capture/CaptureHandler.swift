import Foundation

public final class CaptureHandler {
    public typealias Resolver = (String) async throws -> PaperMetadata
    /// Optional arXiv figure fetcher (by arXiv id). Left nil in unit tests to stay offline.
    /// `@Sendable` so it can run in a background enrichment task after capture returns.
    public typealias FigureFetcher = @Sendable (String) async throws -> FigureChooser.Result

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
        p.teaserURL = absolutize(payload.teaser_url?.nonEmpty ?? meta.teaserURL, base: payload.url)
        p.pdfURL = absolutize(
            payload.pdf_url?.nonEmpty ?? ArxivService.normalizedPDFURL(absOrID: payload.url) ?? meta.pdfURL,
            base: payload.url)
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

        // arXiv figure enrichment runs in the BACKGROUND so capture returns immediately;
        // the teaser fills in a moment later and the UI refreshes via DB observation.
        if saved.teaserURL.isEmpty,
           let id = ArxivService.extractID(from: payload.url),
           let fetch = fetchFigures,
           let pid = saved.id {
            let store = self.store
            Task {
                guard let figs = try? await fetch(id),
                      figs.teaser != nil || figs.pipeline != nil,
                      var paper = try? store.paper(id: pid) else { return }
                paper.teaserURL = figs.teaser ?? ""
                paper.pipelineURL = figs.pipeline ?? ""
                _ = try? store.update(paper)
            }
        }
        return saved
    }

    /// Resolve a possibly-relative URL (e.g. CVF's `citation_pdf_url`) against the page URL.
    private func absolutize(_ urlString: String, base: String) -> String {
        guard !urlString.isEmpty, !urlString.hasPrefix("http") else { return urlString }
        if let baseURL = URL(string: base), let resolved = URL(string: urlString, relativeTo: baseURL) {
            return resolved.absoluteString
        }
        return urlString
    }
}

extension String { var nonEmpty: String? { isEmpty ? nil : self } }
