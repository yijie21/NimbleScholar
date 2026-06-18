import Foundation

/// Saves a captured webpage / GitHub link into the `links` table. When the page payload lacks a
/// title or figure, it resolves them from the page's `<meta>` tags (og:title / og:image), the same
/// way paper capture does — GitHub repos yield their social-preview card as the figure.
public final class LinkCaptureHandler {
    /// Resolve a URL's metadata (og:title, og:image → teaserURL, og:description → abstract).
    public typealias Resolver = (String) async throws -> PaperMetadata

    let store: LibraryStore
    let resolve: Resolver?

    public init(store: LibraryStore, resolve: Resolver? = nil) {
        self.store = store
        self.resolve = resolve
    }

    @discardableResult
    public func capture(_ payload: LinkCapturePayload) async throws -> SavedLink {
        guard !payload.url.isEmpty else { throw URLError(.badURL) }

        // Fill in whatever the page didn't supply by scraping its <meta> tags.
        var meta = PaperMetadata()
        let needsTitle = (payload.title?.nonEmpty == nil)
        let needsImage = (payload.image_url?.nonEmpty == nil)
        if needsTitle || needsImage, let resolve {
            meta = (try? await resolve(payload.url)) ?? PaperMetadata()
        }

        var link = SavedLink(url: payload.url)
        link.title = payload.title?.nonEmpty ?? meta.title.nonEmpty ?? payload.url
        link.detail = payload.description?.nonEmpty ?? meta.abstract
        link.imageURL = payload.image_url?.nonEmpty ?? meta.teaserURL
        link.source = payload.source?.nonEmpty ?? (link.isGitHub ? "github" : "web")

        let saved: SavedLink
        if let existing = try store.existingLink(forURL: payload.url) {
            // Update in place — keep the original creation time, don't lose a figure we already have.
            link.id = existing.id
            link.createdAt = existing.createdAt
            if link.imageURL.isEmpty { link.imageURL = existing.imageURL }
            if link.imagePath.isEmpty { link.imagePath = existing.imagePath }
            saved = try store.updateLink(link)
        } else {
            saved = try store.createLink(link)
        }
        // Only assign tags when some were actually provided — an empty list must not wipe the tags
        // of a link being re-captured. (Links get no default tag; see the extension.)
        if let tags = payload.tags, let id = saved.id {
            let normalized = TagNormalizer.normalize(tags)
            if !normalized.isEmpty { try store.setLinkTags(linkID: id, tags: normalized) }
        }
        return saved
    }
}
