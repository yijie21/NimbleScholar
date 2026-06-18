import SwiftUI
import AppKit
import NimbleScholarCore

/// The card figure for a saved link: its og:image (loaded through the app's network session so it
/// honors the proxy), falling back to a placeholder tile keyed to the kind of link (a GitHub glyph
/// or a generic link glyph) plus the host. Fills its frame; the caller sets size + clip.
struct LinkThumbnail: View {
    let link: SavedLink
    var contentMode: ContentMode = .fill
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                LinkPlaceholder(link: link)
            }
        }
        .task(id: link.imagePath + "|" + link.imageURL) { image = await load() }
    }

    private func load() async -> NSImage? {
        if !link.imagePath.isEmpty, let img = NSImage(contentsOfFile: link.imagePath) { return img }
        guard !link.imageURL.isEmpty, let u = URL(string: link.imageURL) else { return nil }
        if let (data, _) = try? await AppEnvironment.shared.networkSession.data(from: u),
           let img = NSImage(data: data) { return img }
        return nil
    }
}

/// Shown until/unless a figure loads: a soft tinted tile with a kind glyph and the host.
struct LinkPlaceholder: View {
    let link: SavedLink
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 6) {
                Image(systemName: link.isGitHub ? "chevron.left.forwardslash.chevron.right" : "link")
                    .font(.system(size: 30, weight: .semibold))
                Text(link.host).font(.caption).lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(8)
        }
    }
}
