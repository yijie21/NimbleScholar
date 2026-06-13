import Foundation

public final class CaptureHandler {
    public typealias Resolver = (String) async throws -> PaperMetadata

    let store: LibraryStore
    let resolve: Resolver

    public init(store: LibraryStore, resolve: @escaping Resolver) {
        self.store = store; self.resolve = resolve
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
        let saved = try store.create(p)
        if let tags = payload.tags {
            try store.setTags(paperID: saved.id!, tags: TagNormalizer.normalize(tags))
        }
        return saved
    }
}

extension String { var nonEmpty: String? { isEmpty ? nil : self } }
