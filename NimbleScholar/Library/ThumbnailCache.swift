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
            trimDiskIfNeeded()
        }
        return produced
    }

    /// Render + cache in the background so the first scroll is instant.
    func prewarm(_ papers: [Paper]) {
        Task { for p in papers { _ = await image(for: p) } }
    }

    private let maxBytes: UInt64 = 200 * 1024 * 1024  // 200 MB

    /// Keep the on-disk cache bounded by evicting the oldest files.
    private func trimDiskIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        var total: UInt64 = 0
        var items: [(url: URL, date: Date, size: UInt64)] = []
        for url in files {
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = UInt64(v?.fileSize ?? 0)
            items.append((url, v?.contentModificationDate ?? .distantPast, size))
            total += size
        }
        guard total > maxBytes else { return }
        for item in items.sorted(by: { $0.date < $1.date }) {   // oldest first
            try? fm.removeItem(at: item.url)
            total -= item.size
            if total <= maxBytes { break }
        }
    }

    private func produce(for paper: Paper) async -> NSImage? {
        // 1) Teaser figure, else pipeline figure, from the web (a broken teaser URL must not
        //    block the pipeline figure, and neither should fall straight through to the PDF).
        for remote in [paper.teaserURL, paper.pipelineURL] where !remote.isEmpty {
            if let url = URL(string: remote),
               let (data, _) = try? await AppEnvironment.shared.networkSession.data(from: url),
               let img = NSImage(data: data) {
                return downscaled(img)
            }
        }
        // 2) No web figure: pull the teaser/pipeline image out of the PDF itself; only if the
        //    PDF has no usable embedded figure (e.g. vector-only) do we render the first page.
        let path = paper.pdfPath
        if !path.isEmpty {
            return await Task.detached(priority: .utility) { () -> NSImage? in
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                if let figure = PDFFigureExtractor.extractFigure(fromPDFAt: path) { return figure }
                guard let doc = PDFDocument(url: URL(fileURLWithPath: path)),
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
