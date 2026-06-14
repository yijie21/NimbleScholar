import SwiftUI
import PDFKit
import AppKit
import NimbleScholarCore

/// Creates PDFAnnotations, writes them into the PDF file, and indexes them in SQLite.
@MainActor
struct AnnotationController {
    let vm: ReaderViewModel

    /// Currently selected highlight color (hex), from Settings/toolbar.
    static var highlightHex: String { UserDefaults.standard.string(forKey: "highlightColorHex") ?? "#ffd966" }

    /// Text-aware highlight: one highlight rectangle per selected line.
    func highlight(selection: PDFSelection, in pdfView: PDFView) {
        guard let page = selection.pages.first,
              let pageIndex = pdfView.document?.index(for: page) else { return }
        let hex = AnnotationController.highlightHex
        let color = NSColor(hex: hex)
        for line in selection.selectionsByLine() {
            let bounds = line.bounds(for: page)
            let a = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            a.color = color
            page.addAnnotation(a)
        }
        persist(pdfView)
        index(kind: "highlight", color: hex, snippet: selection.string ?? "",
              bounds: selection.bounds(for: page), on: page, pageIndex: pageIndex)
        pdfView.clearSelection()
    }

    /// Remove an annotation tapped on the page, and its nearest index row.
    func deleteAnnotation(_ annotation: PDFAnnotation, on page: PDFPage, pdfView: PDFView) {
        guard let pageIndex = pdfView.document?.index(for: page) else { return }
        let pageRect = page.bounds(for: .mediaBox)
        let b = annotation.bounds
        page.removeAnnotation(annotation)
        persist(pdfView)
        if pageRect.width > 0, pageRect.height > 0, let pid = vm.paper.id {
            let nx = Double(b.minX / pageRect.width), ny = Double(b.minY / pageRect.height)
            let onPage = ((try? vm.store.annotations(forPaper: pid)) ?? []).filter { $0.page == pageIndex + 1 }
            if let nearest = onPage.min(by: { hypot($0.x - nx, $0.y - ny) < hypot($1.x - nx, $1.y - ny) }),
               let id = nearest.id {
                try? vm.store.deleteAnnotation(id: id)
            }
        }
        vm.refreshAnnotations()
    }

    func addNote(text: String, at point: CGPoint, on page: PDFPage, pdfView: PDFView) {
        guard let pageIndex = pdfView.document?.index(for: page) else { return }
        let rect = CGRect(x: point.x, y: point.y, width: 22, height: 22)
        let note = PDFAnnotation(bounds: rect, forType: .text, withProperties: nil)
        note.contents = text
        note.color = NSColor(red: 0.49, green: 0.77, blue: 1, alpha: 1)
        page.addAnnotation(note)
        persist(pdfView)
        index(kind: "note", color: "#7cc4ff", snippet: text, bounds: rect, on: page, pageIndex: pageIndex)
    }

    private func index(kind: String, color: String, snippet: String,
                       bounds: CGRect, on page: PDFPage, pageIndex: Int) {
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return }
        var idx = AnnotationIndex(
            id: nil, paperId: vm.paper.id ?? -1, page: pageIndex + 1, kind: kind, color: color,
            snippet: snippet,
            x: Double(bounds.minX / pageRect.width), y: Double(bounds.minY / pageRect.height),
            width: Double(bounds.width / pageRect.width), height: Double(bounds.height / pageRect.height),
            createdAt: 0, updatedAt: 0)
        _ = try? vm.store.upsertAnnotation(&idx)
        vm.refreshAnnotations()
    }

    private func persist(_ pdfView: PDFView) {
        if let u = vm.localURL { pdfView.document?.write(to: u) }
    }

    /// Modal prompt for note text (shared by the toolbar button and the right-click menu).
    static func promptNoteText() -> String? {
        let alert = NSAlert()
        alert.messageText = "New note"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return field.stringValue
    }
}

extension CGRect { var center: CGPoint { CGPoint(x: midX, y: midY) } }

extension NSColor {
    convenience init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                  green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255,
                  alpha: 1)
    }
}
