import SwiftUI
import AppKit
import NimbleScholarCore

/// Cached card image: teaser/pipeline figure, else rendered PDF first page, else a
/// placeholder. Backed by ThumbnailCache (memory + disk), so it loads instantly after
/// the first time. Fills its frame (caller sets size + clip).
struct PaperThumbnail: View {
    let paper: Paper
    @State private var image: NSImage?

    private var cacheKey: String { "\(paper.id ?? 0)|\(paper.teaserURL)|\(paper.pipelineURL)|\(paper.pdfPath)" }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Placeholder()
            }
        }
        .task(id: cacheKey) {
            image = await ThumbnailCache.shared.image(for: paper)
        }
    }
}

private struct Placeholder: View {
    var body: some View {
        ZStack {
            Color.gray.opacity(0.08)
            Image(systemName: "doc.text").font(.title2).foregroundStyle(.tertiary)
        }
    }
}
