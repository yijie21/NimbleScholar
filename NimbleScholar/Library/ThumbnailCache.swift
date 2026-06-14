import SwiftUI
import PDFKit
import AppKit
import NimbleScholarCore

/// Two-level thumbnail cache (memory + disk). Each paper's card image is produced
/// once — downloaded teaser figure or rendered PDF first page — then reused instantly.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let memory = NSCache<NSString, NSImage>()
    private let dir: URL

    private init() {
        let base = (try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        dir = base.appendingPathComponent("Nimble Scholar/thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Stable key that changes when a paper's image source changes (so it self-invalidates).
    private func key(for paper: Paper) -> String {
        let src = "\(paper.teaserURL)|\(paper.pipelineURL)|\(paper.pdfPath)"
        var h: UInt64 = 5381
        for b in src.utf8 { h = (h << 5) &+ h &+ UInt64(b) }
        return "\(paper.id ?? 0)-\(h)"
    }

    func image(for paper: Paper) async -> NSImage? {
        let k = key(for: paper) as NSString
        if let cached = memory.object(forKey: k) { return cached }

        let file = dir.appendingPathComponent("\(k).png")
        if let data = try? Data(contentsOf: file), let img = NSImage(data: data) {
            memory.setObject(img, forKey: k)
            return img
        }

        guard let produced = await produce(for: paper) else { return nil }
        memory.setObject(produced, forKey: k)
        if let tiff = produced.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: file)
        }
        return produced
    }

    private func produce(for paper: Paper) async -> NSImage? {
        // 1) Teaser / pipeline figure from the web.
        let remote = paper.teaserURL.isEmpty ? paper.pipelineURL : paper.teaserURL
        if !remote.isEmpty, let url = URL(string: remote),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let img = NSImage(data: data) {
            return downscaled(img)
        }
        // 2) Fallback: render the cached PDF's first page (off the main thread).
        let path = paper.pdfPath
        if !path.isEmpty {
            return await Task.detached(priority: .utility) { () -> NSImage? in
                guard FileManager.default.fileExists(atPath: path),
                      let doc = PDFDocument(url: URL(fileURLWithPath: path)),
                      let page = doc.page(at: 0) else { return nil }
                return page.thumbnail(of: NSSize(width: 480, height: 620), for: .mediaBox)
            }.value
        }
        return nil
    }

    /// Keep cached images modest in size for fast decode and small disk footprint.
    private func downscaled(_ image: NSImage, maxDimension: CGFloat = 640) -> NSImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1, size.width > 0, size.height > 0 else { return image }
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let out = NSImage(size: newSize)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}
