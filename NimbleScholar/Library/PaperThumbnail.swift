import SwiftUI
import PDFKit
import AppKit
import NimbleScholarCore

/// Shows the paper's teaser/pipeline image if present; otherwise renders the cached
/// PDF's first page; otherwise a placeholder. Fills its frame (caller sets size + clip).
struct PaperThumbnail: View {
    let paper: Paper

    private var imageURL: URL? {
        let s = paper.teaserURL.isEmpty ? paper.pipelineURL : paper.teaserURL
        return s.isEmpty ? nil : URL(string: s)
    }

    var body: some View {
        if let url = imageURL {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Placeholder() }
        } else if !paper.pdfPath.isEmpty {
            PDFFirstPage(path: paper.pdfPath)
        } else {
            Placeholder()
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

private struct PDFFirstPage: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Placeholder()
            }
        }
        .task(id: path) { await render() }
    }

    private func render() async {
        guard image == nil else { return }
        let p = path
        let rendered = await Task.detached(priority: .utility) { () -> NSImage? in
            guard FileManager.default.fileExists(atPath: p),
                  let doc = PDFDocument(url: URL(fileURLWithPath: p)),
                  let page = doc.page(at: 0) else { return nil }
            return page.thumbnail(of: NSSize(width: 420, height: 560), for: .mediaBox)
        }.value
        await MainActor.run { self.image = rendered }
    }
}
