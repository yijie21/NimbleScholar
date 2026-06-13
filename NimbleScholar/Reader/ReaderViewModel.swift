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
}
