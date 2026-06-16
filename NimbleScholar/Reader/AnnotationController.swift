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

    /// Fixed accent for the little "has a note" dot, so it reads the same regardless of the
    /// highlight color, and lets notes show a distinct swatch in the Annotations list.
    static let noteDotHex = "#4a90d9"
    static var noteDotColor: NSColor { NSColor(hex: noteDotHex) }

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

    /// Remove an annotation tapped on the page together with everything else in the same indexed
    /// region (a note's highlights + dot, or a multi-line highlight's rectangles), and drop the row.
    func deleteAnnotation(_ annotation: PDFAnnotation, on page: PDFPage, pdfView: PDFView) {
        guard let pageIndex = pdfView.document?.index(for: page) else { return }
        let match = row(for: annotation, on: page, pageIndex: pageIndex)
        if let m = match {
            removeAnnotations(inRegionOf: m, on: page)
        } else {
            page.removeAnnotation(annotation)
        }
        persist(pdfView)
        if let id = match?.id { try? vm.store.deleteAnnotation(id: id) }
        vm.refreshAnnotations()
    }

    /// Delete an annotation chosen from the inspector list: remove every PDFAnnotation in its
    /// recorded region from the file (highlights + any note dot), then drop the row.
    func deleteIndexed(_ row: AnnotationIndex, pdfView: PDFView) {
        if let page = pdfView.document?.page(at: row.page - 1) {
            removeAnnotations(inRegionOf: row, on: page)
            vm.scheduleSave()
        }
        if let id = row.id { try? vm.store.deleteAnnotation(id: id) }
        vm.refreshAnnotations()
    }

    /// The page region (PDF coordinates) recorded for an index row, expanded slightly so a note's
    /// trailing dot and a multi-line selection's per-line rectangles are all covered.
    private func pageRegion(for row: AnnotationIndex, on page: PDFPage) -> CGRect? {
        let pr = page.bounds(for: .mediaBox)
        guard pr.width > 0, pr.height > 0 else { return nil }
        return CGRect(x: CGFloat(row.x) * pr.width, y: CGFloat(row.y) * pr.height,
                      width: CGFloat(row.width) * pr.width, height: CGFloat(row.height) * pr.height)
            .insetBy(dx: -16, dy: -6)
    }

    /// Remove every annotation intersecting an index row's region (its highlights + any note dot).
    private func removeAnnotations(inRegionOf row: AnnotationIndex, on page: PDFPage) {
        guard let region = pageRegion(for: row, on: page) else { return }
        for a in page.annotations where region.intersects(a.bounds) { page.removeAnnotation(a) }
    }

    /// The index row a clicked annotation belongs to: the row whose region contains it, else the
    /// nearest by normalized origin.
    private func row(for annotation: PDFAnnotation, on page: PDFPage, pageIndex: Int) -> AnnotationIndex? {
        guard let pid = vm.paper.id else { return nil }
        let rows = ((try? vm.store.annotations(forPaper: pid)) ?? []).filter { $0.page == pageIndex + 1 }
        if let hit = rows.first(where: { (pageRegion(for: $0, on: page) ?? .null).intersects(annotation.bounds) }) {
            return hit
        }
        let pr = page.bounds(for: .mediaBox)
        guard pr.width > 0, pr.height > 0 else { return nil }
        let nx = Double(annotation.bounds.minX / pr.width), ny = Double(annotation.bounds.minY / pr.height)
        return rows.min(by: { hypot($0.x - nx, $0.y - ny) < hypot($1.x - nx, $1.y - ny) })
    }

    /// Drop index rows whose page no longer has any annotation near them — the PDF file is the
    /// source of truth, so this keeps the Annotations list honest after edits in other apps.
    func reconcile(pdfView: PDFView) {
        guard let pid = vm.paper.id, let doc = pdfView.document else { return }
        for row in (try? vm.store.annotations(forPaper: pid)) ?? [] {
            guard let page = doc.page(at: row.page - 1) else { continue }
            let pageRect = page.bounds(for: .mediaBox)
            guard pageRect.width > 0 else { continue }
            let tx = CGFloat(row.x) * pageRect.width, ty = CGFloat(row.y) * pageRect.height
            let near = page.annotations.contains { hypot($0.bounds.minX - tx, $0.bounds.minY - ty) < 8 }
            if !near, let id = row.id { try? vm.store.deleteAnnotation(id: id) }
        }
        vm.refreshAnnotations()
    }

    /// Highlight the selected sentence and attach a note: each line is highlighted in the current
    /// color, a small dot is drawn just past the end of the last line, and the note text is stored
    /// on the annotations (hover shows it) and indexed as kind "note".
    func addNote(text: String, selection: PDFSelection, in pdfView: PDFView) {
        guard let page = selection.pages.first,
              let pageIndex = pdfView.document?.index(for: page) else { return }
        let color = NSColor(hex: AnnotationController.highlightHex)
        var firstLine: CGRect?
        for line in selection.selectionsByLine() {
            let b = line.bounds(for: page)
            guard b.width > 0, b.height > 0 else { continue }
            let a = PDFAnnotation(bounds: b, forType: .highlight, withProperties: nil)
            a.color = color
            a.contents = text
            page.addAnnotation(a)
            if firstLine == nil { firstLine = b }
        }
        guard let topLine = firstLine else { return }   // nothing highlightable
        // Put the dot out in the blank side margin so it never overlaps text: left margin if the
        // selection sits entirely left of the page centre (e.g. a 2-column left item), else right.
        let sel = selection.bounds(for: page)
        let pageBox = page.bounds(for: .mediaBox)
        let d: CGFloat = 7, gap: CGFloat = 8
        let onLeft = sel.maxX < pageBox.midX
        // Sit just outside the selected text on the chosen side (in the margin/gutter whitespace),
        // clamped to the page — close to the words rather than out at the page edge.
        let dotX = onLeft ? max(pageBox.minX + 2, sel.minX - gap - d)
                          : min(pageBox.maxX - d - 2, sel.maxX + gap)
        let dotRect = CGRect(x: dotX, y: topLine.midY - d / 2, width: d, height: d)
        let dot = PDFAnnotation(bounds: dotRect, forType: .circle, withProperties: nil)
        dot.color = AnnotationController.noteDotColor
        dot.interiorColor = AnnotationController.noteDotColor
        let border = PDFBorder(); border.lineWidth = 0.5; dot.border = border
        dot.contents = text
        page.addAnnotation(dot)
        persist(pdfView)
        // Index the union of the text and the margin dot so region-delete removes both together.
        index(kind: "note", color: AnnotationController.noteDotHex, snippet: text,
              bounds: sel.union(dotRect), on: page, pageIndex: pageIndex)
        pdfView.clearSelection()
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
        // Annotation is already on screen; coalesce the (whole-file) write off the
        // interaction path so highlighting/deleting feels instant.
        vm.scheduleSave()
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
