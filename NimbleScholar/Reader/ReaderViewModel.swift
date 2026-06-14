import SwiftUI
import PDFKit
import NimbleScholarCore

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
        let all = (try? AppEnvironment.shared.store.allPapers()) ?? []
        self.paper = all.first { $0.id == paperID } ?? Paper(title: "Unknown paper")
    }

    func load() async {
        do {
            let url = try await downloader.ensureLocalPDF(for: paper)
            self.localURL = url
            // Persist the cached path so library thumbnails / future opens find it.
            if paper.pdfPath != url.path {
                var p = paper; p.pdfPath = url.path; _ = try? store.update(p)
            }
            self.document = PDFDocument(url: url)
            self.status = document == nil ? "Could not open PDF" : "Ready"
            refreshAnnotations()
        } catch {
            self.status = "PDF unavailable — use Browser"
        }
    }

    func refreshAnnotations() {
        if let id = paper.id { annotations = (try? store.annotations(forPaper: id)) ?? [] }
    }

    // MARK: - Reading position

    private var positionKey: String { "readingPage.\(paper.id ?? -1)" }
    var savedPageIndex: Int { UserDefaults.standard.integer(forKey: positionKey) }
    func savePage(_ index: Int) { UserDefaults.standard.set(index, forKey: positionKey) }
}
