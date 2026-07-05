import SwiftUI
import PDFKit
import NimbleScholarCore

/// Drives one reader window: loads (downloading if needed) the paper's PDF, tracks its annotation
/// index, marks the paper read on open, remembers the last page, and debounces whole-file saves so
/// annotating stays responsive. The PDF file is the source of truth for annotation geometry.
@MainActor
final class ReaderViewModel: ObservableObject {
    @Published var document: PDFDocument?
    @Published var status = "Loading…"
    @Published var annotations: [AnnotationIndex] = []

    let paper: Paper
    let store = AppEnvironment.shared.store
    let downloader = AppEnvironment.shared.downloader
    var localURL: URL?

    init(paperID: Int64?) {
        if let pid = paperID, let found = (try? AppEnvironment.shared.store.paper(id: pid)) ?? nil {
            self.paper = found
        } else {
            self.paper = Paper(title: "Unknown paper")
        }
    }

    func load() async {
        ActivityCenter.shared.begin("Downloading PDF — \(paper.title)")
        defer { ActivityCenter.shared.end() }
        do {
            let url = try await downloader.ensureLocalPDF(for: paper)
            self.localURL = url
            // Persist the cached path so library thumbnails / future opens find it.
            if paper.pdfPath != url.path {
                var p = paper; p.pdfPath = url.path; _ = try? store.update(p, touch: false)
            }
            // Parse the PDF off the main thread so it doesn't block the open animation.
            let doc = await Self.loadDocument(url)
            self.document = doc
            self.status = doc == nil ? "Could not open PDF" : "Ready"
            if let id = paper.id { try? store.removeTag(LibraryViewModel.toReadTag, fromPaper: id) }
            refreshAnnotations()
        } catch {
            self.status = "PDF unavailable — use Browser"
        }
    }

    func refreshAnnotations() {
        if let id = paper.id { annotations = (try? store.annotations(forPaper: id)) ?? [] }
    }

    /// Create the PDFDocument off the main thread (parsing can be heavy for large files),
    /// so opening the reader doesn't stutter the transition animation.
    nonisolated static func loadDocument(_ url: URL) async -> PDFDocument? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: PDFDocument(url: url))
            }
        }
    }

    // MARK: - Debounced PDF persistence
    // Writing the whole PDF on every annotation stalls the UI; coalesce writes instead.
    private var saveWork: DispatchWorkItem?

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func flushSave() {
        saveWork?.cancel(); saveWork = nil
        writeNow()
    }

    private func writeNow() {
        guard let url = localURL, let doc = document else { return }
        doc.write(to: url)
    }

    // MARK: - Reading position

    private var positionKey: String { "readingPage.\(paper.id ?? -1)" }
    var savedPageIndex: Int { UserDefaults.standard.integer(forKey: positionKey) }
    func savePage(_ index: Int) { UserDefaults.standard.set(index, forKey: positionKey) }
}
