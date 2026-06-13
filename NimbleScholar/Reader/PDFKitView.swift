import SwiftUI
import PDFKit
import CoreImage

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var displayMode: PDFDisplayMode
    @AppStorage("nightReading") private var nightReading = false
    let onReady: (PDFView) -> Void

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.autoScales = true
        v.displayMode = displayMode
        v.displayDirection = .vertical
        v.wantsLayer = true
        onReady(v)
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        if v.document !== document { v.document = document }
        v.displayMode = displayMode
        v.layer?.filters = nightReading ? [CIFilter(name: "CIColorInvert")!] : []
    }
}
