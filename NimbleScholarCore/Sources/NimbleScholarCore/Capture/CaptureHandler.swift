import Foundation

/// Where to scrape a captured paper's teaser/pipeline figure from.
public enum FigureSource: Equatable, Sendable {
    case arxiv(id: String)     // arxiv.org/html/<id> (then ar5iv)
    case page(url: String)     // the paper's HTML landing page (CVF, publishers, …)
}

public final class CaptureHandler {
    public typealias Resolver = (String) async throws -> PaperMetadata
    /// Optional figure fetcher. Left nil in unit tests to stay offline.
    /// `@Sendable` so it can run in a background enrichment task after capture returns.
    public typealias FigureFetcher = @Sendable (FigureSource) async throws -> FigureChooser.Result
    /// Optional sink for human-readable capture problems (e.g. metadata couldn't be
    /// fetched). The app shows these as a macOS notification; nil in unit tests.
    public typealias IssueReporter = (String) -> Void

    let store: LibraryStore
    let resolve: Resolver
    let fetchFigures: FigureFetcher?
    let reportIssue: IssueReporter?

    public init(store: LibraryStore, resolve: @escaping Resolver,
                fetchFigures: FigureFetcher? = nil, reportIssue: IssueReporter? = nil) {
        self.store = store; self.resolve = resolve
        self.fetchFigures = fetchFigures; self.reportIssue = reportIssue
    }

    @discardableResult
    public func capture(_ payload: CapturePayload) async throws -> Paper {
        // Skip the HTML metadata fetch for direct PDF links (nothing to parse, and it
        // would otherwise download the whole PDF just to scrape <meta> tags). Exception:
        // a CVF raw-PDF URL maps to its small abstract page, which has the full metadata.
        var meta = PaperMetadata()
        var resolveError: String?
        let resolveURL = Self.looksLikePDFURL(payload.url)
            ? MetadataService.cvfLandingURL(forPDF: payload.url) : payload.url
        if let resolveURL {
            do { meta = try await resolve(resolveURL) }
            catch { resolveError = error.localizedDescription }
        }
        // No usable title from the page payload OR the resolver ⇒ the capture landed
        // without metadata (commonly a network/proxy problem). Tell the user, instead of
        // silently saving a paper whose title is just the URL.
        let resolvedTitle = payload.title?.nonEmpty ?? meta.title.nonEmpty
        if resolvedTitle == nil {
            let detail = resolveError.map { " (\($0))" } ?? ""
            reportIssue?("Couldn't fetch the paper's details for \(payload.url)\(detail). "
                + "Check your network or proxy in Settings ▸ General ▸ Downloads.")
        }
        var p = Paper(title: resolvedTitle ?? payload.url)
        p.authors = payload.authors?.nonEmpty ?? meta.authors
        p.year = meta.year
        p.doi = payload.doi?.nonEmpty ?? meta.doi
        p.url = payload.url
        p.abstract = payload.abstract?.nonEmpty ?? meta.abstract
        p.source = payload.source ?? ""
        // Browser payloads pass the page's og:image through, which on OpenReview/publisher
        // pages is the site logo — drop those so real figure enrichment can fill in later.
        let payloadTeaser = payload.teaser_url?.nonEmpty.flatMap {
            FigureChooser.isPlaceholder($0) ? nil : $0
        }
        p.teaserURL = absolutize(payloadTeaser ?? meta.teaserURL, base: payload.url)
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

        // Figure enrichment runs in the BACKGROUND so capture returns immediately;
        // the teaser fills in a moment later and the UI refreshes via DB observation.
        if saved.teaserURL.isEmpty,
           let source = Self.figureSource(payloadURL: payload.url, metaArxivID: meta.arxivID),
           let fetch = fetchFigures,
           let pid = saved.id {
            let store = self.store
            Task {
                guard let figs = try? await fetch(source),
                      figs.teaser != nil || figs.pipeline != nil,
                      var paper = try? store.paper(id: pid) else { return }
                paper.teaserURL = figs.teaser ?? ""
                paper.pipelineURL = figs.pipeline ?? ""
                _ = try? store.update(paper)
            }
        }
        return saved
    }

    /// Where to scrape figures for a captured paper: an arXiv id (from the URL, or harvested
    /// from the landing page — e.g. CVF's [arXiv] link), else the paper's HTML landing page.
    /// OpenReview pages sit behind a browser check and render no figures, so they get no
    /// source here — their cards fall back to PDF figure extraction once the PDF downloads.
    static func figureSource(payloadURL: String, metaArxivID: String) -> FigureSource? {
        if let id = ArxivService.extractID(from: payloadURL) { return .arxiv(id: id) }
        if !metaArxivID.isEmpty { return .arxiv(id: metaArxivID) }
        if OpenReviewService.extractID(from: payloadURL) != nil { return nil }
        if let landing = MetadataService.cvfLandingURL(forPDF: payloadURL) { return .page(url: landing) }
        if !looksLikePDFURL(payloadURL), payloadURL.hasPrefix("http") { return .page(url: payloadURL) }
        return nil
    }

    static func looksLikePDFURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasSuffix(".pdf") || lower.contains(".pdf?")
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
