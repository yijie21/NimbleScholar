import SwiftUI
import PDFKit

struct ThumbnailSidebar: NSViewRepresentable {
    let pdfView: PDFView

    func makeNSView(context: Context) -> PDFThumbnailView {
        let t = PDFThumbnailView()
        t.pdfView = pdfView
        t.thumbnailSize = NSSize(width: 110, height: 150)
        t.backgroundColor = .clear
        return t
    }

    func updateNSView(_ nsView: PDFThumbnailView, context: Context) {
        nsView.pdfView = pdfView
    }
}
